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
            // The watch has no text input, so nothing is "entered"; formal address as on the phone.
            "message_invalid_set_input" to "Проверьте вес и повторения.",
            "open_phone" to "Откройте GymApp на телефоне",
            "send_rejected" to "Телефон не принял эту тренировку. Обновите GymApp на телефоне.",
            // One-word edge-button labels for screens under 225dp: a word is never broken.
            "log_set_short" to "Записать",
            "choose_short" to "Выбрать",
            "label_duration" to "Время",
            // Same verbs as the phone's Watches screen.
            "link_phone" to "Привязать к телефону",
            "unlink_phone" to "Отвязать от телефона",
            "link_unlinked" to "Не привязано к телефону"
        )
        expected.forEach { (key, value) ->
            assertEquals("Unexpected Russian Wear wording for '$key'", value, russian[key])
        }
    }

    @Test
    fun appLabelIsTheProductNameInEveryLocale() {
        listOf("values", "values-uk", "values-ru").forEach { directory ->
            assertEquals(directory, "GymApp", loadStrings(directory)["app_name"])
        }
    }

    @Test
    fun edgeButtonShortLabelsAreSingleWordsThatFitASmallScreen() {
        listOf("values-uk", "values-ru").forEach { directory ->
            val strings = loadStrings(directory)
            listOf("log_set_short", "choose_short").forEach { key ->
                val label = requireNotNull(strings[key])
                assertEquals("$directory/$key must be one word", false, label.contains(' '))
                assertEquals("$directory/$key is too long for a small edge button", true, label.length <= 8)
            }
        }
    }

    @Test
    fun accessibilityCountsHaveEveryPluralForm() {
        // 1 / 2 / 5 / 21 in Russian and Ukrainian need one / few / many (+ other for fractions).
        val slavic = setOf("one", "few", "many", "other")
        mapOf("values" to setOf("one", "other"), "values-uk" to slavic, "values-ru" to slavic)
            .forEach { (directory, quantities) ->
                val plurals = loadPlurals(directory)
                listOf("a11y_reps", "a11y_beats").forEach { name ->
                    val forms = requireNotNull(plurals[name]) { "$directory is missing plurals '$name'" }
                    assertEquals("$directory/$name", quantities, forms.keys)
                    forms.forEach { (quantity, text) ->
                        assertEquals("$directory/$name/$quantity", listOf("%1\$d"), Regex("%(?:1\\$)?d").findAll(text).map { it.value }.toList())
                    }
                }
            }
        val russian = loadPlurals("values-ru")
        assertEquals("%1\$d повторение", russian.getValue("a11y_reps").getValue("one"))
        assertEquals("%1\$d повторения", russian.getValue("a11y_reps").getValue("few"))
        assertEquals("%1\$d повторений", russian.getValue("a11y_reps").getValue("many"))
        assertEquals("%1\$d удар в минуту", russian.getValue("a11y_beats").getValue("one"))
        assertEquals("%1\$d удара в минуту", russian.getValue("a11y_beats").getValue("few"))
        assertEquals("%1\$d ударов в минуту", russian.getValue("a11y_beats").getValue("many"))
    }

    private fun loadPlurals(valuesDirectory: String): Map<String, Map<String, String>> {
        val path = wearFile("src/main/res/$valuesDirectory/strings.xml")
        val factory = DocumentBuilderFactory.newInstance().apply {
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
            isXIncludeAware = false
            isExpandEntityReferences = false
        }
        val document = Files.newInputStream(path).use { input -> factory.newDocumentBuilder().parse(input) }
        val nodes = document.getElementsByTagName("plurals")
        return buildMap {
            for (index in 0 until nodes.length) {
                val node = nodes.item(index)
                val items = (node as org.w3c.dom.Element).getElementsByTagName("item")
                put(
                    node.getAttribute("name"),
                    buildMap {
                        for (itemIndex in 0 until items.length) {
                            val item = items.item(itemIndex) as org.w3c.dom.Element
                            put(item.getAttribute("quantity"), item.textContent)
                        }
                    }
                )
            }
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
