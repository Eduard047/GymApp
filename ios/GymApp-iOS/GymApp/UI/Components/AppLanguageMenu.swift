import SwiftUI

struct AppLanguageMenu: View {
    enum Style {
        /// Bordered capsule with a globe icon and the language name — the
        /// original look, used on hero surfaces like the Auth header.
        case pill
        /// Plain text (current language name) with a small up/down chevron,
        /// no capsule or border — for use as the trailing element of a
        /// settings row that already supplies its own icon and title.
        case inline
    }

    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    var onHero = false
    var style: Style = .pill

    var body: some View {
        Menu {
            Picker("Language", selection: $languageCode) {
                Label("English", systemImage: "globe").tag("en")
                Label("Українська", systemImage: "globe").tag("uk")
                Label("Русский", systemImage: "globe").tag("ru")
            }
        } label: {
            switch style {
            case .pill:
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
            case .inline:
                HStack(spacing: 4) {
                    Text(AppLanguage(rawValue: languageCode)?.fullTitle ?? AppLanguage.english.fullTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(GymTheme.textSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .accessibilityLabel(gymText("Language", "Мова", languageCode: languageCode))
        .accessibilityValue(languageCode == "uk" ? "Українська" : languageCode == "ru" ? "Русский" : "English")
    }
}
