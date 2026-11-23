import Foundation
import SwiftUI
import WatchKit

enum WatchResultState: Equatable {
    case sending
    case saved
    case deferred
}

enum WatchPhase: Equatable {
    case start
    case workout
    case summary
    case result(WatchResultState)
}

/// Coordinates the context, the running workout, HealthKit and the outbox.
@MainActor
final class WatchAppModel: ObservableObject {
    static let shared = WatchAppModel()

    @Published private(set) var context: WatchContextMessage?
    @Published private(set) var workout: WatchActiveWorkout?
    @Published private(set) var outbox: [WatchOutboxItem] = []
    @Published var phase: WatchPhase = .start
    @Published var weightStep: Double {
        didSet { UserDefaults.standard.set(weightStep, forKey: Self.weightStepKey) }
    }
    /// One-line status under Pause (for example "Record at least one set before finishing.").
    @Published var pauseStatus: String?
    @Published private(set) var isSaving = false

    let language: String
    let health = WorkoutSessionManager()
    let client = WatchSessionClient()

    private static let weightStepKey = "watch.weightStep.v1"
    private let planStore: PlanStore
    private let activeStore: ActiveWorkoutStore
    private let outboxStore: OutboxStore
    private var launched = false
    private var resultRequestId: String?
    private var restTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    /// The item being finished: it is not flushed until its Health save has settled.
    private var savingRequestId: String?
    private var recoveringHealth = false
    #if DEBUG
    private var debugSeedApplied = false
    #endif

    init(files: WatchFileStore = WatchFileStore(root: WatchFileStore.defaultRoot())) {
        language = WatchText.language(preferredLanguages: Locale.preferredLanguages)
        planStore = PlanStore(files: files)
        activeStore = ActiveWorkoutStore(files: files)
        outboxStore = OutboxStore(files: files)
        let storedStep = UserDefaults.standard.double(forKey: Self.weightStepKey)
        weightStep = WatchCrownSteps.validWeightStep(storedStep)
        context = planStore.context
        outbox = outboxStore.loadAll()
        if let restored = activeStore.load() {
            if WatchOutboxPolicy.isAlreadyFinished(requestId: restored.requestId, outbox: outbox) {
                // Killed between the outbox write and the snapshot delete: the workout is
                // already finished, so finishing it again would resend other bytes.
                activeStore.clear()
            } else {
                workout = restored
                phase = .workout
            }
        }
    }

    // MARK: Text

    func text(_ key: WatchTextKey) -> String { WatchText.string(key, language) }
    func format(_ key: WatchTextKey, _ arguments: CVarArg...) -> String {
        String(format: WatchText.string(key, language), locale: Locale(identifier: language), arguments: arguments)
    }

    // MARK: Lifecycle

    func launch() {
        guard !launched else { return }
        launched = true
        client.onContextBytes = { [weak self] bytes in self?.handleContext(bytes) }
        client.onReplyBytes = { [weak self] bytes in self?.handleReply(bytes) }
        client.onActivated = { [weak self] in self?.flushOutbox() }
        client.activate()
        #if DEBUG
        applyDebugSeed()
        #endif
        scheduleRestEnd()
        Task { await recoverHealthSession() }
    }

    func becameActive() {
        if let workout, WatchWorkoutModel.restRemainingSeconds(workout, nowMillis: Self.nowMillis()) == nil,
           workout.restEndsAtMillis != nil {
            mutate { WatchWorkoutModel.skipRest(&$0) }
        }
        flushOutbox()
    }

    /// Called on relaunch: reattach to the HealthKit session; without one the workout
    /// continues paused and without heart rate (Resume / Finish / Discard).
    func recoverHealthSession() async {
        guard !recoveringHealth else { return }
        recoveringHealth = true
        defer { recoveringHealth = false }
        guard let current = workout else {
            // No workout to attach to (its snapshot is gone): end an orphan session.
            if await health.recover(), workout == nil, !isSaving { health.discard() }
            return
        }
        guard current.heartRateEnabled, !health.isRunning else { return }
        if await health.recover() {
            if let latest = workout, WatchWorkoutModel.isPaused(latest) { health.pause() }
            return
        }
        guard workout?.requestId == current.requestId, !health.isRunning else { return }
        mutate {
            $0.heartRateEnabled = false
            WatchWorkoutModel.pause(&$0, nowMillis: Self.nowMillis())
        }
        pauseStatus = text(.hrOff)
    }

    // MARK: Start

    var bound: WatchBoundContext? { context?.bound }
    var outboxIsFull: Bool { !WatchOutboxPolicy.canStartWorkout(itemCount: outbox.count) }
    var canStart: Bool { bound != nil && !outboxIsFull && workout == nil && !isSaving }

    func startWorkout(mode: WatchWorkoutMode) async {
        guard canStart else { return }
        let heartRateEnabled = await health.requestAuthorization()
        guard canStart, let bound else { return }
        let now = Self.nowMillis()
        guard let started = WatchWorkoutModel.start(
            mode: mode,
            context: bound,
            requestId: WatchSync.makeRequestID(),
            nowMillis: now,
            heartRateEnabled: heartRateEnabled
        ) else { return }
        workout = started
        persist()
        pauseStatus = nil
        phase = .workout
        WKInterfaceDevice.current().play(.start)
        if heartRateEnabled {
            let running = await health.start(requestId: started.requestId, startDate: Self.date(now))
            if !running { mutate { $0.heartRateEnabled = false } }
        }
    }

    func cycleWeightStep() {
        weightStep = WatchCrownSteps.nextWeightStep(after: weightStep)
    }

    // MARK: Workout

    func selectExercise(_ name: String) {
        mutate { WatchWorkoutModel.selectExercise(&$0, name: name) }
    }

    func logSet(weight: Double, reps: Int) {
        var logged = false
        mutate { logged = WatchWorkoutModel.logSet(&$0, weight: weight, reps: reps, nowMillis: Self.nowMillis()) }
        if logged {
            pauseStatus = nil
            WKInterfaceDevice.current().play(.success)
        }
    }

    func undo() {
        var undone = false
        mutate { undone = WatchWorkoutModel.undo(&$0, nowMillis: Self.nowMillis()) }
        if undone { WKInterfaceDevice.current().play(.retry) }
    }

    func addRest() {
        mutate { WatchWorkoutModel.addRest(&$0, nowMillis: Self.nowMillis()) }
    }

    func skipRest() {
        mutate { WatchWorkoutModel.skipRest(&$0) }
    }

    func pause() {
        guard let workout, !WatchWorkoutModel.isPaused(workout) else { return }
        mutate { WatchWorkoutModel.pause(&$0, nowMillis: Self.nowMillis()) }
        if workout.heartRateEnabled { health.pause() }
        WKInterfaceDevice.current().play(.stop)
    }

    func resume() {
        guard let workout, WatchWorkoutModel.isPaused(workout) else { return }
        mutate { WatchWorkoutModel.resume(&$0, nowMillis: Self.nowMillis()) }
        if workout.heartRateEnabled { health.resume() }
        pauseStatus = nil
        WKInterfaceDevice.current().play(.start)
    }

    /// Finish with zero sets does not navigate; it shows a status line instead.
    func requestFinish() {
        guard let workout else { return }
        guard !workout.sets.isEmpty else {
            pauseStatus = text(.needSet)
            return
        }
        pause()
        phase = .summary
    }

    func backFromSummary() {
        guard workout != nil else { return }
        phase = .workout
    }

    func discardWorkout() {
        guard let current = workout else { return }
        if current.heartRateEnabled { health.discard() }
        restTask?.cancel()
        activeStore.clear()
        workout = nil
        pauseStatus = nil
        phase = .start
        WKInterfaceDevice.current().play(.failure)
    }

    /// Crash-safe finish order: end session and collection → read statistics → write the
    /// outbox item → save to Health → delete the active snapshot → transferUserInfo.
    func saveWorkout() async {
        guard let current = workout, !isSaving, !current.sets.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        phase = .result(.sending)
        let endedAt = Self.nowMillis()
        var stats = WorkoutSessionManager.Statistics()
        if current.heartRateEnabled {
            stats = await health.end(at: Self.date(endedAt))
        }
        func message(_ status: WatchHealthKitStatus) -> WatchWorkoutMessage? {
            WatchWorkoutModel.finish(
                current,
                endedAtMillis: endedAt,
                healthKit: status,
                averageHeartRate: stats.averageHeartRate,
                maximumHeartRate: stats.maximumHeartRate,
                activeKilocalories: stats.activeKilocalories
            )
        }
        let initialStatus: WatchHealthKitStatus = current.heartRateEnabled ? .saved : .off
        guard let finished = message(initialStatus),
              let envelope = try? WatchSyncCodec.encode(finished, nowMillis: Self.nowMillis()) else {
            phase = .summary
            return
        }
        let item = WatchOutboxPolicy.makeItem(
            message: finished,
            envelope: envelope,
            summary: WatchWorkoutModel.summary(finished),
            nowMillis: Self.nowMillis()
        )
        savingRequestId = item.requestId
        do {
            try outboxStore.save(item)
        } catch {
            savingRequestId = nil
            phase = .summary
            return
        }
        outbox.removeAll { $0.requestId == item.requestId }
        outbox.append(item)

        if current.heartRateEnabled {
            let savedToHealth = await health.finishWorkout()
            // Rewritten only while the live item was never sent: other bytes under the
            // same requestId would be a conflict on the phone.
            if !savedToHealth,
               let live = outbox.first(where: { $0.requestId == item.requestId }),
               let failed = message(.failed),
               let data = try? WatchSyncCodec.encode(failed, nowMillis: Self.nowMillis()),
               let rewritten = WatchOutboxPolicy.rewriting(live, envelope: data) {
                store(rewritten)
            }
        }
        savingRequestId = nil

        restTask?.cancel()
        activeStore.clear()
        workout = nil
        pauseStatus = nil
        resultRequestId = finished.requestId
        flushOutbox()
        resultTask?.cancel()
        resultTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self, self.phase == .result(.sending) else { return }
            self.phase = .result(.deferred)
        }
    }

    func closeResult() {
        resultTask?.cancel()
        resultRequestId = nil
        #if DEBUG
        if WatchDebugSeed.isScreen("result-saved") { return }
        #endif
        if workout == nil { phase = .start }
    }

    // MARK: Outbox

    func sendNow(_ requestId: String) {
        guard let index = outbox.firstIndex(where: { $0.requestId == requestId }),
              outbox[index].status == .queued || outbox[index].status == .sent else { return }
        var item = outbox[index]
        item.nextAttemptAtMillis = Self.nowMillis()
        store(item)
        flushOutbox()
    }

    func discardOutboxItem(_ requestId: String) {
        try? outboxStore.delete(requestId: requestId)
        outbox.removeAll { $0.requestId == requestId }
        WKInterfaceDevice.current().play(.failure)
    }

    func flushOutbox() {
        let now = Self.nowMillis()
        var outstanding = client.outstandingRequestIDs()
        if let savingRequestId { outstanding.insert(savingRequestId) }
        for item in outbox where WatchOutboxPolicy.isSendable(item, context: context, nowMillis: now, outstanding: outstanding) {
            if client.transfer(item.envelope) {
                store(WatchOutboxPolicy.markSent(item, nowMillis: now))
                #if DEBUG
                WatchDebugSeed.log("transfer \(item.requestId) bytes=\(item.envelope.count) attempt=\(item.attempts + 1)")
                #endif
            }
        }
        scheduleRetry()
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let pending = outbox.filter { $0.status == .queued || $0.status == .sent }.map(\.nextAttemptAtMillis)
        guard let next = pending.min() else { return }
        let delay = max(1_000, next - Self.nowMillis())
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.flushOutbox()
        }
    }

    private func handleContext(_ bytes: Data) {
        guard let incoming = WatchSyncCodec.decodeContext(bytes) else { return }
        let merged = planStore.apply(incoming)
        context = merged
        #if DEBUG
        WatchDebugSeed.log("context bound=\(merged.bound != nil) account=\(merged.bound?.accountBinding.prefix(8) ?? "-") revision=\(merged.bound?.planRevision ?? 0) plan=\(merged.bound?.plan.count ?? 0) exercises=\(merged.bound?.exercises.count ?? 0)")
        #endif
        let now = Self.nowMillis()
        for item in outbox {
            let next = WatchOutboxPolicy.applyContext(merged, to: item, nowMillis: now)
            if next != item { store(next) }
        }
        #if DEBUG
        applyDebugSeed()
        #endif
        flushOutbox()
    }

    private func handleReply(_ bytes: Data) {
        guard let reply = WatchSyncCodec.decodeReply(bytes) else { return }
        #if DEBUG
        WatchDebugSeed.log("reply \(reply)")
        #endif
        let now = Self.nowMillis()
        for item in outbox {
            switch WatchOutboxPolicy.apply(reply, to: item, nowMillis: now) {
            case .delete:
                try? outboxStore.delete(requestId: item.requestId)
                outbox.removeAll { $0.requestId == item.requestId }
                if item.requestId == resultRequestId, phase == .result(.sending) || phase == .result(.deferred) {
                    resultTask?.cancel()
                    phase = .result(.saved)
                    WKInterfaceDevice.current().play(.success)
                }
            case .update(let next):
                store(next)
                if item.requestId == resultRequestId, phase == .result(.sending) {
                    resultTask?.cancel()
                    phase = .result(.deferred)
                }
            case .ignore:
                break
            }
        }
        scheduleRetry()
    }

    private func store(_ item: WatchOutboxItem) {
        do {
            try outboxStore.save(item)
            replace(item)
        } catch {
            // Keep the previous on-disk state; it is retried on the next flush.
        }
    }

    private func replace(_ item: WatchOutboxItem) {
        if let index = outbox.firstIndex(where: { $0.requestId == item.requestId }) {
            outbox[index] = item
        }
    }

    // MARK: Helpers

    private func mutate(_ change: (inout WatchActiveWorkout) -> Void) {
        guard var next = workout else { return }
        change(&next)
        workout = next
        persist()
        scheduleRestEnd()
    }

    private func persist() {
        guard let workout else { return }
        try? activeStore.save(workout)
    }

    /// Rest end: haptic, "Rest timer done" announcement and back to Working.
    private func scheduleRestEnd() {
        restTask?.cancel()
        guard let workout, let end = workout.restEndsAtMillis, !WatchWorkoutModel.isPaused(workout) else { return }
        let delay = max(0, end - Self.nowMillis())
        restTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            guard !Task.isCancelled, let self, self.workout?.restEndsAtMillis == end else { return }
            WKInterfaceDevice.current().play(.notification)
            AccessibilityNotification.Announcement(self.text(.restDone)).post()
            self.mutate { WatchWorkoutModel.skipRest(&$0) }
        }
    }

    static func nowMillis() -> Int64 { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
    static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1_000).rounded()) }
    static func date(_ millis: Int64) -> Date { Date(timeIntervalSince1970: Double(millis) / 1_000) }
}

#if DEBUG
extension WatchAppModel {
    /// DEBUG-only seeds (`-AWDebugSeed <name>`) for screenshots and the paired-simulator
    /// check. Never compiled into Release.
    fileprivate func applyDebugSeed() {
        guard !debugSeedApplied, let seed = WatchDebugSeed.screen else { return }
        if seed == "finished" || seed == "resend" {
            debugDeliver(resend: seed == "resend")
        } else {
            debugSeedApplied = true
            debugShowScreen(seed)
        }
    }

    /// "finished": a finished workout for the bound account goes through the real outbox.
    /// "resend": the same item (same bytes) is queued again after it was acked.
    private func debugDeliver(resend: Bool) {
        guard let bound else { return }
        debugSeedApplied = true
        let files = WatchFileStore(root: WatchFileStore.defaultRoot())
        let copyName = "debug-last-item.json"
        let now = Self.nowMillis()
        if resend {
            guard let data = files.read(name: copyName, maximumBytes: 256 * 1_024),
                  var item = try? JSONDecoder().decode(WatchOutboxItem.self, from: data),
                  !outbox.contains(where: { $0.requestId == item.requestId }) else { return }
            item.status = .sent
            item.nextAttemptAtMillis = now
            guard (try? outboxStore.save(item)) != nil else { return }
            outbox.append(item)
            WatchDebugSeed.log("seed resend \(item.requestId)")
            flushOutbox()
            return
        }
        let name = bound.plan.first?.name ?? bound.exercises.first ?? "Bench press"
        guard var seeded = WatchWorkoutModel.start(
            mode: .free, context: bound, requestId: WatchSync.makeRequestID(),
            nowMillis: now - 900_000, heartRateEnabled: false
        ) else { return }
        WatchWorkoutModel.selectExercise(&seeded, name: name)
        WatchWorkoutModel.logSet(&seeded, weight: 60, reps: 8, nowMillis: now - 600_000)
        WatchWorkoutModel.logSet(&seeded, weight: 62.5, reps: 6, nowMillis: now - 300_000)
        WatchWorkoutModel.pause(&seeded, nowMillis: now - 60_000)
        guard let finished = WatchWorkoutModel.finish(
            seeded, endedAtMillis: now, healthKit: .off,
            averageHeartRate: nil, maximumHeartRate: nil, activeKilocalories: nil
        ), let envelope = try? WatchSyncCodec.encode(finished, nowMillis: now) else { return }
        let item = WatchOutboxPolicy.makeItem(
            message: finished, envelope: envelope,
            summary: WatchWorkoutModel.summary(finished), nowMillis: now
        )
        guard (try? outboxStore.save(item)) != nil else { return }
        if let copy = try? JSONEncoder().encode(item) { try? files.write(copy, name: copyName) }
        outbox.append(item)
        resultRequestId = item.requestId
        phase = .result(.sending)
        WatchDebugSeed.log("seed finished \(item.requestId)")
    }

    /// In-memory state for one screen; nothing is written to the outbox.
    private func debugShowScreen(_ seed: String) {
        let now = Self.nowMillis()
        let names: [String]
        switch language {
        case "ru": names = ["Жим штанги лёжа на наклонной скамье", "Приседания со штангой", "Тяга штанги в наклоне", "Подтягивания"]
        case "uk": names = ["Жим штанги лежачи на похилій лаві", "Присідання зі штангою", "Тяга штанги в нахилі", "Підтягування"]
        default: names = ["Incline barbell bench press", "Barbell back squat", "Bent-over barbell row", "Pull-up"]
        }
        let plan = [
            WatchPlanExercise(name: names[0], restSeconds: 120,
                              sets: [.init(weight: 62.5, reps: 8), .init(weight: 62.5, reps: 8), .init(weight: 65, reps: 6)]),
            WatchPlanExercise(name: names[1], restSeconds: 90, sets: [.init(weight: 100, reps: 5), .init(weight: 100, reps: 5)])
        ]
        let seedBound = WatchBoundContext(
            accountBinding: String(repeating: "a", count: 64), language: language,
            planRevision: 1, plan: plan, exercises: names
        )
        if bound == nil { context = WatchContextMessage(sentAtMillis: now, bound: seedBound) }
        guard var seeded = WatchWorkoutModel.start(
            mode: .plan, context: seedBound, requestId: WatchSync.makeRequestID(),
            nowMillis: now - 754_000, heartRateEnabled: false
        ) else { return }
        WatchWorkoutModel.logSet(&seeded, weight: 62.5, reps: 8, nowMillis: now - 600_000)
        WatchWorkoutModel.logSet(&seeded, weight: 62.5, reps: 8, nowMillis: now - 300_000)
        WatchWorkoutModel.skipRest(&seeded)
        switch seed {
        case "dashboard", "set-entry", "picker":
            workout = seeded
            phase = .workout
        case "rest":
            WatchWorkoutModel.logSet(&seeded, weight: 65, reps: 6, nowMillis: now)
            workout = seeded
            phase = .workout
        case "pause", "discard", "summary":
            WatchWorkoutModel.pause(&seeded, nowMillis: now)
            workout = seeded
            phase = seed == "summary" ? .summary : .workout
        case "result-saved":
            workout = nil
            phase = .result(.saved)
        case "result-deferred":
            workout = nil
            phase = .result(.deferred)
        case "outbox", "outbox-list":
            workout = nil
            phase = .start
            let states: [(WatchOutboxStatus, String?)] = [
                (.queued, nil), (.held, WatchNackReason.foreignAccount.rawValue), (.failed, "invalid")
            ]
            outbox = states.enumerated().map { index, state in
                let ended = now - Int64(index) * 86_400_000
                return WatchOutboxItem(
                    requestId: WatchSync.makeRequestID(), accountBinding: String(repeating: "b", count: 64),
                    envelope: Data(), status: state.0, reason: state.1, attempts: 1,
                    nextAttemptAtMillis: now + 3_600_000, heldProtocolVersion: nil, everSent: true,
                    createdAtMillis: ended,
                    summary: WatchWorkoutSummary(
                        durationSeconds: 3_125, setCount: 14 + index, volumeKilograms: 5_420,
                        averageHeartRate: nil, maximumHeartRate: nil, activeKilocalories: nil, endedAtMillis: ended
                    )
                )
            }
        default:
            break
        }
    }
}
#endif
