import SwiftUI
import UIKit

/// Read-only Apple Health import: connect, import now, disconnect. Self-contained and shown on the Watches screen.
struct HealthDataCard: View {
    @ObservedObject var service: HealthKitImportService
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue

    var body: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: gymText("Health data", "Дані про здоров’я", "Данные о здоровье", languageCode: languageCode),
                    supporting: gymText(
                        "Imports workouts and heart rate",
                        "Імпортує тренування й пульс",
                        "Импортирует тренировки и пульс",
                        languageCode: languageCode
                    )
                )

                if !service.isAvailable {
                    GymInlineState(
                        gymText(
                            "Apple Health isn’t available on this phone.",
                            "Apple Health недоступний на цьому телефоні.",
                            "Apple Health недоступен на этом телефоне.",
                            languageCode: languageCode
                        ),
                        systemImage: "heart.slash"
                    )
                } else if service.isConnected {
                    connectedContent
                } else {
                    notConnectedContent
                }

                // Source caption: which watches reach GymApp through Apple Health.
                Text(gymText(
                    "Imports gym workouts and heart rate from Apple Watch and other watches that save to Apple Health.",
                    "Імпортує тренування в залі та пульс з Apple Watch й інших годинників, які зберігають дані в Apple Health.",
                    "Импортирует тренировки в зале и пульс с Apple Watch и других часов, которые сохраняют данные в Apple Health.",
                    languageCode: languageCode
                ))
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Status first, actions after: the failure banner always sits above the buttons.
    @ViewBuilder
    private var failureBanner: some View {
        if let failure = service.failure {
            GymStatusBanner(message: failureText(failure), isError: true)
        }
    }

    @ViewBuilder
    private var notConnectedContent: some View {
        failureBanner

        Button {
            Task { await service.connect() }
        } label: {
            Text(gymText(
                "Connect Apple Health",
                "Підключити Apple Health",
                "Подключить Apple Health",
                languageCode: languageCode
            ))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymPrimaryButtonStyle())

        if service.revokeRequiresSettings {
            settingsHint
        }
    }

    @ViewBuilder
    private var connectedContent: some View {
        Text(summaryText)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GymTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

        failureBanner

        if let summary = service.lastSummary, summary.imported == 0, !service.isImporting {
            Text(gymText(
                "No new gym workouts found. If you expected some, allow access in Settings › Apps › Health › Data Access & Devices.",
                "Нових тренувань у залі не знайдено. Якщо ви очікували їх, дозвольте доступ: Параметри › Програми › Здоров’я › Доступ до даних і пристрої.",
                "Новых тренировок в зале не найдено. Если вы ожидали их, разрешите доступ: Настройки › Приложения › Здоровье › Доступ к данным и устройства.",
                languageCode: languageCode
            ))
            .font(.caption)
            .foregroundStyle(GymTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Button {
            Task { await service.importNow() }
        } label: {
            if service.isImporting {
                HStack(spacing: 9) {
                    ProgressView()
                    Text(gymText("Importing…", "Імпорт…", "Импорт…", languageCode: languageCode))
                }
                .frame(maxWidth: .infinity)
            } else {
                Text(gymText("Import now", "Імпортувати зараз", "Импортировать сейчас", languageCode: languageCode))
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .disabled(service.isImporting)

        Button {
            service.disconnect()
        } label: {
            Text(gymText("Disconnect", "Відключити", "Отключить", languageCode: languageCode))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .disabled(service.isImporting)
    }

    private var settingsHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(gymText(
                "GymApp stopped importing. Apple Health keeps the permission until you remove it in Settings › Apps › Health › Data Access & Devices.",
                "GymApp припинив імпорт. Apple Health зберігає дозвіл, доки ви не приберете його: Параметри › Програми › Здоров’я › Доступ до даних і пристрої.",
                "GymApp перестал импортировать. Apple Health хранит разрешение, пока вы не уберёте его: Настройки › Приложения › Здоровье › Доступ к данным и устройства.",
                languageCode: languageCode
            ))
            .font(.caption)
            .foregroundStyle(GymTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(gymText("Open Settings", "Відкрити Параметри", "Открыть Настройки", languageCode: languageCode))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GymSecondaryButtonStyle())
        }
    }

    private var summaryText: String {
        let count = service.importedTotal
        let countText: String
        switch languageCode {
        case AppLanguage.ukrainian.rawValue:
            countText = "Імпортовано \(count) " + (gymPluralCategory(count, languageCode: languageCode) == .many ? "тренувань" : "тренування")
        case AppLanguage.russian.rawValue:
            switch gymPluralCategory(count, languageCode: languageCode) {
            case .one: countText = "Импортирована \(count) тренировка"
            case .few: countText = "Импортировано \(count) тренировки"
            default: countText = "Импортировано \(count) тренировок"
            }
        default:
            countText = "Imported \(count) " + (count == 1 ? "workout" : "workouts")
        }
        guard let last = service.lastImportAt else { return countText }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = gymAppLocale(languageCode: languageCode)
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: last, relativeTo: Date())
        return countText + " · " + gymText(
            "last import \(relative)",
            "останній імпорт \(relative)",
            "последний импорт \(relative)",
            languageCode: languageCode
        )
    }

    private func failureText(_ failure: HealthImportFailure) -> String {
        switch failure {
        case .authorization, .query, .storage:
            gymText(
                "Couldn’t import. Try again.",
                "Не вдалося імпортувати. Спробуйте ще раз.",
                "Не удалось импортировать. Попробуйте ещё раз.",
                languageCode: languageCode
            )
        }
    }
}
