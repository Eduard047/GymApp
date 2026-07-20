fun commandExecution() {
    // ruleid: gymapp-kotlin-process-execution
    Runtime.getRuntime().exec("id")
}

fun dangerousWebView(webView: android.webkit.WebView) {
    // ruleid: gymapp-kotlin-dangerous-webview-bridge
    webView.addJavascriptInterface(Any(), "bridge")
}

fun sensitiveLogging(token: String) {
    // ruleid: gymapp-kotlin-sensitive-logging
    android.util.Log.i("Auth", "accessToken=$token")
    // ok: gymapp-kotlin-sensitive-logging
    android.util.Log.i("Sync", "sync rejected")
}

fun cleartextUrl(): String {
    // ruleid: gymapp-hardcoded-cleartext-url
    return "http://example.invalid/api"
}

fun secureUrl(): String {
    // ok: gymapp-hardcoded-cleartext-url
    return "https://example.invalid/api"
}
