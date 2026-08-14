package com.example.gymapp.ui.components

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import org.junit.Assert.assertTrue
import org.junit.Test

class FirstRunTutorialAccessibilitySourceTest {
    @Test
    fun tutorialHidesUnderlyingSemanticsAndCancelsFocusExit() {
        val navigation = Files.readString(appFile("src/main/java/com/example/gymapp/navigation/GymNavGraph.kt"))
        val overlay = Files.readString(
            appFile("src/main/java/com/example/gymapp/ui/components/FirstRunTutorialOverlay.kt")
        )

        assertTrue(navigation.contains("if (tutorialMode != null) hideFromAccessibility()"))
        assertTrue(overlay.contains("exit = { FocusRequester.Cancel }"))
        assertTrue(overlay.contains(".focusGroup()"))
        assertTrue(overlay.contains("R.string.tutorial_completion_save_failed"))
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
            .firstOrNull(Files::isRegularFile)
            ?: error("Could not locate app/$relativePath")
    }
}
