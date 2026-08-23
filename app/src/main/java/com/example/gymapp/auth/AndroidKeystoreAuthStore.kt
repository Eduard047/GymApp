package com.example.gymapp.auth

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class AndroidKeystoreAuthStore(
    context: Context,
    private val keyAlias: String = "gymapp-cloud-auth-v1"
) {
    private val preferences = context.applicationContext.getSharedPreferences(
        "gym_cloud_auth_secure",
        Context.MODE_PRIVATE
    )
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    @Synchronized
    fun putString(key: String, value: String): Boolean = runCatching {
        require(key.matches(Regex("^[a-z0-9_]{1,64}$")))
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, encryptionKey())
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val envelope = listOf(
            VERSION,
            Base64.encodeToString(cipher.iv, BASE64_FLAGS),
            Base64.encodeToString(ciphertext, BASE64_FLAGS)
        ).joinToString(":")
        preferences.edit().putString(key, envelope).commit()
    }.getOrDefault(false)

    @Synchronized
    fun getString(key: String): String? {
        val envelope = preferences.getString(key, null) ?: return null
        return runCatching {
            val parts = envelope.split(':')
            require(parts.size == 3 && parts[0] == VERSION)
            val iv = Base64.decode(parts[1], BASE64_FLAGS)
            val ciphertext = Base64.decode(parts[2], BASE64_FLAGS)
            require(iv.size == 12 && ciphertext.size in 16..MAX_CIPHERTEXT_BYTES)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, encryptionKey(), GCMParameterSpec(128, iv))
            cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
            val plaintext = cipher.doFinal(ciphertext)
            require(plaintext.size <= MAX_PLAINTEXT_BYTES)
            String(plaintext, Charsets.UTF_8)
        }.getOrElse {
            preferences.edit().remove(key).commit()
            null
        }
    }

    @Synchronized
    fun remove(key: String): Boolean = preferences.edit().remove(key).commit()

    @Synchronized
    fun clear(): Boolean = preferences.edit().clear().commit()

    private fun encryptionKey(): SecretKey {
        (keyStore.getKey(keyAlias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    private companion object {
        const val VERSION = "v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val MAX_PLAINTEXT_BYTES = 64 * 1024
        const val MAX_CIPHERTEXT_BYTES = MAX_PLAINTEXT_BYTES + 16
        const val BASE64_FLAGS = Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
    }
}
