import SwiftUI

/// Unsent workouts: status per item, Send now, Discard (with the confirmation sheet).
struct OutboxView: View {
    @EnvironmentObject private var model: WatchAppModel

    var body: some View {
        List {
            ForEach(model.outbox, id: \.requestId) { item in
                NavigationLink {
                    OutboxItemView(requestId: item.requestId)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateText(item.summary.endedAtMillis))
                            .font(.body)
                        Text(model.format(.setsCount, item.summary.setCount))
                            .font(.footnote)
                            .foregroundStyle(WatchTheme.textSecondary)
                        Text(statusText(item))
                            .font(.footnote)
                            .foregroundStyle(item.status == .failed ? WatchTheme.destructive : WatchTheme.textSecondary)
                            .lineLimit(3)
                    }
                }
            }
        }
        .navigationTitle(model.text(.queuedTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dateText(_ millis: Int64) -> String {
        WatchAppModel.date(millis).formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: model.language))
        )
    }

    private func statusText(_ item: WatchOutboxItem) -> String {
        switch item.status {
        case .failed: return model.text(.notAccepted)
        case .held: return item.reason == WatchNackReason.foreignAccount.rawValue ? model.text(.sameAccount) : model.text(.openPhone)
        case .queued, .sent: return model.text(.sendLater)
        }
    }
}

struct OutboxItemView: View {
    @EnvironmentObject private var model: WatchAppModel
    @Environment(\.dismiss) private var dismiss
    let requestId: String
    @State private var confirmDiscard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let item {
                    Text(WatchCrownSteps.formatDuration(seconds: item.summary.durationSeconds))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(model.format(.setsCount, item.summary.setCount))
                        .font(.footnote)
                        .foregroundStyle(WatchTheme.textSecondary)
                    if item.status == .queued || item.status == .sent {
                        Button(model.text(.sendNow)) { model.sendNow(requestId) }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Button {
                        confirmDiscard = true
                    } label: {
                        Text(model.text(.discard)).multilineTextAlignment(.center)
                    }
                    .buttonStyle(TonalButtonStyle(fill: WatchTheme.destructiveTonal, foreground: WatchTheme.destructive))
                }
            }
            .scenePadding(.horizontal)
        }
        .sheet(isPresented: $confirmDiscard) {
            DiscardConfirmView {
                model.discardOutboxItem(requestId)
                dismiss()
            }
        }
    }

    private var item: WatchOutboxItem? { model.outbox.first { $0.requestId == requestId } }
}
