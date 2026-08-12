import SwiftUI

struct AppLanguageMenu: View {
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    var onHero = false

    var body: some View {
        Menu {
            Picker("Language", selection: $languageCode) {
                Label("English", systemImage: languageCode == "en" ? "checkmark" : "globe").tag("en")
                Label("Українська", systemImage: languageCode == "uk" ? "checkmark" : "globe").tag("uk")
                Label("Русский", systemImage: languageCode == "ru" ? "checkmark" : "globe").tag("ru")
            }
        } label: {
            Label(
                AppLanguage(rawValue: languageCode)?.title ?? AppLanguage.english.title,
                systemImage: "globe"
            )
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 7)
                .foregroundStyle(onHero ? Color.white : GymTheme.primary)
                .background(
                    Capsule().fill(
                        onHero
                            ? Color.white.opacity(0.12)
                            : GymTheme.surfaceVariant.opacity(0.72)
                    )
                )
                .overlay {
                    Capsule().strokeBorder(
                        onHero
                            ? Color.white.opacity(0.26)
                            : GymTheme.outlineSoft.opacity(0.72),
                        lineWidth: 1
                    )
                }
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
