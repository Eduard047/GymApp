package com.example.gymapp.ui.screens

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.auth.AuthUiState
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.HeroPanel

@Composable
fun AuthScreen(
    uiState: AuthUiState,
    onLogin: (email: String, password: String) -> Unit,
    onSignUp: (email: String, password: String, displayName: String) -> Unit,
    onResendConfirmation: (email: String) -> Unit,
    onPasswordReset: (email: String) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var signUpEmail by remember { mutableStateOf("") }
    var signUpEmailConfirm by remember { mutableStateOf("") }
    var signUpPassword by remember { mutableStateOf("") }
    var signUpPasswordConfirm by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    var isSignUp by remember { mutableStateOf(false) }
    var loginPasswordVisible by remember { mutableStateOf(false) }
    var signUpPasswordVisible by remember { mutableStateOf(false) }
    var signUpPasswordConfirmVisible by remember { mutableStateOf(false) }
    var localMessage by remember { mutableStateOf<String?>(null) }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
    ) {
        Column(
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .heightIn(min = maxHeight)
                .widthIn(max = 560.dp)
                .padding(horizontal = 16.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)
        ) {
            HeroPanel {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        text = "GymApp",
                        style = MaterialTheme.typography.headlineMedium
                    )
                    Text(
                        text = stringResource(R.string.auth_sync_supporting),
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
                        text = stringResource(
                            if (isSignUp) R.string.auth_create_account else R.string.auth_cloud_account
                        ),
                        style = MaterialTheme.typography.titleLarge
                    )
                    OutlinedTextField(
                        value = if (isSignUp) signUpEmail else email,
                        onValueChange = {
                            localMessage = null
                            if (isSignUp) signUpEmail = it else email = it
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.auth_email)) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email)
                    )
                    if (!isSignUp) {
                        PasswordTextField(
                            value = password,
                            onValueChange = {
                                localMessage = null
                                password = it
                            },
                            passwordVisible = loginPasswordVisible,
                            onPasswordVisibilityChange = { loginPasswordVisible = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = stringResource(R.string.auth_password)
                        )
                    }
                    if (isSignUp) {
                        OutlinedTextField(
                            value = signUpEmailConfirm,
                            onValueChange = {
                                localMessage = null
                                signUpEmailConfirm = it
                            },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text(stringResource(R.string.auth_repeat_email)) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email)
                        )
                        PasswordTextField(
                            value = signUpPassword,
                            onValueChange = {
                                localMessage = null
                                signUpPassword = it
                            },
                            passwordVisible = signUpPasswordVisible,
                            onPasswordVisibilityChange = { signUpPasswordVisible = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = stringResource(R.string.auth_password)
                        )
                        PasswordTextField(
                            value = signUpPasswordConfirm,
                            onValueChange = {
                                localMessage = null
                                signUpPasswordConfirm = it
                            },
                            passwordVisible = signUpPasswordConfirmVisible,
                            onPasswordVisibilityChange = { signUpPasswordConfirmVisible = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = stringResource(R.string.auth_repeat_password)
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
                            label = { Text(stringResource(R.string.auth_display_name)) },
                            singleLine = true
                        )
                    }
                    Text(
                        text = stringResource(
                            if (isSignUp) R.string.auth_signup_requirements else R.string.auth_password_requirements
                        ),
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
                                        emailConfirm = signUpEmailConfirm,
                                        password = signUpPassword,
                                        passwordConfirm = signUpPasswordConfirm,
                                        displayName = displayName
                                    )
                                    if (validation == null) {
                                        onSignUp(signUpEmail, signUpPassword, displayName)
                                    } else {
                                        localMessage = localizedAuthValidationMessage(context, validation)
                                    }
                                } else {
                                    val validation = validateLoginInput(
                                        email = email,
                                        password = password
                                    )
                                    if (validation == null) {
                                        onLogin(email, password)
                                    } else {
                                        localMessage = localizedAuthValidationMessage(context, validation)
                                    }
                                }
                            },
                            enabled = !uiState.isLoading,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(
                                stringResource(
                                    if (isSignUp) R.string.auth_create_account else R.string.auth_log_in
                                )
                            )
                        }
                        OutlinedButton(
                            onClick = {
                                localMessage = null
                                isSignUp = !isSignUp
                            },
                            enabled = !uiState.isLoading,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(
                                stringResource(
                                    if (isSignUp) R.string.auth_log_in_instead else R.string.auth_create_account
                                )
                            )
                        }
                    }
                    if (isSignUp) {
                        OutlinedButton(
                            onClick = {
                                val validation = validateConfirmationEmailInput(signUpEmail)
                                if (validation == null) {
                                    localMessage = null
                                    onResendConfirmation(signUpEmail)
                                } else {
                                    localMessage = localizedAuthValidationMessage(context, validation)
                                }
                            },
                            enabled = !uiState.isLoading,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(stringResource(R.string.auth_resend_confirmation))
                        }
                    } else {
                        OutlinedButton(
                            onClick = {
                                val validation = validateRecoveryEmailInput(email)
                                if (validation == null) {
                                    localMessage = null
                                    onPasswordReset(email)
                                } else {
                                    localMessage = localizedAuthValidationMessage(context, validation)
                                }
                            },
                            enabled = !uiState.isLoading,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(stringResource(R.string.auth_forgot_password))
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
                    color = if (uiState.messageIsError) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

@Composable
fun PasswordUpdateScreen(
    uiState: AuthUiState,
    onUpdatePassword: (password: String) -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    var password by remember { mutableStateOf("") }
    var passwordConfirm by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }
    var passwordConfirmVisible by remember { mutableStateOf(false) }
    var localMessage by remember { mutableStateOf<String?>(null) }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
    ) {
        Column(
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .heightIn(min = maxHeight)
                .widthIn(max = 560.dp)
                .padding(horizontal = 16.dp, vertical = 18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)
        ) {
            HeroPanel {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        text = stringResource(R.string.auth_choose_new_password),
                        style = MaterialTheme.typography.headlineMedium
                    )
                    Text(
                        text = stringResource(R.string.auth_recovery_verified),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }

            AppPanel(highlighted = true) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    PasswordTextField(
                        value = password,
                        onValueChange = {
                            localMessage = null
                            password = it
                        },
                        passwordVisible = passwordVisible,
                        onPasswordVisibilityChange = { passwordVisible = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = stringResource(R.string.auth_new_password)
                    )
                    PasswordTextField(
                        value = passwordConfirm,
                        onValueChange = {
                            localMessage = null
                            passwordConfirm = it
                        },
                        passwordVisible = passwordConfirmVisible,
                        onPasswordVisibilityChange = { passwordConfirmVisible = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = stringResource(R.string.auth_repeat_password)
                    )
                    Text(
                        text = stringResource(R.string.auth_new_password_requirements),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
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
                            color = if (uiState.messageIsError) {
                                MaterialTheme.colorScheme.error
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                    Button(
                        onClick = {
                            val validation = validatePasswordUpdateInput(password, passwordConfirm)
                            if (validation == null) {
                                localMessage = null
                                onUpdatePassword(password)
                            } else {
                                localMessage = localizedAuthValidationMessage(context, validation)
                            }
                        },
                        enabled = !uiState.isLoading,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            stringResource(
                                if (uiState.isLoading) R.string.auth_updating_password else R.string.auth_update_password
                            )
                        )
                    }
                    OutlinedButton(
                        onClick = onCancel,
                        enabled = !uiState.isLoading,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.auth_cancel_recovery))
                    }
                }
            }
        }
    }
}

@Composable
private fun PasswordTextField(
    value: String,
    onValueChange: (String) -> Unit,
    passwordVisible: Boolean,
    onPasswordVisibilityChange: (Boolean) -> Unit,
    label: String,
    modifier: Modifier = Modifier
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier,
        label = { Text(label) },
        singleLine = true,
        visualTransformation = if (passwordVisible) {
            VisualTransformation.None
        } else {
            PasswordVisualTransformation()
        },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        trailingIcon = {
            IconButton(onClick = { onPasswordVisibilityChange(!passwordVisible) }) {
                Icon(
                    imageVector = if (passwordVisible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                    contentDescription = stringResource(
                        if (passwordVisible) R.string.auth_hide_password else R.string.auth_show_password
                    )
                )
            }
        }
    )
}

private fun localizedAuthValidationMessage(context: Context, message: String): String {
    val resource = when (message) {
        "Enter your email." -> R.string.auth_error_email_required
        "Enter a valid email address." -> R.string.auth_error_email_invalid
        "Enter your password." -> R.string.auth_error_password_required
        "Repeat your email." -> R.string.auth_error_repeat_email
        "Email does not match." -> R.string.auth_error_email_mismatch
        "Display name must be 2-32 characters." -> R.string.auth_error_display_name_length
        "Password must be at least 8 characters." -> R.string.auth_error_password_minimum
        "Password must include letters and numbers." -> R.string.auth_error_password_complexity
        "Passwords do not match." -> R.string.auth_error_password_mismatch
        "Enter a new password." -> R.string.auth_error_new_password_required
        "Password must be 8-72 characters." -> R.string.auth_error_new_password_length
        else -> return message
    }
    return context.getString(resource)
}

internal fun validateLoginInput(
    email: String,
    password: String
): String? {
    val cleanEmail = normalizeAuthEmail(email)
    return when {
        cleanEmail.isBlank() -> "Enter your email."
        !isValidEmail(cleanEmail) -> "Enter a valid email address."
        password.isBlank() -> "Enter your password."
        else -> null
    }
}

internal fun validateSignUpInput(
    email: String,
    emailConfirm: String,
    password: String,
    passwordConfirm: String,
    displayName: String
): String? {
    val cleanEmail = normalizeAuthEmail(email)
    val cleanEmailConfirm = normalizeAuthEmail(emailConfirm)
    return when {
        cleanEmail.isBlank() -> "Enter your email."
        !isValidEmail(cleanEmail) -> "Enter a valid email address."
        cleanEmailConfirm.isBlank() -> "Repeat your email."
        cleanEmail != cleanEmailConfirm -> "Email does not match."
        displayName.trim().length !in 2..32 -> "Display name must be 2-32 characters."
        password.length < 8 -> "Password must be at least 8 characters."
        !password.any { it.isLetter() } || !password.any { it.isDigit() } -> "Password must include letters and numbers."
        password != passwordConfirm -> "Passwords do not match."
        else -> null
    }
}

internal fun validateConfirmationEmailInput(email: String): String? {
    val cleanEmail = normalizeAuthEmail(email)
    return when {
        cleanEmail.isBlank() -> "Enter your email."
        !isValidEmail(cleanEmail) -> "Enter a valid email address."
        else -> null
    }
}

internal fun validateRecoveryEmailInput(email: String): String? {
    return validateConfirmationEmailInput(email)
}

internal fun validatePasswordUpdateInput(
    password: String,
    passwordConfirm: String
): String? {
    return when {
        password.isBlank() -> "Enter a new password."
        password.length !in 8..72 -> "Password must be 8-72 characters."
        !password.any { it.isLetter() } || !password.any { it.isDigit() } ->
            "Password must include letters and numbers."
        password != passwordConfirm -> "Passwords do not match."
        else -> null
    }
}

private fun normalizeAuthEmail(email: String): String {
    return email.trim().lowercase()
}

private fun isValidEmail(email: String): Boolean {
    return Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$").matches(email) && email.length <= 254
}
