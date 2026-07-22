package com.example.gymapp.localization

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class StringResourceParityTest {
    @Test
    fun englishUkrainianAndRussianExposeTheSameStringKeys() {
        val english = loadStrings("values")
        val ukrainian = loadStrings("values-uk")
        val russian = loadStrings("values-ru")

        assertEquals("Ukrainian string keys differ from English", english.keys, ukrainian.keys)
        assertEquals("Russian string keys differ from English", english.keys, russian.keys)
    }

    @Test
    fun localizedStringsPreserveAndroidFormatPlaceholders() {
        val english = loadStrings("values")
        val ukrainian = loadStrings("values-uk")
        val russian = loadStrings("values-ru")

        english.forEach { (key, englishValue) ->
            val expected = formatPlaceholders(englishValue)
            assertEquals(
                "Ukrainian placeholders differ for '$key'",
                expected,
                formatPlaceholders(requireNotNull(ukrainian[key]))
            )
            assertEquals(
                "Russian placeholders differ for '$key'",
                expected,
                formatPlaceholders(requireNotNull(russian[key]))
            )
        }
    }

    @Test
    fun releaseCriticalRussianCopyStaysDeviceNeutralAndPolished() {
        val english = loadStrings("values")
        val ukrainian = loadStrings("values-uk")
        val russian = loadStrings("values-ru")

        assertEquals("%1\$s · synced from Garmin", english["garmin_workout_synced_from"])
        assertEquals("%1\$s · синхронізовано з Garmin", ukrainian["garmin_workout_synced_from"])
        assertEquals("%1\$s · синхронизировано с Garmin", russian["garmin_workout_synced_from"])
        assertFalse((english.values + ukrainian.values + russian.values).any { '\u200B' in it })
        assertEquals(
            "Name in English, Ukrainian, or Russian",
            english["exercise_search_placeholder"]
        )
        assertEquals(
            "Назва англійською, українською або російською",
            ukrainian["exercise_search_placeholder"]
        )
        assertEquals(
            "Название на английском, украинском или русском",
            russian["exercise_search_placeholder"]
        )

        val expectedRussian = mapOf(
            "auth_new_password_requirements" to
                "Используй не менее 12 символов (до 72 байт UTF-8): строчную и заглавную латинские буквы, цифру и поддерживаемый спецсимвол, например !, @, # или $.",
            "activity_heatmap_legend" to
                "Цвет показывает дневной объём тренировок за этот месяц: вес × повторения. Чем темнее, тем меньше объём; чем ярче оранжевый, тем больше.",
            "smart_kind_hold_and_build" to
                "План прогрессии: сохрани вес и добавляй повторения перед следующим увеличением.",
            "smart_reason_calorie_deficit" to
                "При дефиците калорий прогрессия осторожнее, чтобы сохранить восстановление.",
            "smart_reason_upper_lower" to
                "Четырёхдневный сплит «верх/низ»: нагрузка оставляет запас для следующей тренировки.",
            "post_workout_top_muscle" to "Наибольшая нагрузка сегодня: %1\$s",
            "exercise_sort_least_frequent" to "Реже всего",
            "action_copy_last_plus" to "Копировать предыдущий + 2,5 кг",
            "post_workout_view_workout" to "Посмотреть тренировку",
            "achievements_supporting" to
                "Полная галерея значков, прогресс и награды за открытие.",
            "rank_status_unlocked" to "Открыт",
            "post_workout_logged_today" to "Записано сегодня",
            "post_workout_logged_recently" to "Записано недавно",
            "progress_summary_title" to "Сводка прогресса"
        )
        expectedRussian.forEach { (key, expected) ->
            assertEquals("Unexpected Russian wording for '$key'", expected, russian[key])
        }
    }

    private fun loadStrings(valuesDirectory: String): Map<String, String> {
        val path = appFile("src/main/res/$valuesDirectory/strings.xml")
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
                val name = node.attributes.getNamedItem("name").nodeValue
                check(put(name, node.textContent) == null) {
                    "Duplicate string '$name' in $path"
                }
            }
        }
    }

    private fun formatPlaceholders(value: String): List<String> = FORMAT_PLACEHOLDER
        .findAll(value)
        .map { it.value }
        .sorted()
        .toList()

    private fun appFile(relativePath: String): Path {
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
        return candidates.firstOrNull(Files::isRegularFile)
            ?: error("Could not locate app/$relativePath from $workingDirectory")
    }

    private companion object {
        val FORMAT_PLACEHOLDER = Regex(
            "%\\d+\\$[-#+ 0,(<]*\\d*(?:\\.\\d+)?[a-zA-Z%]|%%"
        )
    }
}
