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
    var displayName by remember { mutableStateOf("") }

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
                    text = "Cloud account",
                    style = MaterialTheme.typography.titleLarge
                )
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Email") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email)
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Password") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation()
                )
                OutlinedTextField(
                    value = displayName,
                    onValueChange = { value ->
                        displayName = value
                            .filter { it.isLetterOrDigit() || it == ' ' || it == '.' || it == '-' || it == '_' }
                            .replace(Regex("\\s+"), " ")
                            .take(32)
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Display name") },
                    singleLine = true
                )
                Text(
                    text = "Password must be 8+ characters and include letters and numbers. Display name allows letters, numbers, spaces, dot, dash and underscore.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Button(
                        onClick = { onLogin(email, password) },
                        enabled = !uiState.isLoading,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("Log in")
                    }
                    OutlinedButton(
                        onClick = { onSignUp(email, password, displayName) },
                        enabled = !uiState.isLoading,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("Create account")
                    }
                }
            }
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
