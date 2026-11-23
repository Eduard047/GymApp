import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.android.legacy-kapt")
}

// Phone versionCode scheme (see app/build.gradle.kts): 2_000_000_000 + minutes since 2026-01-01.
fun autoVersionCode(): Int {
    val base = Instant.parse("2026-01-01T00:00:00Z")
    val minutes = Duration.between(base, Instant.now()).toMinutes().toInt()
    return 2_000_000_000 + minutes
}

// Same package as the phone app, so the watch build needs its own versionCode range. It is the
// phone's code plus a fixed offset: deterministic for a given appVersionCode, always higher than
// the phone's, and within Play's 2_100_000_000 ceiling. `-PwearVersionCode=` overrides it.
val wearVersionCodeOffset = 50_000_000
val phoneVersionCode = (findProperty("appVersionCode") as String?)?.toIntOrNull() ?: autoVersionCode()
val wearVersionCode = (findProperty("wearVersionCode") as String?)?.toIntOrNull()
    ?: (phoneVersionCode + wearVersionCodeOffset)
val wearVersionName = (findProperty("wearVersionName") as String?)
    ?: (findProperty("appVersionName") as String?)
    ?: LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy.MM.dd.HHmm"))
// Must match the phone app: the Data Layer pairs the two apps by package name and signature.
val useDevApplicationIdSuffix = (findProperty("devApplicationIdSuffix") as String?) != "false"

val releaseKeystorePath = providers.environmentVariable("GYMAPP_RELEASE_KEYSTORE_PATH").orNull
val releaseKeyAlias = providers.environmentVariable("GYMAPP_RELEASE_KEY_ALIAS").orNull
val releaseStorePassword = providers.environmentVariable("GYMAPP_RELEASE_STORE_PASSWORD").orNull
val releaseKeyPassword = providers.environmentVariable("GYMAPP_RELEASE_KEY_PASSWORD").orNull
val releaseSigningConfigured = listOf(
    releaseKeystorePath,
    releaseKeyAlias,
    releaseStorePassword,
    releaseKeyPassword
).all { !it.isNullOrBlank() }
if (listOf(
        releaseKeystorePath,
        releaseKeyAlias,
        releaseStorePassword,
        releaseKeyPassword
    ).any { !it.isNullOrBlank() } && !releaseSigningConfigured
) {
    error("Release signing requires all GYMAPP_RELEASE_* environment variables.")
}
val releaseKeystoreFile = releaseKeystorePath?.let(::file)?.canonicalFile
if (releaseKeystoreFile != null) {
    val repositoryRoot = rootProject.projectDir.canonicalFile.toPath()
    require(releaseKeystoreFile.isFile) { "The external release keystore was not found." }
    require(!releaseKeystoreFile.toPath().startsWith(repositoryRoot)) {
        "The release keystore must be stored outside the repository."
    }
}

android {
    namespace = "com.example.gymapp.wear"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "com.setforge.gymapp"
        minSdk = 30
        targetSdk = 36
        versionCode = wearVersionCode
        versionName = wearVersionName

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("release") {
            if (releaseSigningConfigured) {
                storeFile = releaseKeystoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            if (useDevApplicationIdSuffix) {
                applicationIdSuffix = ".dev"
                versionNameSuffix = "-dev"
            }
        }
        release {
            isMinifyEnabled = false
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        create("qa") {
            initWith(getByName("release"))
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-qa"
            isDebuggable = false
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    buildFeatures {
        compose = true
    }
}

kapt {
    correctErrorTypes = true
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation("androidx.wear:wear:1.3.0")
    // AmbientModeSupport pulls an old Fragment; registerForActivityResult needs Fragment >= 1.3.0
    // (otherwise the heart-rate permission request crashes with a requestCode error).
    implementation("androidx.fragment:fragment:1.8.5")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.8.1")
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
    // Heart rate / calories during a workout (ExerciseClient). 1.1.0 is the stable release.
    implementation("androidx.health:health-services-client:1.1.0")

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    // Compose for Wear OS (Material 3 for Wear). 1.5.6 is the stable line the watch UI spec targets.
    implementation("androidx.wear.compose:compose-material3:1.5.6")
    implementation("androidx.wear.compose:compose-foundation:1.5.6")
    implementation("androidx.wear.compose:compose-navigation:1.5.6")

    implementation("androidx.room:room-runtime:2.8.4")
    implementation("androidx.room:room-ktx:2.8.4")
    kapt("androidx.room:room-compiler:2.8.4")

    testImplementation(libs.junit)
    testImplementation("org.json:json:20240303")
}
