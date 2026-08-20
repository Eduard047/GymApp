import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.apache.commons.compress.archivers.sevenz.SevenZArchiveEntry;
import org.apache.commons.compress.archivers.sevenz.SevenZFile;
import org.apache.commons.compress.archivers.sevenz.SevenZMethodConfiguration;
import org.apache.commons.compress.archivers.sevenz.SevenZOutputFile;

/**
 * Release sanitizer and structural readback for a Connect IQ store export.
 *
 * <p>The Connect IQ SDK exposes package signing through monkeyc but does not
 * expose a standalone signature-verification command. Release-key continuity
 * is therefore enforced before monkeyc. This helper rewrites only debug.xml
 * local path prefixes, then reopens the full package and proves that every
 * non-debug entry remains byte-identical.</p>
 */
public final class VerifyGarminIq {
    private static final long MAX_PACKAGE_BYTES = 512L * 1024L * 1024L;
    private static final long MAX_TOTAL_UNCOMPRESSED_BYTES = 1024L * 1024L * 1024L;
    private static final int MAX_DEBUG_XML_BYTES = 16 * 1024 * 1024;
    private static final int MAX_ENTRY_COUNT = 20_000;
    private static final String CANONICAL_PROGRAM_NAME =
        "gymapp-garmin-connect-iq.prg";
    private static final byte[] SEVEN_Z_MAGIC = {
        0x37, 0x7a, (byte) 0xbc, (byte) 0xaf, 0x27, 0x1c
    };
    private static final Pattern UNIX_USER_PREFIX = Pattern.compile(
        "(?<![A-Za-z0-9_])/(?:Users|home)/[^/<>\\\"'\\r\\n]+/"
    );
    private static final Pattern WINDOWS_USER_PREFIX = Pattern.compile(
        "(?i)(?<![A-Za-z0-9_])[A-Z]:[\\\\/]+Users[\\\\/]+" +
        "[^\\\\/<>\\\"'\\r\\n]+[\\\\/]+"
    );
    private static final Pattern WINDOWS_ROOTED_USER_PREFIX = Pattern.compile(
        "(?i)(?<![A-Za-z0-9_])[\\\\/]Users[\\\\/]+" +
        "[^\\\\/<>\\\"'\\r\\n]+[\\\\/]+"
    );
    private static final Pattern WINDOWS_DRIVE_PREFIX = Pattern.compile(
        "(?i)(?<![A-Za-z0-9_])[A-Z]:[\\\\/]+"
    );

    private VerifyGarminIq() {}

    public static void main(String[] args) {
        boolean sanitizing = args.length > 0 && args[0].equals("--sanitize-debug-paths");
        try {
            if (sanitizing) {
                if (args.length != 4) {
                    throw safeFailure(
                        "Expected source IQ, destination IQ, and exact source-root paths."
                    );
                }
                sanitizeDebugPaths(
                    Path.of(args[1]).toAbsolutePath().normalize(),
                    Path.of(args[2]).toAbsolutePath().normalize(),
                    Path.of(args[3])
                );
                System.out.println("Garmin IQ debug paths sanitized and verified.");
            } else {
                if (args.length != 1) {
                    throw safeFailure("Expected exactly one IQ package path.");
                }
                verify(Path.of(args[0]).toAbsolutePath().normalize());
                System.out.println("Garmin IQ structure verified.");
            }
        } catch (SafeIqException error) {
            System.err.println(error.getMessage());
            System.exit(1);
        } catch (Exception error) {
            System.err.println(sanitizing
                ? "Garmin IQ sanitization failed."
                : "Garmin IQ verification failed.");
            System.exit(1);
        }
    }

    static void sanitizeDebugPaths(Path source, Path destination, Path sourceRoot)
            throws IOException {
        if (source.equals(destination)) {
            throw safeFailure("Garmin IQ sanitization requires a separate destination.");
        }
        assertPackageFile(source);
        if (Files.exists(destination)) {
            throw safeFailure("Garmin IQ sanitization destination already exists.");
        }

        try {
            String sourceRootPrefix = exactSourceRootPrefix(sourceRoot);
            Map<String, String> sourceNonDebugHashes = rewriteDebugEntries(
                source,
                destination,
                sourceRootPrefix
            );
            VerificationResult result = verify(destination);
            if (!sourceNonDebugHashes.equals(result.nonDebugHashes)) {
                throw safeFailure("Garmin IQ non-debug entries changed during sanitization.");
            }
        } catch (IOException | RuntimeException error) {
            try {
                Files.deleteIfExists(destination);
            } catch (IOException cleanupError) {
                error.addSuppressed(cleanupError);
            }
            throw error;
        }
    }

    static VerificationResult verify(Path packagePath) throws IOException {
        assertPackageFile(packagePath);

        boolean hasManifest = false;
        boolean hasManifestSignature = false;
        boolean hasDeveloperPublicKey = false;
        boolean hasProgram = false;
        int entryCount = 0;
        int regularEntryCount = 0;
        long totalUncompressedBytes = 0;
        Set<String> names = new HashSet<>();
        Map<String, String> nonDebugHashes = new LinkedHashMap<>();
        byte[] buffer = new byte[64 * 1024];
        try (SevenZFile archive = SevenZFile.builder().setFile(packagePath.toFile()).get()) {
            SevenZArchiveEntry entry;
            while ((entry = archive.getNextEntry()) != null) {
                entryCount++;
                validateEntryNameAndCount(entry, entryCount, names);
                if (entry.isDirectory()) {
                    continue;
                }

                regularEntryCount++;
                totalUncompressedBytes = validateEntrySize(entry, totalUncompressedBytes);
                UnsafePathScanner pathScanner = new UnsafePathScanner(
                    !entry.getName().endsWith(".prg")
                );
                MessageDigest digest = isDebugXml(entry.getName()) ? null : sha256();
                long bytesRead = 0;
                int count;
                while ((count = archive.read(buffer)) != -1) {
                    bytesRead += count;
                    if (bytesRead > entry.getSize()) {
                        throw safeFailure("Garmin IQ package entry exceeds its declared size.");
                    }
                    pathScanner.accept(buffer, 0, count);
                    if (digest != null) {
                        digest.update(buffer, 0, count);
                    }
                }
                if (bytesRead != entry.getSize()) {
                    throw safeFailure("Garmin IQ package entry is truncated.");
                }
                if (pathScanner.hasUnsafePath()) {
                    throw safeFailure("Garmin IQ package contains an unsafe local source path.");
                }
                if (digest != null) {
                    nonDebugHashes.put(entry.getName(), hex(digest.digest()));
                }

                String name = entry.getName();
                hasManifest |= name.equals("manifest.xml");
                hasManifestSignature |= name.equals("manifest.sig2") && entry.getSize() == 512;
                hasDeveloperPublicKey |= name.equals("dev_key.pub") && entry.getSize() >= 512;
                if (name.endsWith(".prg")) {
                    if (!isCanonicalProgramPath(name)) {
                        throw safeFailure(
                            "Garmin IQ package contains a non-canonical compiled program name."
                        );
                    }
                    hasProgram = true;
                }
            }
        }
        if (regularEntryCount == 0 || !hasManifest || !hasManifestSignature ||
                !hasDeveloperPublicKey || !hasProgram) {
            throw safeFailure(
                "Garmin IQ package is missing its manifest, RSA-4096 signature, " +
                "developer public key, or compiled program."
            );
        }
        return new VerificationResult(nonDebugHashes);
    }

    private static Map<String, String> rewriteDebugEntries(
        Path source,
        Path destination,
        String sourceRootPrefix
    ) throws IOException {
        Map<String, String> sourceNonDebugHashes = new LinkedHashMap<>();
        Set<String> names = new HashSet<>();
        int entryCount = 0;
        long totalUncompressedBytes = 0;
        byte[] buffer = new byte[64 * 1024];

        try (
            SevenZFile archive = SevenZFile.builder().setFile(source.toFile()).get();
            SevenZOutputFile output = new SevenZOutputFile(destination.toFile())
        ) {
            SevenZArchiveEntry entry;
            while ((entry = archive.getNextEntry()) != null) {
                entryCount++;
                validateEntryNameAndCount(entry, entryCount, names);
                SevenZArchiveEntry copiedEntry = copyMetadata(entry);
                output.putArchiveEntry(copiedEntry);
                if (entry.isDirectory()) {
                    output.closeArchiveEntry();
                    continue;
                }

                totalUncompressedBytes = validateEntrySize(entry, totalUncompressedBytes);
                if (isDebugXml(entry.getName())) {
                    byte[] original = readDebugXml(archive, entry);
                    byte[] sanitized = sanitizeDebugXml(original, sourceRootPrefix);
                    output.write(sanitized);
                } else {
                    MessageDigest digest = sha256();
                    UnsafePathScanner pathScanner = new UnsafePathScanner(
                        !entry.getName().endsWith(".prg")
                    );
                    long bytesRead = 0;
                    int count;
                    while ((count = archive.read(buffer)) != -1) {
                        bytesRead += count;
                        if (bytesRead > entry.getSize()) {
                            throw safeFailure("Garmin IQ package entry exceeds its declared size.");
                        }
                        pathScanner.accept(buffer, 0, count);
                        if (pathScanner.hasUnsafePath()) {
                            throw safeFailure(
                                "Garmin IQ package contains an unsafe local path outside debug metadata."
                            );
                        }
                        digest.update(buffer, 0, count);
                        output.write(buffer, 0, count);
                    }
                    if (bytesRead != entry.getSize()) {
                        throw safeFailure("Garmin IQ package entry is truncated.");
                    }
                    sourceNonDebugHashes.put(entry.getName(), hex(digest.digest()));
                }
                output.closeArchiveEntry();
            }
        }
        return sourceNonDebugHashes;
    }

    private static byte[] readDebugXml(SevenZFile archive, SevenZArchiveEntry entry)
            throws IOException {
        if (entry.getSize() > MAX_DEBUG_XML_BYTES) {
            throw safeFailure("Garmin IQ debug metadata exceeds the sanitization limit.");
        }
        ByteArrayOutputStream bytes = new ByteArrayOutputStream((int) entry.getSize());
        byte[] buffer = new byte[64 * 1024];
        long bytesRead = 0;
        int count;
        while ((count = archive.read(buffer)) != -1) {
            bytesRead += count;
            if (bytesRead > entry.getSize()) {
                throw safeFailure("Garmin IQ package entry exceeds its declared size.");
            }
            bytes.write(buffer, 0, count);
        }
        if (bytesRead != entry.getSize()) {
            throw safeFailure("Garmin IQ package entry is truncated.");
        }
        return bytes.toByteArray();
    }

    private static byte[] sanitizeDebugXml(byte[] original, String sourceRootPrefix)
            throws IOException {
        String text;
        try {
            text = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(original))
                .toString();
        } catch (CharacterCodingException error) {
            throw safeFailure("Garmin IQ debug metadata is not valid UTF-8.");
        }

        String sanitized = replaceExactSourceRoot(text, sourceRootPrefix);
        sanitized = replacePrefixes(sanitized, WINDOWS_USER_PREFIX);
        sanitized = replacePrefixes(sanitized, WINDOWS_ROOTED_USER_PREFIX);
        sanitized = replacePrefixes(sanitized, UNIX_USER_PREFIX);
        sanitized = replacePrefixes(sanitized, WINDOWS_DRIVE_PREFIX);
        byte[] result = sanitized.getBytes(StandardCharsets.UTF_8);
        if (result.length != original.length) {
            throw safeFailure("Garmin IQ debug path sanitization changed the entry length.");
        }
        UnsafePathScanner scanner = new UnsafePathScanner();
        scanner.accept(result, 0, result.length);
        if (scanner.hasUnsafePath()) {
            throw safeFailure("Garmin IQ debug metadata still contains an unsafe local source path.");
        }
        return result;
    }

    private static String exactSourceRootPrefix(Path sourceRoot) throws IOException {
        if (!sourceRoot.isAbsolute() || !sourceRoot.equals(sourceRoot.normalize()) ||
                sourceRoot.getNameCount() < 2) {
            throw safeFailure("Garmin IQ source root must be an exact normalized absolute path.");
        }
        String prefix = sourceRoot.toString();
        if (prefix.endsWith("/") || prefix.endsWith("\\")) {
            throw safeFailure("Garmin IQ source root must not include a trailing separator.");
        }
        return prefix + File.separator;
    }

    private static String replaceExactSourceRoot(String source, String prefix)
            throws IOException {
        Pattern exactPrefix = Pattern.compile(
            "(?<![A-Za-z0-9_])" + Pattern.quote(prefix)
        );
        Matcher matcher = exactPrefix.matcher(source);
        StringBuffer result = new StringBuffer(source.length());
        while (matcher.find()) {
            int pathEnd = matcher.end();
            while (pathEnd < source.length() && !isPathTerminator(source.charAt(pathEnd))) {
                pathEnd++;
            }
            String remainder = source.substring(matcher.end(), pathEnd)
                .replace('\\', '/');
            for (String segment : remainder.split("/", -1)) {
                if (segment.equals(".") || segment.equals("..")) {
                    throw safeFailure(
                        "Garmin IQ debug source path contains a traversal segment."
                    );
                }
            }
            matcher.appendReplacement(
                result,
                Matcher.quoteReplacement(
                    neutralRelativePrefix(
                        prefix.getBytes(StandardCharsets.UTF_8).length,
                        prefix.charAt(prefix.length() - 1)
                    )
                )
            );
        }
        matcher.appendTail(result);
        return result.toString();
    }

    private static boolean isPathTerminator(char value) {
        return value == '"' || value == '\'' || value == '<' || value == '>' ||
            value == '\r' || value == '\n' || value == '\t' || value == ' ';
    }

    private static String replacePrefixes(String source, Pattern pattern) throws IOException {
        Matcher matcher = pattern.matcher(source);
        StringBuffer result = new StringBuffer(source.length());
        while (matcher.find()) {
            String prefix = matcher.group();
            int byteLength = prefix.getBytes(StandardCharsets.UTF_8).length;
            char separator = prefix.charAt(prefix.length() - 1);
            matcher.appendReplacement(
                result,
                Matcher.quoteReplacement(neutralRelativePrefix(byteLength, separator))
            );
        }
        matcher.appendTail(result);
        return result.toString();
    }

    private static String neutralRelativePrefix(int byteLength, char separator)
            throws IOException {
        if (byteLength < 3 || (separator != '/' && separator != '\\')) {
            throw safeFailure("Garmin IQ debug path prefix is malformed.");
        }
        StringBuilder prefix = new StringBuilder(byteLength);
        prefix.append('r');
        while (prefix.length() < byteLength - 1) {
            prefix.append('_');
        }
        prefix.append(separator);
        return prefix.toString();
    }

    private static SevenZArchiveEntry copyMetadata(SevenZArchiveEntry source) {
        SevenZArchiveEntry copy = new SevenZArchiveEntry();
        copy.setName(source.getName());
        copy.setDirectory(source.isDirectory());
        copy.setAntiItem(source.isAntiItem());
        copy.setSize(source.getSize());
        if (source.getHasCreationDate()) {
            copy.setCreationTime(source.getCreationTime());
        }
        if (source.getHasAccessDate()) {
            copy.setAccessTime(source.getAccessTime());
        }
        if (source.getHasLastModifiedDate()) {
            copy.setLastModifiedTime(source.getLastModifiedTime());
        }
        if (source.getHasWindowsAttributes()) {
            copy.setHasWindowsAttributes(true);
            copy.setWindowsAttributes(source.getWindowsAttributes());
        }
        Iterable<? extends SevenZMethodConfiguration> methods = source.getContentMethods();
        if (methods != null) {
            copy.setContentMethods(methods);
        }
        return copy;
    }

    private static void assertPackageFile(Path packagePath) throws IOException {
        if (!Files.isRegularFile(packagePath) || Files.size(packagePath) < 32 ||
                Files.size(packagePath) > MAX_PACKAGE_BYTES) {
            throw safeFailure("Garmin IQ package is missing, empty, or oversized.");
        }
        byte[] header = new byte[SEVEN_Z_MAGIC.length];
        try (var input = Files.newInputStream(packagePath)) {
            if (input.read(header) != header.length) {
                throw safeFailure("Garmin IQ package header is truncated.");
            }
        }
        for (int index = 0; index < SEVEN_Z_MAGIC.length; index++) {
            if (header[index] != SEVEN_Z_MAGIC[index]) {
                throw safeFailure("Garmin IQ package is not a 7z archive.");
            }
        }
    }

    private static void validateEntryNameAndCount(
        SevenZArchiveEntry entry,
        int entryCount,
        Set<String> names
    ) throws IOException {
        if (entryCount > MAX_ENTRY_COUNT) {
            throw safeFailure("Garmin IQ package contains too many entries.");
        }
        String name = entry.getName();
        if (!isSafeArchivePath(name) || !names.add(name)) {
            throw safeFailure("Garmin IQ package contains an unsafe or duplicate entry.");
        }
    }

    private static long validateEntrySize(SevenZArchiveEntry entry, long total)
            throws IOException {
        if (entry.getSize() <= 0 || entry.getSize() > MAX_PACKAGE_BYTES) {
            throw safeFailure("Garmin IQ package contains an empty or oversized file.");
        }
        if (entry.getSize() > MAX_TOTAL_UNCOMPRESSED_BYTES - total) {
            throw safeFailure("Garmin IQ package expands beyond the readback limit.");
        }
        return total + entry.getSize();
    }

    private static boolean isDebugXml(String name) {
        return name.equals("debug.xml") || name.endsWith("/debug.xml");
    }

    private static boolean isCanonicalProgramPath(String name) {
        return name.equals(CANONICAL_PROGRAM_NAME) ||
            name.endsWith("/" + CANONICAL_PROGRAM_NAME);
    }

    private static MessageDigest sha256() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException("SHA-256 is unavailable.", error);
        }
    }

    private static String hex(byte[] bytes) {
        StringBuilder value = new StringBuilder(bytes.length * 2);
        for (byte item : bytes) {
            value.append(String.format("%02x", item & 0xff));
        }
        return value.toString();
    }

    private static SafeIqException safeFailure(String message) {
        return new SafeIqException(message);
    }

    private static boolean isSafeArchivePath(String name) {
        if (name == null || name.isBlank() || name.indexOf('\0') >= 0) {
            return false;
        }
        String normalized = name.replace('\\', '/');
        if (normalized.startsWith("/") || normalized.matches("^[A-Za-z]:/.*")) {
            return false;
        }
        for (String segment : normalized.split("/", -1)) {
            if (segment.isEmpty() || segment.equals(".") || segment.equals("..")) {
                return false;
            }
        }
        return !new File(name).isAbsolute();
    }

    private static final class VerificationResult {
        private final Map<String, String> nonDebugHashes;

        private VerificationResult(Map<String, String> nonDebugHashes) {
            this.nonDebugHashes = nonDebugHashes;
        }
    }

    private static final class SafeIqException extends IOException {
        private SafeIqException(String message) {
            super(message);
        }
    }

    private static final class UnsafePathScanner {
        private static final int WINDOW_SIZE = 16;
        private final byte[] recent = new byte[WINDOW_SIZE];
        // Compiled PRGs are opaque binary and can contain coincidental `X:/`
        // bytes. Their high-confidence user/temp roots are still scanned; the
        // generic drive-prefix rule remains strict for every textual/non-PRG
        // entry and for sanitized debug metadata.
        private final boolean scanGenericDrivePrefix;
        private int recentLength = 0;
        private long bytesSeen = 0;
        private boolean unsafePath = false;

        private UnsafePathScanner() {
            this(true);
        }

        private UnsafePathScanner(boolean scanGenericDrivePrefix) {
            this.scanGenericDrivePrefix = scanGenericDrivePrefix;
        }

        private void accept(byte[] bytes, int offset, int length) {
            for (int index = offset; index < offset + length && !unsafePath; index++) {
                accept(bytes[index]);
            }
        }

        private void accept(byte value) {
            if (recentLength < recent.length) {
                recent[recentLength++] = value;
            } else {
                System.arraycopy(recent, 1, recent, 0, recent.length - 1);
                recent[recent.length - 1] = value;
            }
            bytesSeen++;
            if (endsWithWindowsUserRoot() || endsWithAscii("/home/", false) ||
                    endsWithAscii("/private/tmp/", false)) {
                unsafePath = true;
                return;
            }
            if (scanGenericDrivePrefix && recentLength >= 3) {
                int driveIndex = recentLength - 3;
                byte drive = recent[driveIndex];
                byte colon = recent[driveIndex + 1];
                byte separator = recent[driveIndex + 2];
                boolean boundary = bytesSeen == 3 ||
                    (recentLength >= 4 && !isIdentifier(recent[driveIndex - 1]));
                if (boundary && isAsciiLetter(drive) && colon == ':' &&
                        (separator == '/' || separator == '\\')) {
                    unsafePath = true;
                }
            }
        }

        private boolean endsWithAscii(String pattern, boolean ignoreCase) {
            if (recentLength < pattern.length()) {
                return false;
            }
            int start = recentLength - pattern.length();
            for (int index = 0; index < pattern.length(); index++) {
                int actual = recent[start + index] & 0xff;
                int expected = pattern.charAt(index);
                if (ignoreCase) {
                    actual = Character.toLowerCase((char) actual);
                    expected = Character.toLowerCase((char) expected);
                }
                if (actual != expected) {
                    return false;
                }
            }
            return true;
        }

        private boolean endsWithWindowsUserRoot() {
            if (recentLength < 7) {
                return false;
            }
            int start = recentLength - 7;
            return isSeparator(recent[start]) &&
                asciiEqualsIgnoreCase(recent[start + 1], 'U') &&
                asciiEqualsIgnoreCase(recent[start + 2], 's') &&
                asciiEqualsIgnoreCase(recent[start + 3], 'e') &&
                asciiEqualsIgnoreCase(recent[start + 4], 'r') &&
                asciiEqualsIgnoreCase(recent[start + 5], 's') &&
                isSeparator(recent[start + 6]);
        }

        private boolean hasUnsafePath() {
            return unsafePath;
        }

        private static boolean isAsciiLetter(byte value) {
            return (value >= 'A' && value <= 'Z') || (value >= 'a' && value <= 'z');
        }

        private static boolean isSeparator(byte value) {
            return value == '/' || value == '\\';
        }

        private static boolean asciiEqualsIgnoreCase(byte actual, char expected) {
            return Character.toLowerCase((char) (actual & 0xff)) ==
                Character.toLowerCase(expected);
        }

        private static boolean isIdentifier(byte value) {
            return isAsciiLetter(value) || (value >= '0' && value <= '9') || value == '_';
        }
    }
}
