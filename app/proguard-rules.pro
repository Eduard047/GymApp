# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# Garmin Connect sends SDK Parcelable objects through broadcasts using their
# original fully qualified class names. Renaming these classes makes Android
# unable to unmarshal an incoming watch message before our receiver can handle
# it, causing a release-only BadParcelableException.
-keep class com.garmin.android.connectiq.IQDevice { *; }
-keep class com.garmin.android.connectiq.IQApp { *; }
-keep class com.garmin.android.connectiq.IQMessage { *; }

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile
-keep class com.example.gymapp.push.PushReconciliationWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# kotlinx-coroutines-slf4j supports an optional SLF4J 1.x binding. GymApp does
# not install that backend, so its legacy discovery class is intentionally absent.
-dontwarn org.slf4j.impl.StaticLoggerBinder
