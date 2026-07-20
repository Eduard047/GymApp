import SwiftUI

struct AppLanguageMenu: View {
    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue

    var body: some View {
        Menu {
            Picker("Language", selection: $languageCode) {
                Label("English", systemImage: languageCode == "en" ? "checkmark" : "globe").tag("en")
                Label("Українська", systemImage: languageCode == "uk" ? "checkmark" : "globe").tag("uk")
                Label("Русский", systemImage: languageCode == "ru" ? "checkmark" : "globe").tag("ru")
            }
        } label: {
            Label(languageCode.uppercased(), systemImage: "globe")
                .labelStyle(.titleAndIcon)
        }
        .accessibilityLabel(gymText("Language", "Мова", languageCode: languageCode))
        .accessibilityValue(languageCode == "uk" ? "Українська" : languageCode == "ru" ? "Русский" : "English")
    }
}

extension View {
    func gymLanguageToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AppLanguageMenu()
            }
        }
    }
}
