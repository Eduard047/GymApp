import Foundation

func insecureCredentialStorage(_ token: String) {
    // ruleid: gymapp-swift-sensitive-userdefaults
    UserDefaults.standard.set(token, forKey: "accessToken")
}

func cleartextURL() -> String {
    // ruleid: gymapp-hardcoded-cleartext-url
    "http://example.invalid/api"
}

func secureURL() -> String {
    // ok: gymapp-hardcoded-cleartext-url
    "https://example.invalid/api"
}
