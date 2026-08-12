import groovy.json.JsonSlurper
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    id("org.jetbrains.kotlin.kapt")
}

fun autoVersionCode(): Int {
    val base = Instant.parse("2026-01-01T00:00:00Z")
    val minutes = Duration.between(base, Instant.now()).toMinutes().toInt()
    return 2_000_000_000 + minutes
}

val appVersionCode = (findProperty("appVersionCode") as String?)?.toIntOrNull() ?: autoVersionCode()
val appVersionName = (findProperty("appVersionName") as String?) ?: LocalDateTime.now()
    .format(DateTimeFormatter.ofPattern("yyyy.MM.dd.HHmm"))
val useDevApplicationIdSuffix = (findProperty("devApplicationIdSuffix") as String?) != "false"
data class FirebaseClientBuildConfig(
    val projectId: String,
    val applicationId: String,
    val apiKey: String,
    val senderId: String
)

fun firebaseClientBuildConfigs(): Map<String, FirebaseClientBuildConfig> {
    val configuredPath = (findProperty("gymappFirebaseConfigFile") as String?)
        ?.trim()
        ?.takeIf(String::isNotEmpty)
        ?: return emptyMap()
    val configFile = rootProject.file(configuredPath)
    require(configFile.isFile) {
        "gymappFirebaseConfigFile must point to a readable google-services.json file."
    }
    val root = JsonSlurper().parse(configFile) as? Map<*, *>
        ?: error("google-services.json must contain a JSON object.")
    val projectInfo = root["project_info"] as? Map<*, *>
        ?: error("google-services.json is missing project_info.")
    val projectId = projectInfo["project_id"] as? String
        ?: error("google-services.json is missing project_info.project_id.")
    val senderId = projectInfo["project_number"] as? String
        ?: error("google-services.json is missing project_info.project_number.")
    require(projectId.matches(Regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$"))) {
        "google-services.json contains an invalid Firebase project ID."
    }
    require(senderId.matches(Regex("^[0-9]{6,32}$"))) {
        "google-services.json contains an invalid Firebase sender ID."
    }
    val clients = root["client"] as? List<*>
        ?: error("google-services.json is missing client entries.")
    return clients.mapNotNull { rawClient ->
        val client = rawClient as? Map<*, *> ?: return@mapNotNull null
        val clientInfo = client["client_info"] as? Map<*, *> ?: return@mapNotNull null
        val androidInfo = clientInfo["android_client_info"] as? Map<*, *>
            ?: return@mapNotNull null
        val packageName = androidInfo["package_name"] as? String ?: return@mapNotNull null
        if (packageName !in setOf("com.setforge.gymapp", "com.setforge.gymapp.dev")) {
            return@mapNotNull null
        }
        val applicationId = clientInfo["mobilesdk_app_id"] as? String
            ?: error("Firebase client $packageName is missing mobilesdk_app_id.")
        val apiKeys = client["api_key"] as? List<*>
            ?: error("Firebase client $packageName is missing api_key.")
        val apiKey = apiKeys.asSequence()
            .mapNotNull { it as? Map<*, *> }
            .mapNotNull { it["current_key"] as? String }
            .firstOrNull()
            ?: error("Firebase client $packageName is missing api_key.current_key.")
        require(applicationId.matches(Regex("^1:[0-9]{6,32}:android:[0-9a-f]{16,64}$"))) {
            "Firebase client $packageName contains an invalid mobilesdk_app_id."
        }
        require(apiKey.matches(Regex("^AIza[A-Za-z0-9_-]{20,200}$"))) {
            "Firebase client $packageName contains an invalid API key."
        }
        packageName to FirebaseClientBuildConfig(
            projectId = projectId,
            applicationId = applicationId,
            apiKey = apiKey,
            senderId = senderId
        )
    }.toMap().also {
        require(it.isNotEmpty()) {
            "google-services.json has no GymApp Android client."
        }
    }
}

fun buildConfigString(value: String): String =
    "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""

val firebaseClients = firebaseClientBuildConfigs()
val productionFirebaseClient = firebaseClients["com.setforge.gymapp"]
val developmentFirebaseClient = firebaseClients["com.setforge.gymapp.dev"]
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use(::load)
    }
}

android {
    namespace = "com.example.gymapp"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "com.setforge.gymapp"
        minSdk = 24
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersionName

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        manifestPlaceholders["authCallbackScheme"] = "com.setforge.gymapp"
        buildConfigField("String", "AUTH_CALLBACK_SCHEME", "\"com.setforge.gymapp\"")
        buildConfigField("String", "AUTH_BRIDGE_VARIANT_QUERY", "\"\"")
        buildConfigField("boolean", "FIREBASE_CONFIGURED", "false")
        buildConfigField("String", "FIREBASE_PROJECT_ID", "\"\"")
        buildConfigField("String", "FIREBASE_APPLICATION_ID", "\"\"")
        buildConfigField("String", "FIREBASE_API_KEY", "\"\"")
        buildConfigField("String", "FIREBASE_SENDER_ID", "\"\"")
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            if (useDevApplicationIdSuffix) {
                applicationIdSuffix = ".dev"
                versionNameSuffix = "-dev"
            }
            manifestPlaceholders["authCallbackScheme"] = "com.setforge.gymapp.dev"
            buildConfigField("String", "AUTH_CALLBACK_SCHEME", "\"com.setforge.gymapp.dev\"")
            buildConfigField("String", "AUTH_BRIDGE_VARIANT_QUERY", "\"&variant=qa\"")
            val firebaseClient = if (useDevApplicationIdSuffix) {
                developmentFirebaseClient
            } else {
                productionFirebaseClient
            }
            buildConfigField(
                "boolean",
                "FIREBASE_CONFIGURED",
                "${firebaseClient != null}"
            )
            buildConfigField(
                "String",
                "FIREBASE_PROJECT_ID",
                buildConfigString(firebaseClient?.projectId.orEmpty())
            )
            buildConfigField(
                "String",
                "FIREBASE_APPLICATION_ID",
                buildConfigString(firebaseClient?.applicationId.orEmpty())
            )
            buildConfigField(
                "String",
                "FIREBASE_API_KEY",
                buildConfigString(firebaseClient?.apiKey.orEmpty())
            )
            buildConfigField(
                "String",
                "FIREBASE_SENDER_ID",
                buildConfigString(firebaseClient?.senderId.orEmpty())
            )
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            buildConfigField(
                "boolean",
                "FIREBASE_CONFIGURED",
                "${productionFirebaseClient != null}"
            )
            buildConfigField(
                "String",
                "FIREBASE_PROJECT_ID",
                buildConfigString(productionFirebaseClient?.projectId.orEmpty())
            )
            buildConfigField(
                "String",
                "FIREBASE_APPLICATION_ID",
                buildConfigString(productionFirebaseClient?.applicationId.orEmpty())
            )
            buildConfigField(
                "String",
                "FIREBASE_API_KEY",
                buildConfigString(productionFirebaseClient?.apiKey.orEmpty())
            )
            buildConfigField(
                "String",
                "FIREBASE_SENDER_ID",
                buildConfigString(productionFirebaseClient?.senderId.orEmpty())
            )
        }
        create("qa") {
            initWith(getByName("release"))
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-qa"
            isDebuggable = false
            signingConfig = signingConfigs.getByName("debug")
            manifestPlaceholders["authCallbackScheme"] = "com.setforge.gymapp.dev"
            buildConfigField("String", "AUTH_CALLBACK_SCHEME", "\"com.setforge.gymapp.dev\"")
            buildConfigField("String", "AUTH_BRIDGE_VARIANT_QUERY", "\"&variant=qa\"")
            buildConfigField(
                "boolean",
                "FIREBASE_CONFIGURED",
                "${developmentFirebaseClient != null}"
            )
            buildConfigField(
                "String",
                "FIREBASE_PROJECT_ID",
                buildConfigString(developmentFirebaseClient?.projectId.orEmpty())
            )
            buildConfigField(
                "String",
                "FIREBASE_APPLICATION_ID",
                buildConfigString(developmentFirebaseClient?.applicationId.orEmpty())
            )
            buildConfigField(
                "String",
                "FIREBASE_API_KEY",
                buildConfigString(developmentFirebaseClient?.apiKey.orEmpty())
            )
            buildConfigField(
                "String",
                "FIREBASE_SENDER_ID",
                buildConfigString(developmentFirebaseClient?.senderId.orEmpty())
            )
            matchingFallbacks += listOf("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        buildConfig = true
        compose = true
    }
    androidResources {
        // aapt ignore syntax is colon-delimited and matched against each asset
        // basename. Preserve Finder duplicates on disk, but never package them.
        ignoreAssetsPattern = "!.svn:!.git:!.ds_store:!*.scc:.*:<dir>_*:*~:* 2.jpg"
    }
    sourceSets {
        getByName("androidTest").assets.srcDir(file("schemas"))
    }
}

kapt {
    correctErrorTypes = true
    arguments {
        arg("room.schemaLocation", file("schemas").path)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.14.0")
    implementation("androidx.room:room-runtime:2.8.4")
    implementation("androidx.room:room-ktx:2.8.4")
    kapt("androidx.room:room-compiler:2.8.4")
    implementation("androidx.navigation:navigation-compose:2.7.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation(platform("io.github.jan-tennert.supabase:bom:2.6.1"))
    implementation("io.github.jan-tennert.supabase:realtime-kt")
    implementation("io.ktor:ktor-client-okhttp:2.3.12")
    implementation("com.garmin.connectiq:ciq-companion-app-sdk:2.4.0@aar")
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation("androidx.compose.material:material-icons-extended")
    testImplementation(libs.junit)
    testImplementation("org.json:json:20240303")
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation("androidx.room:room-testing:2.8.4")
    debugImplementation(platform("org.jetbrains.kotlinx:kotlinx-serialization-bom:1.8.1"))
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
}
