package com.example.gymapp.ui.screens

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.BackHand
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.gymapp.R
import com.example.gymapp.auth.AuthUiState
import com.example.gymapp.auth.SavedLocalProfile
import com.example.gymapp.auth.boundedNewLocalDisplayNameDraft
import com.example.gymapp.auth.newPasswordCharacterGroupsAreValid
import com.example.gymapp.auth.newPasswordLengthIsValid
import com.example.gymapp.auth.validatedNewLocalDisplayNameOrNull
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.AppBrandMark
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.util.AppLanguage
import com.example.gymapp.util.asString

class AuthDraftViewModel : ViewModel() {
    val email = mutableStateOf("")
    val password = mutableStateOf("")
    val signUpEmail = mutableStateOf("")
    val signUpEmailConfirm = mutableStateOf("")
    val signUpPassword = mutableStateOf("")
    val signUpPasswordConfirm = mutableStateOf("")
    val displayName = mutableStateOf("")
    val localDisplayName = mutableStateOf("")
    val isSignUp = mutableStateOf(false)
    val showOfflineSheet = mutableStateOf(false)

    fun clearSensitiveFields() {
        password.value = ""
        signUpPassword.value = ""
        signUpPasswordConfirm.value = ""
    }

    override fun onCleared() {
        clearSensitiveFields()
        super.onCleared()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthScreen(
    uiState: AuthUiState,
    selectedLanguage: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit,
    onLogin: (email: String, password: String) -> Unit,
    onSignUp: (email: String, password: String, displayName: String) -> Unit,
    onResendConfirmation: (email: String) -> Unit,
    onDismissEmailConfirmation: (clearPendingRequest: Boolean) -> Unit,
    onPasswordReset: (email: String) -> Unit,
    savedLocalProfiles: List<SavedLocalProfile>,
    onContinueLocal: (displayName: String, resumeExisting: Boolean) -> Unit,
    draft: AuthDraftViewModel = viewModel(),
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    var email by draft.email
    var password by draft.password
    var signUpEmail by draft.signUpEmail
    var signUpEmailConfirm by draft.signUpEmailConfirm
    var signUpPassword by draft.signUpPassword
    var signUpPasswordConfirm by draft.signUpPasswordConfirm
    var displayName by draft.displayName
    var localDisplayName by draft.localDisplayName
    var isSignUp by draft.isSignUp
    var showOfflineSheet by draft.showOfflineSheet
    var loginPasswordVisible by remember { mutableStateOf(false) }
    var signUpPasswordVisible by remember { mutableStateOf(false) }
    var signUpPasswordConfirmVisible by remember { mutableStateOf(false) }
    var signUpPasswordFocused by remember { mutableStateOf(false) }
    var localMessage by remember { mutableStateOf<String?>(null) }
    var localProfileMessage by remember(selectedLanguage) { mutableStateOf<String?>(null) }
    val pendingConfirmationEmail = uiState.pendingConfirmationEmail

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
    ) {
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .widthIn(max = 560.dp)
                .fillMaxWidth()
                .heightIn(min = maxHeight)
                .padding(start = 16.dp, top = 20.dp, end = 16.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            HeroPanel(modifier = Modifier.fillMaxWidth()) {
                BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                    val onSelectLanguage: (AppLanguage) -> Unit = { language ->
                        localMessage = null
                        localProfileMessage = null
                        onLanguageSelected(language)
                    }
                    if (maxWidth >= 320.dp) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            AppBrandMark(modifier = Modifier.size(72.dp))
                            Text(
                                text = "GymApp",
                                modifier = Modifier.weight(1f).semantics { heading() },
                                style = MaterialTheme.typography.headlineLarge
                            )
                            AuthLanguageSelector(
                                selectedLanguage = selectedLanguage,
                                onLanguageSelected = onSelectLanguage
                            )
                        }
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                AppBrandMark(modifier = Modifier.size(56.dp))
                                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                                AuthLanguageSelector(
                                    selectedLanguage = selectedLanguage,
                                    onLanguageSelected = onSelectLanguage
                                )
                            }
                            Text(
                                text = "GymApp",
                                modifier = Modifier.semantics { heading() },
                                style = MaterialTheme.typography.headlineLarge
                            )
                        }
                    }
                }
            }

            AppPanel(
                modifier = Modifier.fillMaxWidth(),
                highlighted = true
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(
                        text = stringResource(
                            when {
                                pendingConfirmationEmail != null -> R.string.auth_confirmation_title
                                isSignUp -> R.string.auth_create_account
                                else -> R.string.auth_welcome_back
                            }
                        ),
                        modifier = Modifier.semantics { heading() },
                        style = MaterialTheme.typography.headlineMedium
                    )

                    pendingConfirmationEmail?.let {
                        Text(
                            text = stringResource(R.string.auth_confirmation_body),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    if (pendingConfirmationEmail != null) {
                        EmailConfirmationCard(
                            email = pendingConfirmationEmail,
                            isLoading = uiState.isLoading,
                            onOpenEmail = {
                                if (!openEmailInbox(context)) {
                                    localMessage = context.getString(R.string.auth_email_app_unavailable)
                                }
                            },
                            onResend = {
                                localMessage = null
                                onResendConfirmation(pendingConfirmationEmail)
                            },
                            onChangeAddress = {
                                signUpEmail = pendingConfirmationEmail
                                signUpEmailConfirm = ""
                                signUpPassword = ""
                                signUpPasswordConfirm = ""
                                localMessage = null
                                isSignUp = true
                                onDismissEmailConfirmation(true)
                            },
                            onBackToSignIn = {
                                email = pendingConfirmationEmail
                                password = ""
                                localMessage = null
                                isSignUp = false
                                onDismissEmailConfirmation(false)
                            }
                        )

                        localMessage?.let { message ->
                            AuthStatusBanner(message = message, isError = true)
                        }
                        uiState.message?.let { message ->
                            AuthStatusBanner(
                                message = message.asString(),
                                isError = uiState.messageIsError
                            )
                        }
                    } else {
                    AuthModeSelector(
                        isSignUp = isSignUp,
                        enabled = !uiState.isLoading,
                        onModeSelected = { signUpSelected ->
                            if (isSignUp != signUpSelected) {
                                localMessage = null
                                isSignUp = signUpSelected
                            }
                        }
                    )

                    Column(verticalArrangement = Arrangement.spacedBy(13.dp)) {
                        OutlinedTextField(
                            value = if (isSignUp) signUpEmail else email,
                            onValueChange = {
                                localMessage = null
                                if (isSignUp) signUpEmail = it else email = it
                            },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text(stringResource(R.string.auth_email)) },
                            singleLine = true,
                            shape = RoundedCornerShape(16.dp),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email)
                        )
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
                                shape = RoundedCornerShape(16.dp),
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email)
                            )
                            OutlinedTextField(
                                value = displayName,
                                onValueChange = { value ->
                                    localMessage = null
                                    displayName = value
                                        .filter {
                                            it.isLetterOrDigit() || it == ' ' || it == '.' ||
                                                it == '-' || it == '_'
                                        }
                                        .replace(Regex("\\s+"), " ")
                                        .take(32)
                                },
                                modifier = Modifier.fillMaxWidth(),
                                label = { Text(stringResource(R.string.auth_display_name)) },
                                singleLine = true,
                                shape = RoundedCornerShape(16.dp)
                            )
                        }

                        PasswordTextField(
                            value = if (isSignUp) signUpPassword else password,
                            onValueChange = {
                                localMessage = null
                                if (isSignUp) signUpPassword = it else password = it
                            },
                            passwordVisible = if (isSignUp) {
                                signUpPasswordVisible
                            } else {
                                loginPasswordVisible
                            },
                            onPasswordVisibilityChange = {
                                if (isSignUp) {
                                    signUpPasswordVisible = it
                                } else {
                                    loginPasswordVisible = it
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                            label = stringResource(R.string.auth_password),
                            onFocusChanged = { focused ->
                                if (isSignUp) signUpPasswordFocused = focused
                            }
                        )

                        if (isSignUp) {
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
                        }
                    }

                    if (isSignUp && signUpPasswordFocused) {
                        Text(
                            text = stringResource(R.string.auth_signup_requirements),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    localMessage?.let { message ->
                        AuthStatusBanner(message = message, isError = true)
                    }
                    uiState.message?.let { message ->
                        AuthStatusBanner(
                            message = message.asString(),
                            isError = uiState.messageIsError
                        )
                    }

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
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 50.dp)
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(9.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            if (uiState.isLoading) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(18.dp),
                                    color = MaterialTheme.colorScheme.onPrimary,
                                    strokeWidth = 2.dp
                                )
                            }
                            Text(
                                stringResource(
                                    if (isSignUp) {
                                        R.string.auth_create_account
                                    } else {
                                        R.string.auth_log_in
                                    }
                                )
                            )
                        }
                    }

                    if (!isSignUp) {
                        TextButton(
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
                            shape = RoundedCornerShape(16.dp),
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = 48.dp)
                        ) {
                            Text(stringResource(R.string.auth_forgot_password))
                        }
                    }

                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    OutlinedButton(
                        onClick = {
                            localProfileMessage = null
                            showOfflineSheet = true
                        },
                        enabled = !uiState.isLoading,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
                        shape = RoundedCornerShape(16.dp)
                    ) {
                        Icon(Icons.Default.PhoneAndroid, contentDescription = null)
                        Text(
                            text = stringResource(R.string.auth_continue_offline),
                            modifier = Modifier.padding(start = 8.dp)
                        )
                    }
                    }
                }
            }

            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = stringResource(R.string.auth_legal_consequence),
                        modifier = Modifier.fillMaxWidth(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        AuthExternalLink(
                            label = stringResource(R.string.auth_privacy_policy),
                            url = AUTH_PRIVACY_URL,
                            icon = Icons.Outlined.BackHand,
                            modifier = Modifier.weight(1f)
                        )
                        AuthExternalLink(
                            label = stringResource(R.string.auth_support),
                            url = AUTH_SUPPORT_URL,
                            icon = Icons.AutoMirrored.Outlined.HelpOutline,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }

    }

    if (showOfflineSheet) {
        ModalBottomSheet(onDismissRequest = { showOfflineSheet = false }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 18.dp, end = 18.dp, bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Text(
                    text = stringResource(R.string.auth_offline_profile),
                    modifier = Modifier.semantics { heading() },
                    style = MaterialTheme.typography.headlineSmall
                )
                Text(
                    text = stringResource(R.string.auth_offline_consequence),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                uiState.message?.takeIf { uiState.messageIsError }?.let { message ->
                    AuthStatusBanner(message = message.asString(), isError = true)
                }
                OutlinedTextField(
                    value = localDisplayName,
                    onValueChange = {
                        localProfileMessage = null
                        localDisplayName = boundedNewLocalDisplayNameDraft(it)
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.auth_local_profile_name)) },
                    placeholder = { Text("Local") },
                    singleLine = true,
                    shape = RoundedCornerShape(16.dp)
                )
                localProfileMessage?.let { message ->
                    AuthStatusBanner(message = message, isError = true)
                }
                Button(
                    onClick = {
                        val validation = validateLocalAccountInput(localDisplayName)
                        if (validation == null) {
                            localProfileMessage = null
                            onContinueLocal(localDisplayName.trim().ifBlank { "Local" }, false)
                        } else {
                            localProfileMessage = localizedAuthValidationMessage(context, validation)
                        }
                    },
                    enabled = !uiState.isLoading,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Text(stringResource(R.string.auth_continue_offline))
                }
                OutlinedButton(
                    onClick = { showOfflineSheet = false },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Text(stringResource(R.string.action_cancel))
                }
                if (savedLocalProfiles.isNotEmpty()) {
                    Text(
                        text = stringResource(R.string.auth_saved_profiles),
                        style = MaterialTheme.typography.titleMedium
                    )
                    savedLocalProfiles.forEach { savedProfile ->
                        OutlinedButton(
                            onClick = { onContinueLocal(savedProfile.id, true) },
                            enabled = !uiState.isLoading,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                            shape = RoundedCornerShape(16.dp)
                        ) {
                            Text(
                                savedProfile.displayName,
                                maxLines = 1,
                                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AuthLanguageSelector(
    selectedLanguage: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit,
    modifier: Modifier = Modifier
) {
    var expanded by remember { mutableStateOf(false) }
    val languageContentColor = LocalContentColor.current
    Box(modifier = modifier) {
        OutlinedButton(
            onClick = { expanded = true },
            shape = RoundedCornerShape(14.dp),
            border = BorderStroke(1.dp, languageContentColor.copy(alpha = 0.28f)),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = languageContentColor),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp)
        ) {
            Icon(
                Icons.Default.Language,
                contentDescription = stringResource(R.string.cd_language),
                modifier = Modifier.size(18.dp)
            )
            Text(
                text = selectedLanguage.visibleCode(),
                modifier = Modifier.padding(start = 6.dp),
                style = MaterialTheme.typography.labelLarge
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            listOf(
                AppLanguage.EN to stringResource(R.string.language_name_english),
                AppLanguage.UK to stringResource(R.string.language_name_ukrainian),
                AppLanguage.RU to stringResource(R.string.language_name_russian)
            ).forEach { (language, label) ->
                DropdownMenuItem(
                    text = {
                        Text(
                            text = label,
                            color = if (language == selectedLanguage) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurface
                            }
                        )
                    },
                    onClick = {
                        expanded = false
                        onLanguageSelected(language)
                    }
                )
            }
        }
    }
}

internal fun AppLanguage.visibleCode(): String = when (this) {
    AppLanguage.EN -> "EN"
    AppLanguage.UK -> "UK"
    AppLanguage.RU -> "RU"
}

@Composable
private fun AuthExternalLink(
    label: String,
    url: String,
    icon: ImageVector,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    TextButton(
        onClick = { openStaticWebPage(context, url) },
        modifier = modifier.heightIn(min = 48.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 2.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(15.dp)
        )
        Text(
            text = label,
            modifier = Modifier.padding(start = 2.dp),
            maxLines = 2,
            softWrap = true,
            textAlign = TextAlign.Center,
            style = MaterialTheme.typography.labelMedium
        )
    }
}

private fun openStaticWebPage(context: Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }
}

private const val AUTH_PRIVACY_URL = "https://gymapptracker.com/privacy-policy.html"
private const val AUTH_SUPPORT_URL = "https://gymapptracker.com/support.html"

private fun openEmailInbox(context: Context): Boolean {
    return try {
        context.startActivity(
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_APP_EMAIL)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }
}

@Composable
private fun EmailConfirmationCard(
    email: String,
    isLoading: Boolean,
    onOpenEmail: () -> Unit,
    onResend: () -> Unit,
    onChangeAddress: () -> Unit,
    onBackToSignIn: () -> Unit,
    modifier: Modifier = Modifier
) {
    val accent = MaterialTheme.colorScheme.primary
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.48f))
            .border(BorderStroke(1.dp, accent.copy(alpha = 0.3f)), shape)
            .semantics { liveRegion = LiveRegionMode.Polite }
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(accent.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Filled.Email,
                    contentDescription = null,
                    tint = accent
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    text = stringResource(R.string.auth_confirmation_sent_to),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = email,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
        }

        Text(
            text = stringResource(R.string.auth_confirmation_spam_hint),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Button(
            onClick = onOpenEmail,
            enabled = !isLoading,
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp)
        ) {
            Text(stringResource(R.string.auth_confirmation_open_email))
        }
        OutlinedButton(
            onClick = onResend,
            enabled = !isLoading,
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
        ) {
            Text(stringResource(R.string.auth_confirmation_resend))
        }
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            TextButton(
                onClick = onChangeAddress,
                enabled = !isLoading,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.auth_confirmation_change_address))
            }
            TextButton(
                onClick = onBackToSignIn,
                enabled = !isLoading,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.auth_confirmation_back_to_sign_in))
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
    var passwordFocused by remember { mutableStateOf(false) }
    var localMessage by remember { mutableStateOf<String?>(null) }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
    ) {
        Column(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .widthIn(max = 560.dp)
                .fillMaxWidth()
                .heightIn(min = maxHeight)
                .padding(start = 16.dp, top = 20.dp, end = 16.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            HeroPanel(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    AuthHeroMark(imageVector = Icons.Filled.Key)
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        Text(
                            text = stringResource(R.string.auth_choose_new_password),
                            modifier = Modifier.semantics { heading() },
                            style = MaterialTheme.typography.titleLarge
                        )
                        Text(
                            text = stringResource(R.string.auth_recovery_verified),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.White.copy(alpha = 0.84f)
                        )
                    }
                }
            }

            AppPanel(
                modifier = Modifier.fillMaxWidth(),
                highlighted = true
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(13.dp)) {
                        PasswordTextField(
                            value = password,
                            onValueChange = {
                                localMessage = null
                                password = it
                            },
                            passwordVisible = passwordVisible,
                            onPasswordVisibilityChange = { passwordVisible = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = stringResource(R.string.auth_new_password),
                            onFocusChanged = { passwordFocused = it }
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
                    }
                    if (passwordFocused) {
                        Text(
                            text = stringResource(R.string.auth_new_password_requirements),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    localMessage?.let { message ->
                        AuthStatusBanner(message = message, isError = true)
                    }
                    uiState.message?.let { message ->
                        AuthStatusBanner(
                            message = message.asString(),
                            isError = uiState.messageIsError
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
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 50.dp)
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(9.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            if (uiState.isLoading) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(18.dp),
                                    color = MaterialTheme.colorScheme.onPrimary,
                                    strokeWidth = 2.dp
                                )
                            }
                            Text(
                                stringResource(
                                    if (uiState.isLoading) {
                                        R.string.auth_updating_password
                                    } else {
                                        R.string.auth_update_password
                                    }
                                )
                            )
                        }
                    }
                    TextButton(
                        onClick = onCancel,
                        enabled = !uiState.isLoading,
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                    ) {
                        Text(stringResource(R.string.auth_cancel_recovery))
                    }
                }
            }
        }
    }
}

@Composable
private fun AuthHeroMark(
    imageVector: ImageVector,
    modifier: Modifier = Modifier
) {
    val darkTheme = isSystemInDarkTheme()
    val leading = if (darkTheme) Color(0xFF132636) else Color(0xFF102A42)
    val trailing = if (darkTheme) Color(0xFF214C40) else Color(0xFF35627E)
    val shape = RoundedCornerShape(22.dp)

    Box(
        modifier = modifier
            .size(72.dp)
            .shadow(
                elevation = 16.dp,
                shape = shape,
                clip = false,
                ambientColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.30f),
                spotColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.30f)
            )
            .clip(shape)
            .background(
                brush = Brush.linearGradient(
                    colors = listOf(leading, trailing),
                    start = Offset.Zero,
                    end = Offset.Infinite
                ),
                shape = shape
            )
            .border(
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.18f)),
                shape = shape
            ),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = imageVector,
            contentDescription = null,
            modifier = Modifier.size(30.dp),
            tint = Color.White
        )
    }
}

@Composable
private fun AuthModeSelector(
    isSignUp: Boolean,
    enabled: Boolean,
    onModeSelected: (isSignUp: Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(16.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .alpha(if (enabled) 1f else 0.56f)
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.58f))
            .border(
                border = BorderStroke(
                    1.dp,
                    MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.58f)
                ),
                shape = shape
            )
            .padding(4.dp)
            .selectableGroup(),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        AuthModeOption(
            text = stringResource(R.string.auth_log_in),
            selected = !isSignUp,
            enabled = enabled,
            onClick = { onModeSelected(false) },
            modifier = Modifier.weight(1f)
        )
        AuthModeOption(
            text = stringResource(R.string.auth_create_account),
            selected = isSignUp,
            enabled = enabled,
            onClick = { onModeSelected(true) },
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun AuthModeOption(
    text: String,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val shape = RoundedCornerShape(13.dp)
    val backgroundColor = if (selected) {
        MaterialTheme.colorScheme.surface
    } else {
        Color.Transparent
    }
    val borderColor = if (selected) {
        MaterialTheme.colorScheme.primary.copy(alpha = 0.30f)
    } else {
        Color.Transparent
    }
    Box(
        modifier = modifier
            .clip(shape)
            .background(backgroundColor)
            .border(BorderStroke(1.dp, borderColor), shape)
            .selectable(
                selected = selected,
                enabled = enabled,
                role = Role.RadioButton,
                onClick = onClick
            )
            .heightIn(min = 48.dp)
            .padding(horizontal = 10.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            color = if (selected) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
            style = MaterialTheme.typography.labelLarge,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun AuthStatusBanner(
    message: String,
    isError: Boolean,
    modifier: Modifier = Modifier
) {
    val accent = if (isError) {
        MaterialTheme.colorScheme.error
    } else {
        MaterialTheme.colorScheme.primary
    }
    val shape = RoundedCornerShape(16.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(accent.copy(alpha = 0.11f))
            .border(BorderStroke(1.dp, accent.copy(alpha = 0.26f)), shape)
            .semantics(mergeDescendants = true) {
                liveRegion = LiveRegionMode.Polite
            }
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top
    ) {
        Icon(
            imageVector = if (isError) Icons.Filled.Error else Icons.Filled.CheckCircle,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = accent
        )
        Text(
            text = message,
            modifier = Modifier.weight(1f),
            color = MaterialTheme.colorScheme.onSurface,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}

@Composable
private fun PasswordTextField(
    value: String,
    onValueChange: (String) -> Unit,
    passwordVisible: Boolean,
    onPasswordVisibilityChange: (Boolean) -> Unit,
    label: String,
    onFocusChanged: (Boolean) -> Unit = {},
    modifier: Modifier = Modifier
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.onFocusChanged { state -> onFocusChanged(state.isFocused) },
        label = { Text(label) },
        singleLine = true,
        shape = RoundedCornerShape(16.dp),
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
        "Password must contain at least 12 characters and fit within 72 UTF-8 bytes." ->
            R.string.auth_error_password_minimum
        "Password must include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol." ->
            R.string.auth_error_password_complexity
        "Passwords do not match." -> R.string.auth_error_password_mismatch
        "Enter a new password." -> R.string.auth_error_new_password_required
        "Local profile name is invalid or too long." -> R.string.auth_error_local_profile_name
        "Display name must be 2–32 characters and use letters, numbers, spaces, dot, dash or underscore." ->
            R.string.auth_error_local_profile_contract
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
        !newPasswordLengthIsValid(password) ->
            "Password must contain at least 12 characters and fit within 72 UTF-8 bytes."
        !newPasswordCharacterGroupsAreValid(password) ->
            "Password must include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol."
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

internal fun validateLocalAccountInput(displayName: String): String? {
    val candidate = displayName.trim().ifBlank { "Local" }
    return if (validatedNewLocalDisplayNameOrNull(candidate) == null) {
        "Display name must be 2–32 characters and use letters, numbers, spaces, dot, dash or underscore."
    } else {
        null
    }
}

internal fun validatePasswordUpdateInput(
    password: String,
    passwordConfirm: String
): String? {
    return when {
        password.isBlank() -> "Enter a new password."
        !newPasswordLengthIsValid(password) ->
            "Password must contain at least 12 characters and fit within 72 UTF-8 bytes."
        !newPasswordCharacterGroupsAreValid(password) ->
            "Password must include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol."
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
