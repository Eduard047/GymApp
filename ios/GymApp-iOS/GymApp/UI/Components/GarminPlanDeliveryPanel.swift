import SwiftUI

@MainActor
struct GarminPlanDeliveryPanel: View {
    @ObservedObject var phone: GarminPhoneSyncService
    @ObservedObject var cloud: GarminCloudService
    let isCloudAccount: Bool
    let isEmpty: Bool
    let sendPhone: (String) -> Void
    let sendCloud: () -> Void
    @State private var selected = ""

    private struct Destination: Identifiable {
        let id: String
        let name: String
    }

    private var destinations: [Destination] {
        var values = phone.devices.map {
            Destination(id: "phone:" + $0.id, name: $0.name + " · iPhone")
        }
        if isCloudAccount, let binding = cloud.selectedDevice {
            let name = cloud.availableDevices.first(where: { $0.id == binding.deviceID })?.displayName ?? "Garmin"
            values.append(Destination(id: "cloud:" + binding.deviceID, name: name + " · " +
                gymText("Cloud", "Хмара", "Облако", languageCode: gymCurrentLanguageCode())))
        }
        return values
    }

    private var ids: [String] { destinations.map(\.id) }

    /// Lite watches (96 KiB tier) record free workouts only; plans never go to them.
    private var selectedIsLite: Bool {
        guard selected.hasPrefix("phone:") else { return false }
        let id = String(selected.dropFirst(6))
        return phone.devices.first(where: { $0.id == id })?.lite == true
    }

    var body: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 10) {
                if destinations.count > 1 {
                    Picker(gymText("Watch", "Годинник", "Часы", languageCode: gymCurrentLanguageCode()), selection: $selected) {
                        Text(gymText("Choose a watch", "Вибери годинник", "Выбери часы", languageCode: gymCurrentLanguageCode())).tag("")
                        ForEach(destinations) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                } else if let destination = destinations.first {
                    Text(destination.name).font(.subheadline).foregroundStyle(GymTheme.textSecondary)
                }
                Button {
                    if selected.hasPrefix("phone:") { sendPhone(String(selected.dropFirst(6))) }
                    else if selected.hasPrefix("cloud:") { sendCloud() }
                } label: {
                    Label(gymText("Sync plan to Garmin", "Синхронізувати план із Garmin", "Синхронизировать план с Garmin",
                        languageCode: gymCurrentLanguageCode()), systemImage: "applewatch.radiowaves.left.and.right")
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .disabled(isEmpty || cloud.isWorking || !ids.contains(selected) || selectedIsLite)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if cloud.isWorking { ProgressView() }
            }
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: ids) { _, _ in reconcileSelection() }
    }

    private var message: String {
        if destinations.isEmpty {
            return gymText("Connect a Garmin watch in Profile → Your watch before syncing a plan.",
                "Підключи годинник Garmin у Профілі → Твій годинник перед синхронізацією плану.",
                "Подключи часы Garmin в Профиле → Твои часы перед синхронизацией плана.", languageCode: gymCurrentLanguageCode())
        }
        if selectedIsLite { return GarminPhoneSyncProtocol.liteWatchMessage(languageCode: gymCurrentLanguageCode()) }
        if selected.hasPrefix("phone:"), let status = phone.planDeliveryMessages[String(selected.dropFirst(6))] { return status }
        return gymText("The current edited plan is sent to the selected watch. No workout is saved or started.",
            "Поточний відредагований план буде надіслано на вибраний годинник. Тренування не буде збережено чи розпочато.",
            "Текущий отредактированный план будет отправлен на выбранные часы. Тренировка не будет сохранена или начата.", languageCode: gymCurrentLanguageCode())
    }

    private func reconcileSelection() {
        if !ids.contains(selected) { selected = ids.count == 1 ? ids[0] : "" }
    }
}
