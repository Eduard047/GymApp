import Foundation

func insecureCredentialStorage(_ token: String) {
    // ruleid: gymapp-swift-sensitive-userdefaults
    UserDefaults.standard.set(token, forKey: "accessToken")
}

func insecureMultilineCredentialStorage(_ token: String) {
    UserDefaults.standard.set(
        token,
        // ruleid: gymapp-swift-sensitive-userdefaults
        forKey: "refresh_token"
    )
}

func ordinaryPreferenceStorage(_ token: String) {
    // ok: gymapp-swift-sensitive-userdefaults
    UserDefaults.standard.set(token, forKey: "syncEnabled")
}

func insecureComputedCredentialKey(_ token: String, accessTokenStorageKey: String) {
    // ruleid: gymapp-swift-sensitive-userdefaults
    UserDefaults.standard.set(token, forKey: accessTokenStorageKey)
}

func cleartextURL() -> String {
    // ruleid: gymapp-hardcoded-cleartext-url
    "http://example.invalid/api"
}

func secureURL() -> String {
    // ok: gymapp-hardcoded-cleartext-url
    "https://example.invalid/api"
}
