package com.example.gymapp.push

import org.json.JSONObject
import org.json.JSONTokener
import java.time.OffsetDateTime

internal data class PushRegistration(
    val installationId: String,
    val bindingId: String,
    val registrationRevision: Int
)

internal data class PushRevocation(
    val installationId: String,
    val revoked: Boolean
)

/** `revoked=false` is the RPC's idempotent already-absent/already-revoked success state. */
internal fun pushRevocationReachedDesiredState(response: PushRevocation?): Boolean =
    response != null

internal fun pushRegistrationRequestJson(
    installationId: String,
    providerToken: String,
    locale: String?,
    appVersion: String
): String {
    require(isCanonicalV4Uuid(installationId)) { "Push installation ID is invalid." }
    require(isValidFcmProviderToken(providerToken)) { "Push provider token is invalid." }
    require(locale == null || LOCALE_PATTERN.matches(locale)) { "Push locale is invalid." }
    require(APP_VERSION_PATTERN.matches(appVersion)) { "Push app version is invalid." }
    return JSONObject()
        .put("p_installation_id", installationId)
        .put("p_platform", "android")
        .put("p_provider", "fcm")
        .put("p_environment", "production")
        .put("p_provider_token", providerToken)
        .put("p_web_push_p256dh", JSONObject.NULL)
        .put("p_web_push_auth", JSONObject.NULL)
        .put("p_locale", locale ?: JSONObject.NULL)
        .put("p_app_version", appVersion)
        .toString()
}

internal fun pushRevocationRequestJson(installationId: String): String {
    require(isCanonicalV4Uuid(installationId)) { "Push installation ID is invalid." }
    return JSONObject().put("p_installation_id", installationId).toString()
}

internal fun parsePushRegistrationResponse(
    raw: String,
    expectedInstallationId: String
): PushRegistration {
    require(raw.toByteArray(Charsets.UTF_8).size <= MAX_PUSH_RPC_RESPONSE_BYTES) {
        "Push registration response is invalid."
    }
    val root = strictJsonObject(raw)
    require(root.keys().asSequence().toSet() == REGISTRATION_RESPONSE_KEYS) {
        "Push registration response is invalid."
    }
    require(root.strictInt("version", 1, 1) == PUSH_CONTRACT_VERSION) {
        "Push registration response is invalid."
    }
    val installationId = root.strictString("installationId", 36)
    require(installationId == expectedInstallationId && isCanonicalV4Uuid(installationId)) {
        "Push registration response is invalid."
    }
    require(root.strictString("provider", 16) == "fcm") {
        "Push registration response is invalid."
    }
    require(root.strictString("environment", 16) == "production") {
        "Push registration response is invalid."
    }
    val bindingId = root.strictString("bindingId", 36)
    require(isCanonicalV4Uuid(bindingId)) { "Push registration response is invalid." }
    val revision = root.strictInt("registrationRevision", 1, Int.MAX_VALUE)
    val registeredAt = root.strictString("registeredAt", 64)
    require(runCatching { OffsetDateTime.parse(registeredAt) }.isSuccess) {
        "Push registration response is invalid."
    }
    return PushRegistration(
        installationId = installationId,
        bindingId = bindingId,
        registrationRevision = revision
    )
}

internal fun parsePushRevocationResponse(
    raw: String,
    expectedInstallationId: String
): PushRevocation {
    require(raw.toByteArray(Charsets.UTF_8).size <= MAX_PUSH_RPC_RESPONSE_BYTES) {
        "Push revocation response is invalid."
    }
    val root = strictJsonObject(raw)
    require(root.keys().asSequence().toSet() == REVOCATION_RESPONSE_KEYS) {
        "Push revocation response is invalid."
    }
    require(root.strictInt("version", 1, 1) == PUSH_CONTRACT_VERSION) {
        "Push revocation response is invalid."
    }
    val installationId = root.strictString("installationId", 36)
    require(installationId == expectedInstallationId && isCanonicalV4Uuid(installationId)) {
        "Push revocation response is invalid."
    }
    val revoked = root.opt("revoked") as? Boolean
        ?: error("Push revocation response is invalid.")
    return PushRevocation(installationId, revoked)
}

internal fun normalizedPushLocale(language: String?, country: String?): String? {
    val normalizedLanguage = language?.lowercase()?.takeIf {
        it.matches(Regex("^[a-z]{2,3}$"))
    } ?: return null
    val normalizedCountry = country?.uppercase()?.takeIf {
        it.matches(Regex("^[A-Z0-9]{2,8}$"))
    }
    return if (normalizedCountry == null) normalizedLanguage
    else "$normalizedLanguage-$normalizedCountry"
}

internal fun isValidFcmProviderToken(value: String): Boolean = FCM_TOKEN_PATTERN.matches(value)

private fun strictJsonObject(raw: String): JSONObject {
    val tokener = JSONTokener(raw)
    val root = tokener.nextValue() as? JSONObject
        ?: error("Push response is invalid.")
    require(tokener.nextClean() == '\u0000') { "Push response is invalid." }
    return root
}

private fun JSONObject.strictString(key: String, maximumCodePoints: Int): String {
    val value = opt(key) as? String ?: error("Push response is invalid.")
    require(value.isNotEmpty() && value.codePointCount(0, value.length) <= maximumCodePoints) {
        "Push response is invalid."
    }
    require(value.none(Char::isISOControl)) { "Push response is invalid." }
    return value
}

private fun JSONObject.strictInt(key: String, minimum: Int, maximum: Int): Int {
    val value = opt(key)
    require(value is Int || value is Long) { "Push response is invalid." }
    val number = (value as Number).toLong()
    require(number in minimum.toLong()..maximum.toLong()) { "Push response is invalid." }
    return number.toInt()
}

private const val MAX_PUSH_RPC_RESPONSE_BYTES = 4 * 1_024
private val FCM_TOKEN_PATTERN = Regex("^[A-Za-z0-9_:-]{32,4096}$")
private val LOCALE_PATTERN = Regex("^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,2}$")
private val APP_VERSION_PATTERN = Regex("^[A-Za-z0-9._+-]{1,32}$")
private val REGISTRATION_RESPONSE_KEYS = setOf(
    "version",
    "installationId",
    "provider",
    "environment",
    "bindingId",
    "registrationRevision",
    "registeredAt"
)
private val REVOCATION_RESPONSE_KEYS = setOf(
    "version",
    "installationId",
    "revoked"
)
