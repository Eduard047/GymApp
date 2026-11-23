package com.example.gymapp.wear.sync

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Test

class WearRussianLocalizationTest {
    @Test
    fun russianWearCopyMatchesWatchUiSpec() {
        val russian = loadStrings("values-ru")

        val expected = mapOf(
            "start_plan" to "Начать план",
            "log_set" to "Записать подход",
            "set_k_of_n" to "Подход %1\$d из %2\$d",
            "discard" to "Удалить тренировку",
            "keep" to "Оставить тренировку",
            "send_later" to "Отправим, когда телефон будет рядом",
            "message_invalid_set_input" to
                "Укажи корректное количество повторов и при необходимости вес."
        )
        expected.forEach { (key, value) ->
            assertEquals("Unexpected Russian Wear wording for '$key'", value, russian[key])
        }
    }

    @Test
    fun wearLocalesExposeMatchingKeysAndPlaceholders() {
        val english = loadStrings("values")
        val ukrainian = loadStrings("values-uk")
        val russian = loadStrings("values-ru")

        assertEquals(english.keys, ukrainian.keys)
        assertEquals(english.keys, russian.keys)
        english.forEach { (key, value) ->
            val placeholders = formatPlaceholders(value)
            assertEquals(key, placeholders, formatPlaceholders(requireNotNull(ukrainian[key])))
            assertEquals(key, placeholders, formatPlaceholders(requireNotNull(russian[key])))
        }
    }

    private fun loadStrings(valuesDirectory: String): Map<String, String> {
        val path = wearFile("src/main/res/$valuesDirectory/strings.xml")
        val factory = DocumentBuilderFactory.newInstance().apply {
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            setFeature("http://xml.org/sax/features/external-general-entities", false)
            setFeature("http://xml.org/sax/features/external-parameter-entities", false)
            setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
            isXIncludeAware = false
            isExpandEntityReferences = false
        }
        val document = Files.newInputStream(path).use { input ->
            factory.newDocumentBuilder().parse(input)
        }
        val nodes = document.getElementsByTagName("string")
        return buildMap {
            for (index in 0 until nodes.length) {
                val node = nodes.item(index)
                check(put(node.attributes.getNamedItem("name").nodeValue, node.textContent) == null)
            }
        }
    }

    private fun formatPlaceholders(value: String): List<String> = FORMAT_PLACEHOLDER
        .findAll(value)
        .map { it.value }
        .sorted()
        .toList()

    private fun wearFile(relativePath: String): Path {
        val workingDirectory = Paths.get("").toAbsolutePath().normalize()
        return generateSequence(workingDirectory) { it.parent }
            .flatMap { directory ->
                sequenceOf(
                    directory.resolve(relativePath),
                    directory.resolve("wear").resolve(relativePath)
                )
            }
            .distinct()
            .firstOrNull(Files::isRegularFile)
            ?: error("Could not locate wear/$relativePath from $workingDirectory")
    }

    private companion object {
        val FORMAT_PLACEHOLDER = Regex(
            "%\\d+\\$[-#+ 0,(<]*\\d*(?:\\.\\d+)?[a-zA-Z%]|%%"
        )
    }
}
