import SwiftUI

struct StartView: View {
    @EnvironmentObject private var model: WatchAppModel
    @ObservedObject private var client = WatchAppModel.shared.client

    var body: some View {
        List {
            if let first = plan.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(first.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(model.format(.setsCount, plan.reduce(0) { $0 + $1.sets.count }))
                        .font(.footnote)
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            if model.bound != nil {
                if !plan.isEmpty {
                    Button(model.text(.startPlan)) { Task { await model.startWorkout(mode: .plan) } }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowBackground(Color.clear)
                        .disabled(!model.canStart)
                    Button(model.text(.freeWorkout)) { Task { await model.startWorkout(mode: .free) } }
                        .buttonStyle(TonalButtonStyle())
                        .listRowBackground(Color.clear)
                        .disabled(!model.canStart)
                } else {
                    Button(model.text(.freeWorkout)) { Task { await model.startWorkout(mode: .free) } }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowBackground(Color.clear)
                        .disabled(!model.canStart)
                }
            }
            if !model.outbox.isEmpty {
                NavigationLink {
                    OutboxView()
                } label: {
                    Text(model.format(.unsentCount, model.outbox.count))
                        .font(.body)
                }
            }
            Button {
                model.cycleWeightStep()
            } label: {
                HStack {
                    Text(model.text(.weightStep))
                    Spacer(minLength: 4)
                    Text(WatchText.weightKg(model.weightStep, model.language))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.accent)
                }
            }
            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.textSecondary)
                    .lineLimit(3)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(model.text(.appTitle))
    }

    private var plan: [WatchPlanExercise] { model.bound?.plan ?? [] }

    private var status: String? {
        if model.bound == nil { return model.text(.openPhoneSignIn) }
        if model.needsWatchUpdate { return model.text(.updateWatch) }
        if model.outboxIsFull { return model.text(.outboxFull) }
        if model.outbox.contains(where: { $0.status == .queued || $0.status == .sent }) {
            return client.isReachable ? model.text(.sendLater) : model.text(.phoneOff) + ". " + model.text(.sendLater)
        }
        // Linked without a plan: the same phone line Wear OS shows in this state.
        if plan.isEmpty { return model.text(.openPhone) }
        return nil
    }
}
