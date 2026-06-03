package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.example.gymapp.auth.AuthUiState
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.HeroPanel

@Composable
fun AuthScreen(
    uiState: AuthUiState,
    onLogin: (email: String, password: String) -> Unit,
    onSignUp: (email: String, password: String, displayName: String) -> Unit,
    modifier: Modifier = Modifier
) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var signUpEmail by remember { mutableStateOf("") }
    var signUpPassword by remember { mutableStateOf("") }
    var signUpPasswordConfirm by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    var isSignUp by remember { mutableStateOf(false) }
    var localMessage by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        HeroPanel {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "GymApp",
                    style = MaterialTheme.typography.headlineMedium
                )
                Text(
                    text = "Sign in to sync workouts across devices.",
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }

        AppPanel(highlighted = true) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    text = if (isSignUp) "Create account" else "Cloud account",
                    style = MaterialTheme.typography.titleLarge
                )
                OutlinedTextField(
                    value = if (isSignUp) signUpEmail else email,
                    onValueChange = {
                        localMessage = null
                        if (isSignUp) signUpEmail = it else email = it
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Email") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email)
                )
                OutlinedTextField(
                    value = if (isSignUp) signUpPassword else password,
                    onValueChange = {
                        localMessage = null
                        if (isSignUp) signUpPassword = it else password = it
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Password") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation()
                )
                if (isSignUp) {
                    OutlinedTextField(
                        value = signUpPasswordConfirm,
                        onValueChange = {
                            localMessage = null
                            signUpPasswordConfirm = it
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Repeat password") },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation()
                    )
                    OutlinedTextField(
                        value = displayName,
                        onValueChange = { value ->
                            localMessage = null
                            displayName = value
                                .filter { it.isLetterOrDigit() || it == ' ' || it == '.' || it == '-' || it == '_' }
                                .replace(Regex("\\s+"), " ")
                                .take(32)
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Display name") },
                        singleLine = true
                    )
                }
                Text(
                    text = if (isSignUp) {
                        "Password must be 8+ characters and include letters and numbers. Display name allows letters, numbers, spaces, dot, dash and underscore."
                    } else {
                        "Password must be 8+ characters and include letters and numbers."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Button(
                        onClick = {
                            if (isSignUp) {
                                val validation = validateSignUpInput(
                                    email = signUpEmail,
                                    password = signUpPassword,
                                    passwordConfirm = signUpPasswordConfirm,
                                    displayName = displayName
                                )
                                if (validation == null) {
                                    onSignUp(signUpEmail, signUpPassword, displayName)
                                } else {
                                    localMessage = validation
                                }
                            } else {
                                onLogin(email, password)
                            }
                        },
                        enabled = !uiState.isLoading,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(if (isSignUp) "Create account" else "Log in")
                    }
                    OutlinedButton(
                        onClick = {
                            localMessage = null
                            isSignUp = !isSignUp
                        },
                        enabled = !uiState.isLoading,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(if (isSignUp) "Log in instead" else "Create account")
                    }
                }
            }
        }

        localMessage?.let { message ->
            Text(
                text = message,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        uiState.message?.let { message ->
            Text(
                text = message,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}

internal fun validateSignUpInput(
    email: String,
    password: String,
    passwordConfirm: String,
    displayName: String
): String? {
    val cleanEmail = email.trim()
    return when {
        cleanEmail.isBlank() -> "Enter your email."
        displayName.trim().length !in 2..32 -> "Display name must be 2-32 characters."
        password.length < 8 -> "Password must be at least 8 characters."
        !password.any { it.isLetter() } || !password.any { it.isDigit() } -> "Password must include letters and numbers."
        password != passwordConfirm -> "Passwords do not match."
        else -> null
    }
}
