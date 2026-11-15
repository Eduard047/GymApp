package com.example.gymapp.ui.screens

import com.example.gymapp.R
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveWorkoutFinishFlowTest {
    @Test
    fun finishAsksOnlyWhenPlannedSetsAreNotLogged() {
        assertEquals(
            ActiveWorkoutFinishDecision.FinishNow,
            activeWorkoutFinishDecision(completedSetCount = 5, totalSetCount = 5)
        )
        assertEquals(
            ActiveWorkoutFinishDecision.FinishNow,
            activeWorkoutFinishDecision(completedSetCount = 0, totalSetCount = 0)
        )
        assertEquals(
            ActiveWorkoutFinishDecision.ConfirmUnlogged(1),
            activeWorkoutFinishDecision(completedSetCount = 4, totalSetCount = 5)
        )
        assertEquals(
            ActiveWorkoutFinishDecision.ConfirmUnlogged(9),
            activeWorkoutFinishDecision(completedSetCount = 3, totalSetCount = 12)
        )
    }

    @Test
    fun unloggedCountNeverGoesNegative() {
        assertEquals(0, activeWorkoutUnloggedSetCount(completedSetCount = 6, totalSetCount = 5))
        assertEquals(2, activeWorkoutUnloggedSetCount(completedSetCount = 3, totalSetCount = 5))
    }

    @Test
    fun exerciseFinishLabelIsSingularOnlyForExactlyOneSet() {
        assertEquals(R.string.active_workout_finish_exercise_without_it, activeWorkoutFinishWithoutLabelRes(1))
        // Russian/Ukrainian plural "one" also matches 21, 31...: those must read "without them".
        listOf(2, 5, 11, 21, 31).forEach { count ->
            assertEquals(R.string.active_workout_finish_exercise_without_them, activeWorkoutFinishWithoutLabelRes(count))
        }
    }

    @Test
    fun finishWorkoutMessageAgreesWithTheCountInEveryLanguage() {
        val en = plurals("values", "finish_remaining_body")
        val ru = plurals("values-ru", "finish_remaining_body")
        val uk = plurals("values-uk", "finish_remaining_body")

        assertEquals("1 set isn't logged — it won't be saved.", render(en, "en", 1))
        assertEquals("5 sets aren't logged — they won't be saved.", render(en, "en", 5))

        assertEquals("Не записан 1 подход — он не попадёт в историю.", render(ru, "ru", 1))
        assertEquals("Не записано 2 подхода — они не попадут в историю.", render(ru, "ru", 2))
        assertEquals("Не записано 5 подходов — они не попадут в историю.", render(ru, "ru", 5))
        assertEquals("Не записано 11 подходов — они не попадут в историю.", render(ru, "ru", 11))
        assertEquals("Не записан 21 подход — он не попадёт в историю.", render(ru, "ru", 21))
        assertEquals("Не записано 22 подхода — они не попадут в историю.", render(ru, "ru", 22))

        assertEquals("Не записано 1 підхід — він не потрапить в історію.", render(uk, "uk", 1))
        assertEquals("Не записано 3 підходи — вони не потраплять в історію.", render(uk, "uk", 3))
        assertEquals("Не записано 5 підходів — вони не потраплять в історію.", render(uk, "uk", 5))
        assertEquals("Не записано 12 підходів — вони не потраплять в історію.", render(uk, "uk", 12))
    }

    @Test
    fun finishExerciseMessageAgreesWithTheCountInEveryLanguage() {
        val en = plurals("values", "active_workout_finish_exercise_unlogged")
        val ru = plurals("values-ru", "active_workout_finish_exercise_unlogged")
        val uk = plurals("values-uk", "active_workout_finish_exercise_unlogged")

        assertEquals("1 set isn't logged", render(en, "en", 1))
        assertEquals("3 sets aren't logged", render(en, "en", 3))
        assertEquals("Не записан 1 подход", render(ru, "ru", 1))
        assertEquals("Не записано 3 подхода", render(ru, "ru", 3))
        assertEquals("Не записано 7 подходов", render(ru, "ru", 7))
        assertEquals("Не записано 1 підхід", render(uk, "uk", 1))
        assertEquals("Не записано 4 підходи", render(uk, "uk", 4))
        assertEquals("Не записано 6 підходів", render(uk, "uk", 6))
    }

    @Test
    fun finishButtonsUseTheAgreedCopy() {
        assertEquals("Finish", string("values", "active_workout_toolbar_finish"))
        assertEquals("Завершить", string("values-ru", "active_workout_toolbar_finish"))
        assertEquals("Завершити", string("values-uk", "active_workout_toolbar_finish"))
        assertEquals("Mark all as done", string("values", "finish_remaining_mark_all_done"))
        assertEquals("Отметить все как выполненные", string("values-ru", "finish_remaining_mark_all_done"))
        assertEquals("Позначити всі як виконані", string("values-uk", "finish_remaining_mark_all_done"))
        assertEquals("Завершить упражнение?", string("values-ru", "active_workout_finish_exercise_title"))
        assertEquals("Завершить без него", string("values-ru", "active_workout_finish_exercise_without_it"))
        assertEquals("Завершить без них", string("values-ru", "active_workout_finish_exercise_without_them"))
        assertEquals("Отметить как выполненные", string("values-ru", "active_workout_finish_exercise_mark_done"))
    }

    @Test
    fun inCardFinishAndRestSkipUseTheAgreedCopy() {
        assertEquals("Done", string("values", "active_workout_finish_exercise"))
        assertEquals("Готово", string("values-ru", "active_workout_finish_exercise"))
        assertEquals("Готово", string("values-uk", "active_workout_finish_exercise"))
        assertEquals("Skip", string("values", "active_workout_rest_skip"))
        assertEquals("Пропустить", string("values-ru", "active_workout_rest_skip"))
        assertEquals("Пропустити", string("values-uk", "active_workout_rest_skip"))
        assertEquals("Settings", string("values", "active_workout_rest_alerts_open_settings"))
        assertEquals("Настройки", string("values-ru", "active_workout_rest_alerts_open_settings"))
        assertEquals("Налаштування", string("values-uk", "active_workout_rest_alerts_open_settings"))
    }

    @Test
    fun bodyHasNoStandaloneLogRemainingButtonAndFinishLivesInTheToolbar() {
        val source = Files.readString(appFile("src/main/java/com/example/gymapp/ui/screens/ActiveWorkoutScreen.kt"))
        assertTrue(!source.contains("action_save_all_pending_sets"))
        assertTrue(!source.contains("onRecordAllPendingSets"))
        assertTrue(source.contains("fun ActiveWorkoutFinishAction"))
    }

    private fun render(items: Map<String, String>, language: String, count: Int): String {
        val template = items.getValue(category(language, count))
        return template.replace("%1\$d", count.toString())
    }

    /** CLDR integer plural categories for the three shipped languages. */
    private fun category(language: String, n: Int): String = when (language) {
        "en" -> if (n == 1) "one" else "other"
        else -> when {
            n % 10 == 1 && n % 100 != 11 -> "one"
            n % 10 in 2..4 && n % 100 !in 12..14 -> "few"
            else -> "many"
        }
    }

    private fun plurals(dir: String, name: String): Map<String, String> {
        val nodes = document(dir).getElementsByTagName("plurals")
        for (i in 0 until nodes.length) {
            val node = nodes.item(i)
            if (node.attributes.getNamedItem("name").nodeValue != name) continue
            val result = mutableMapOf<String, String>()
            for (j in 0 until node.childNodes.length) {
                val child = node.childNodes.item(j)
                if (child.nodeName == "item") {
                    result[child.attributes.getNamedItem("quantity").nodeValue] = unescape(child.textContent)
                }
            }
            return result
        }
        error("plural $name missing in $dir")
    }

    private fun string(dir: String, name: String): String {
        val nodes = document(dir).getElementsByTagName("string")
        for (i in 0 until nodes.length) {
            val node = nodes.item(i)
            if (node.attributes.getNamedItem("name").nodeValue == name) return unescape(node.textContent)
        }
        error("string $name missing in $dir")
    }

    private fun unescape(raw: String) = raw.replace("\\'", "'").replace("\\u2014", "—")

    private fun document(dir: String) = DocumentBuilderFactory.newInstance().newDocumentBuilder()
        .parse(appFile("src/main/res/$dir/strings.xml").toFile())

    private fun appFile(relativePath: String): Path {
        val workingDirectory = Paths.get("").toAbsolutePath().normalize()
        return generateSequence(workingDirectory) { it.parent }
            .flatMap { sequenceOf(it.resolve(relativePath), it.resolve("app").resolve(relativePath)) }
            .first(Files::exists)
    }
}
