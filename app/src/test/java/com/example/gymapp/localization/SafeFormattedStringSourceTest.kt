package com.example.gymapp.localization

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import kotlin.streams.asSequence
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Store-injected translations can break a format template, and a direct formatted call then crashes
 * with IllegalFormatException. Every resource lookup that takes format arguments must therefore go
 * through the helpers in SafeStringResources.kt.
 */
class SafeFormattedStringSourceTest {
    @Test
    fun mainSourcesFormatResourcesOnlyThroughSafeHelpers() {
        val root = appFile("src/main/java")
        val offenders = Files.walk(root).use { paths ->
            paths.asSequence()
                .filter { it.fileName.toString().endsWith(".kt") }
                .filter { it.fileName.toString() != "SafeStringResources.kt" }
                .flatMap { file ->
                    findDirectFormattedCalls(Files.readString(file)).map { "${root.relativize(file)}:$it" }
                }
                .toList()
        }

        assertTrue(
            "Use formattedStringResource / formattedPluralStringResource / safeGetString / " +
                "safeGetQuantityString for resources with format arguments:\n" +
                offenders.joinToString("\n"),
            offenders.isEmpty()
        )
    }

    @Test
    fun scannerFlagsDirectFormattedCallsOnly() {
        val source = """
            val a = stringResource(R.string.plain)
            val b = stringResource(R.string.formatted, name)
            val c = pluralStringResource(R.plurals.count, n)
            val d = pluralStringResource(R.plurals.count, n, n)
            val e = context.getString(R.string.plain)
            val f = context.getString(R.string.formatted, "x, y")
            val g = resources.getQuantityString(R.plurals.count, n, n)
            val h = preferences.getString("key", null)
            val i = formattedStringResource(R.string.formatted, name)
            val j = context.safeGetString(R.string.formatted, name)
            // stringResource(R.string.commented, name)
            val k = androidx.compose.ui.res.stringResource(R.string.formatted, name)
            val l = getString(textId, *args)
        """.trimIndent()

        assertEquals(listOf(2, 4, 6, 7, 12, 13), findDirectFormattedCalls(source))
    }

    private fun appFile(relativePath: String): Path {
        val workingDirectory = Paths.get("").toAbsolutePath().normalize()
        return generateSequence(workingDirectory) { it.parent }
            .flatMap { directory ->
                sequenceOf(
                    directory.resolve(relativePath),
                    directory.resolve("app").resolve(relativePath)
                )
            }
            .distinct()
            .firstOrNull(Files::isDirectory)
            ?: error("Could not locate app/$relativePath")
    }

    /** 1-based line numbers of lookups that pass format arguments without the safe helpers. */
    private fun findDirectFormattedCalls(source: String): List<Int> {
        val code = blankOutCommentsAndLiterals(source)
        return CALL.findAll(code).mapNotNull { match ->
            val arguments = topLevelArguments(code, match.range.last)
            val extraArguments = arguments.size - if (match.groupValues[1] == "stringResource" ||
                match.groupValues[1] == "getString"
            ) {
                1
            } else {
                2
            }
            val isPreferencesLookup = match.groupValues[1] == "getString" &&
                arguments.getOrNull(1)?.trim() == "null"
            if (extraArguments > 0 && !isPreferencesLookup) {
                source.substring(0, match.range.first).count { it == '\n' } + 1
            } else {
                null
            }
        }.toList()
    }

    /** Replaces comments and literal contents with spaces so only real code is scanned (offsets kept). */
    private fun blankOutCommentsAndLiterals(source: String): String {
        val out = StringBuilder(source)
        var i = 0
        fun blank(from: Int, to: Int) {
            for (k in from until minOf(to, out.length)) if (out[k] != '\n') out[k] = ' '
        }
        while (i < source.length) {
            when {
                source.startsWith("//", i) -> {
                    val end = source.indexOf('\n', i).let { if (it < 0) source.length else it }
                    blank(i, end)
                    i = end
                }
                source.startsWith("/*", i) -> {
                    val end = source.indexOf("*/", i + 2).let { if (it < 0) source.length else it + 2 }
                    blank(i, end)
                    i = end
                }
                source.startsWith("\"\"\"", i) -> {
                    val end = source.indexOf("\"\"\"", i + 3).let { if (it < 0) source.length else it + 3 }
                    blank(i + 3, end - 3)
                    i = end
                }
                source[i] == '"' -> {
                    var j = i + 1
                    while (j < source.length && source[j] != '"') j += if (source[j] == '\\') 2 else 1
                    blank(i + 1, j)
                    i = j + 1
                }
                source[i] == '\'' && CHAR_LITERAL.matchesAt(source, i) -> {
                    val end = CHAR_LITERAL.matchAt(source, i)!!.range.last + 1
                    blank(i + 1, end - 1)
                    i = end
                }
                else -> i++
            }
        }
        return out.toString()
    }

    /** Top-level argument texts of the call whose opening parenthesis is at [openIndex]. */
    private fun topLevelArguments(code: String, openIndex: Int): List<String> {
        val arguments = mutableListOf<String>()
        var depth = 0
        var start = openIndex + 1
        for (i in openIndex until code.length) {
            when (code[i]) {
                '(', '[', '{' -> depth++
                ')', ']', '}' -> {
                    depth--
                    if (depth == 0) {
                        arguments += code.substring(start, i)
                        return arguments.filter { it.isNotBlank() }
                    }
                }
                ',' -> if (depth == 1) {
                    arguments += code.substring(start, i)
                    start = i + 1
                }
            }
        }
        return arguments.filter { it.isNotBlank() }
    }

    private companion object {
        val CALL = Regex("""(?<![A-Za-z0-9_])(stringResource|pluralStringResource|getString|getQuantityString)\(""")
        val CHAR_LITERAL = Regex("""'(\\u[0-9a-fA-F]{4}|\\.|[^'\\])'""")
    }
}
