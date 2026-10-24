package com.example.gymapp.localization

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.streams.toList
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Static guard against `IllegalFormatConversionException` / `MissingFormatArgumentException`
 * at formatted string call sites. It only judges calls whose resource id is a literal
 * `R.string.X` / `R.plurals.X` and whose argument list is plain positional; anything that
 * cannot be decided statically (named, spread or collection arguments) is skipped.
 */
class StringFormatCallSiteTest {
    @Test
    fun formattedResourceCallsPassMatchingArgumentCountAndTypes() {
        val strings = loadFormatSpecs("string")
        val plurals = loadFormatSpecs("plurals")
        val violations = mutableListOf<String>()
        var checkedCalls = 0

        kotlinSources().forEach { file ->
            val text = Files.readString(file)
            findCalls(text).forEach { call ->
                val spec = (if (call.plural) plurals else strings)[call.resourceName] ?: return@forEach
                val formatArgs = call.formatArgs ?: return@forEach
                checkedCalls++
                val location = "${displayPath(file)}:${lineOf(text, call.offset)}"
                val label = "${call.function}(R.${call.kind}.${call.resourceName})"

                val expectedCount = spec.slots.keys.maxOrNull() ?: 0
                if (formatArgs.size != expectedCount) {
                    violations += "$location $label passes ${formatArgs.size} format argument(s) " +
                        "but '${call.resourceName}' expects $expectedCount"
                    return@forEach
                }
                spec.slots.forEach { (index, conversions) ->
                    val argument = formatArgs[index - 1]
                    if (conversions.any { it in NUMERIC_CONVERSIONS } && isClearlyText(argument)) {
                        violations += "$location $label argument $index is text " +
                            "(`${argument.trim().replace(Regex("\\s+"), " ")}`) " +
                            "but '${call.resourceName}' uses %$index\$${conversions.joinToString("/")}"
                    }
                }
            }
        }

        assertTrue("Scanner found no formatted resource calls; it is probably broken", checkedCalls > 50)
        assertTrue(
            "Format call-site mismatches:\n" + violations.joinToString("\n"),
            violations.isEmpty()
        )
    }

    @Test
    fun scannerParsesNestedMultilineAndUndecidableCalls() {
        val source = """
            val a = stringResource(
                R.string.sample,
                foo(1, listOf(2, 3)),
                "x, y",
            )
            val b = context.getString(R.string.sample, "${'$'}{inner(1)}", ')')
            val c = pluralStringResource(R.plurals.sample_plural, n, n, name)
            val d = stringResource(R.string.sample, *args)
            val e = stringResource(R.string.sample, formatArgs = arrayOf(1))
            val f = stringResource(id, 1)
            // stringResource(R.string.commented, 1)
            val g = "stringResource(R.string.quoted, 1)"
            val h = androidx.compose.ui.res.stringResource(R.string.sample)
        """.trimIndent()

        val calls = findCalls(source)
        val byLine = calls.associateBy { lineOf(source, it.offset) }

        assertTrue("expected 6 calls, got ${calls.map { it.function }}", calls.size == 6)
        assertTrue(byLine.getValue(1).formatArgs?.size == 2)
        assertTrue(byLine.getValue(6).formatArgs?.size == 2)
        assertTrue(byLine.getValue(7).plural && byLine.getValue(7).formatArgs?.size == 2)
        assertTrue(byLine.getValue(8).formatArgs == null)
        assertTrue(byLine.getValue(9).formatArgs == null)
        assertTrue(byLine.getValue(13).formatArgs?.isEmpty() == true)
        assertTrue(isClearlyText("\"abc\""))
        assertTrue(isClearlyText("\"${'$'}count items\""))
        assertTrue(isClearlyText("stringResource(R.string.x)"))
        assertTrue(isClearlyText("context.getString(R.string.x, 1)"))
        assertTrue(isClearlyText("value.toString()"))
        assertTrue(!isClearlyText("count"))
        assertTrue(!isClearlyText("if (a) \"x\" else \"y\""))
        assertTrue(!isClearlyText("value?.toString() ?: \"\""))
        assertTrue(!isClearlyText("\"a\" + 1"))
    }

    private class FormatSpec(val slots: Map<Int, Set<Char>>)

    private class Call(
        val function: String,
        val plural: Boolean,
        val kind: String,
        val resourceName: String,
        val offset: Int,
        /** Null when the argument list cannot be judged statically. */
        val formatArgs: List<String>?
    )

    private fun findCalls(text: String): List<Call> {
        val calls = mutableListOf<Call>()
        var i = 0
        while (i < text.length) {
            val c = text[i]
            when {
                text.startsWith("//", i) -> i = skipLineComment(text, i)
                text.startsWith("/*", i) -> i = skipBlockComment(text, i)
                c == '"' -> i = skipString(text, i)
                c == '\'' -> i = skipChar(text, i)
                c.isJavaIdentifierStart() -> {
                    val start = i
                    while (i < text.length && text[i].isJavaIdentifierPart()) i++
                    val name = text.substring(start, i)
                    if (name in STRING_FUNCTIONS || name in PLURAL_FUNCTIONS) {
                        var open = i
                        while (open < text.length && text[open].isWhitespace()) open++
                        if (open < text.length && text[open] == '(' && !isDeclaration(text, start)) {
                            parseCall(text, name, start, open)?.let(calls::add)
                        }
                    }
                }
                else -> i++
            }
        }
        return calls
    }

    private fun parseCall(text: String, function: String, offset: Int, open: Int): Call? {
        val plural = function in PLURAL_FUNCTIONS
        val arguments = splitArguments(text, open) ?: return null
        if (arguments.isEmpty()) return null
        val idMatch = RESOURCE_ID.matchEntire(arguments[0].trim()) ?: return null
        val kind = idMatch.groupValues[1]
        if ((kind == "plurals") != plural) return null
        val name = idMatch.groupValues[2]
        val rest = arguments.drop(if (plural) 2 else 1)
        if (plural && arguments.size < 2) return Call(function, true, kind, name, offset, null)
        val undecidable = arguments.any { argument ->
            val trimmed = argument.trim()
            NAMED_ARGUMENT.containsMatchIn(trimmed) || trimmed.startsWith("*") || trimmed.isEmpty()
        } || rest.any { isCollectionArgument(it.trim()) } || text.hasLambdaAfterCall(open)
        return Call(function, plural, kind, name, offset, if (undecidable) null else rest)
    }

    private fun String.hasLambdaAfterCall(open: Int): Boolean {
        val close = findClosingParen(this, open) ?: return true
        var i = close + 1
        while (i < length && (this[i] == ' ' || this[i] == '\t')) i++
        return i < length && this[i] == '{'
    }

    private fun isCollectionArgument(argument: String): Boolean =
        Regex("^(?:[\\w.]+\\.)?(?:arrayOf|listOf|mutableListOf)\\s*[(<]").containsMatchIn(argument)

    private fun isDeclaration(text: String, nameStart: Int): Boolean {
        val lineStart = text.lastIndexOf('\n', nameStart - 1) + 1
        return FUN_DECLARATION.containsMatchIn(text.substring(lineStart, nameStart))
    }

    /** Splits the top-level arguments of the call whose '(' is at [open]. */
    private fun splitArguments(text: String, open: Int): List<String>? {
        val arguments = mutableListOf<String>()
        var depth = 0
        var argStart = open + 1
        var i = open
        while (i < text.length) {
            val c = text[i]
            when {
                text.startsWith("//", i) -> i = skipLineComment(text, i)
                text.startsWith("/*", i) -> i = skipBlockComment(text, i)
                c == '"' -> i = skipString(text, i)
                c == '\'' -> i = skipChar(text, i)
                c == '(' || c == '[' || c == '{' -> { depth++; i++ }
                c == ')' || c == ']' || c == '}' -> {
                    depth--
                    if (depth == 0) {
                        val last = stripComments(text.substring(argStart, i))
                        if (last.isNotBlank()) arguments += last
                        return arguments
                    }
                    i++
                }
                c == ',' && depth == 1 -> {
                    arguments += stripComments(text.substring(argStart, i))
                    argStart = i + 1
                    i++
                }
                else -> i++
            }
        }
        return null
    }

    private fun findClosingParen(text: String, open: Int): Int? {
        var depth = 0
        var i = open
        while (i < text.length) {
            val c = text[i]
            when {
                text.startsWith("//", i) -> i = skipLineComment(text, i)
                text.startsWith("/*", i) -> i = skipBlockComment(text, i)
                c == '"' -> i = skipString(text, i)
                c == '\'' -> i = skipChar(text, i)
                c == '(' -> { depth++; i++ }
                c == ')' -> { depth--; if (depth == 0) return i; i++ }
                else -> i++
            }
        }
        return null
    }

    private fun stripComments(argument: String): String {
        val out = StringBuilder()
        var i = 0
        while (i < argument.length) {
            when {
                argument.startsWith("//", i) -> i = skipLineComment(argument, i)
                argument.startsWith("/*", i) -> i = skipBlockComment(argument, i)
                argument[i] == '"' -> {
                    val end = skipString(argument, i)
                    out.append(argument, i, end)
                    i = end
                }
                else -> { out.append(argument[i]); i++ }
            }
        }
        return out.toString()
    }

    private fun skipLineComment(text: String, from: Int): Int {
        val end = text.indexOf('\n', from)
        return if (end < 0) text.length else end
    }

    private fun skipBlockComment(text: String, from: Int): Int {
        // Kotlin block comments nest.
        var depth = 0
        var i = from
        while (i < text.length) {
            when {
                text.startsWith("/*", i) -> { depth++; i += 2 }
                text.startsWith("*/", i) -> { depth--; i += 2; if (depth == 0) return i }
                else -> i++
            }
        }
        return text.length
    }

    private fun skipChar(text: String, from: Int): Int {
        var i = from + 1
        while (i < text.length && text[i] != '\'' && text[i] != '\n') {
            if (text[i] == '\\') i++
            i++
        }
        return minOf(i + 1, text.length)
    }

    /** Returns the index just past the string literal that starts at [from]. */
    private fun skipString(text: String, from: Int): Int {
        val raw = text.startsWith("\"\"\"", from)
        var i = from + if (raw) 3 else 1
        while (i < text.length) {
            val c = text[i]
            when {
                raw && text.startsWith("\"\"\"", i) -> {
                    var end = i + 3
                    while (end < text.length && text[end] == '"') end++
                    return end
                }
                !raw && c == '"' -> return i + 1
                !raw && c == '\\' -> i += 2
                c == '$' && i + 1 < text.length && text[i + 1] == '{' -> i = skipTemplate(text, i + 1)
                else -> i++
            }
        }
        return text.length
    }

    private fun skipTemplate(text: String, openBrace: Int): Int {
        var depth = 0
        var i = openBrace
        while (i < text.length) {
            when (text[i]) {
                '{' -> { depth++; i++ }
                '}' -> { depth--; i++; if (depth == 0) return i }
                '"' -> i = skipString(text, i)
                '\'' -> i = skipChar(text, i)
                else -> i++
            }
        }
        return text.length
    }

    /**
     * A clear text value: one string literal/template, one string-producing call, or a trailing
     * `.toString()`. Conditionals, elvis chains and concatenations are left undecided.
     */
    private fun isClearlyText(argument: String): Boolean {
        val trimmed = argument.trim()
        if (trimmed.isEmpty()) return false
        if (trimmed.startsWith("\"")) return skipString(trimmed, 0) == trimmed.length
        STRING_PRODUCING_CALL.find(trimmed)?.let { match ->
            val open = match.range.last
            if (findClosingParen(trimmed, open) == trimmed.length - 1) return true
        }
        if (trimmed.endsWith(".toString()")) {
            val receiver = trimmed.removeSuffix(".toString()")
            return receiver.isNotBlank() && !UNDECIDED_OPERATOR.containsMatchIn(withoutNested(receiver))
        }
        return false
    }

    /** Blanks parenthesised / quoted parts so operator detection only sees the top level. */
    private fun withoutNested(expression: String): String {
        val out = StringBuilder()
        var depth = 0
        var i = 0
        while (i < expression.length) {
            val c = expression[i]
            when {
                c == '"' -> { i = skipString(expression, i); continue }
                c == '(' || c == '[' || c == '{' -> depth++
                c == ')' || c == ']' || c == '}' -> depth--
                depth == 0 -> out.append(c)
            }
            i++
        }
        return out.toString()
    }

    private fun loadFormatSpecs(tag: String): Map<String, FormatSpec> {
        val document = DocumentBuilderFactory.newInstance().apply {
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            setFeature("http://xml.org/sax/features/external-general-entities", false)
            setFeature("http://xml.org/sax/features/external-parameter-entities", false)
            setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
            isXIncludeAware = false
            isExpandEntityReferences = false
        }.newDocumentBuilder().parse(
            Files.newInputStream(appPath("src/main/res/values/strings.xml")).use { it.readAllBytes().inputStream() }
        )
        val nodes = document.getElementsByTagName(tag)
        return buildMap {
            for (index in 0 until nodes.length) {
                val node = nodes.item(index)
                val name = node.attributes.getNamedItem("name").nodeValue
                val formatted = node.attributes.getNamedItem("formatted")?.nodeValue
                if (formatted == "false") continue
                val text = if (tag == "plurals") {
                    val children = node.childNodes
                    (0 until children.length)
                        .map { children.item(it) }
                        .firstOrNull { it.nodeName == "item" && it.attributes.getNamedItem("quantity").nodeValue == "other" }
                        ?.textContent
                        ?: error("Plural '$name' has no 'other' item")
                } else {
                    node.textContent
                }
                put(name, FormatSpec(parseSlots(text)))
            }
        }
    }

    private fun parseSlots(text: String): Map<Int, Set<Char>> {
        val slots = sortedMapOf<Int, MutableSet<Char>>()
        var sequential = 0
        SPECIFIER.findAll(text).forEach { match ->
            val conversion = match.groupValues[3].single()
            if (conversion == '%' || conversion == 'n') return@forEach
            val explicit = match.groupValues[1].takeIf { it.isNotEmpty() }?.toInt()
            val index = explicit ?: (++sequential)
            slots.getOrPut(index) { mutableSetOf() } += conversion
        }
        return slots
    }

    private fun kotlinSources(): List<Path> {
        val root = appPath("src/main/java")
        return Files.walk(root).use { stream ->
            stream.filter { Files.isRegularFile(it) && it.toString().endsWith(".kt") }.sorted().toList()
        }
    }

    private fun displayPath(file: Path): String {
        val main = appPath("src/main/java")
        return "app/src/main/java/" + main.relativize(file)
    }

    private fun lineOf(text: String, offset: Int): Int = text.substring(0, offset).count { it == '\n' } + 1

    private fun appPath(relativePath: String): Path {
        val workingDirectory = Paths.get("").toAbsolutePath().normalize()
        val candidates = generateSequence(workingDirectory) { it.parent }
            .flatMap { directory ->
                sequenceOf(
                    directory.resolve(relativePath),
                    directory.resolve("app").resolve(relativePath)
                )
            }
            .distinct()
            .toList()
        return candidates.firstOrNull(Files::exists)
            ?: error("Could not locate app/$relativePath from $workingDirectory")
    }

    private companion object {
        val STRING_FUNCTIONS = setOf(
            "stringResource", "getString", "formattedStringResource", "safeGetString"
        )
        val PLURAL_FUNCTIONS = setOf(
            "pluralStringResource", "getQuantityString",
            "formattedPluralStringResource", "safeGetQuantityString"
        )
        val NUMERIC_CONVERSIONS = setOf('d', 'x', 'X', 'o', 'f', 'e', 'E', 'g', 'G')
        val SPECIFIER = Regex("%(?:(\\d+)\\$)?([-#+ 0,(<]*\\d*(?:\\.\\d+)?)([a-zA-Z%])")
        val RESOURCE_ID = Regex("^(?:[A-Za-z_][\\w]*\\.)*R\\.(string|plurals)\\.([A-Za-z_]\\w*)$")
        val NAMED_ARGUMENT = Regex("^[A-Za-z_]\\w*\\s*=(?!=)")
        val FUN_DECLARATION = Regex("\\bfun\\b[^=]*$")
        val STRING_PRODUCING_CALL = Regex(
            "^(?:[A-Za-z_][\\w]*\\??\\.)*(?:stringResource|pluralStringResource|formattedStringResource|" +
                "formattedPluralStringResource|getString|getQuantityString|safeGetString|safeGetQuantityString)\\s*\\("
        )
        val UNDECIDED_OPERATOR = Regex("\\?:|\\bif\\b|\\bwhen\\b|\\belse\\b|[+*/%]|\\s-\\s|&&|\\|\\|")
    }
}
