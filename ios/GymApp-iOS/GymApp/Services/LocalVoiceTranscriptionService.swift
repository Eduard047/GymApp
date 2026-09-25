import AVFoundation
import Foundation
import Speech

enum VoiceTranscriptionError: LocalizedError, Equatable, Sendable {
    case unavailable
    case permissionDenied
    case unsupportedLanguage
    case audioFailure
    case recognitionFailure

    var errorDescription: String? {
        localizedDescription(languageCode: AppLanguage.english.rawValue)
    }

    func localizedDescription(languageCode: String) -> String {
        switch languageCode {
        case AppLanguage.ukrainian.rawValue:
            switch self {
            case .unavailable: "Розпізнавання мовлення на пристрої недоступне. Введи тренування текстом."
            case .permissionDenied: "Потрібен доступ до мікрофона й розпізнавання мовлення."
            case .unsupportedLanguage: "Для цієї мови немає розпізнавання на пристрої. Введи тренування текстом."
            case .audioFailure: "Не вдалося запустити мікрофон."
            case .recognitionFailure: "Не вдалося розпізнати мовлення. Спробуй ще раз або введи фразу вручну."
            }
        case AppLanguage.russian.rawValue:
            switch self {
            case .unavailable: "Распознавание речи на устройстве недоступно. Введи тренировку текстом."
            case .permissionDenied: "Нужен доступ к микрофону и распознаванию речи."
            case .unsupportedLanguage: "Для этого языка нет распознавания на устройстве. Введи тренировку текстом."
            case .audioFailure: "Не удалось запустить микрофон."
            case .recognitionFailure: "Не удалось распознать речь. Попробуй ещё раз или введи фразу вручную."
            }
        default:
            switch self {
            case .unavailable: "On-device speech recognition is unavailable. Type the workout instead."
            case .permissionDenied: "Microphone and speech recognition permission are required."
            case .unsupportedLanguage: "On-device recognition isn't available for this language. Type the workout instead."
            case .audioFailure: "The microphone could not be started."
            case .recognitionFailure: "Speech could not be recognized. Try again or enter the phrase manually."
            }
        }
    }
}

enum VoiceTranscriptionAvailability: Equatable, Sendable {
    case available
    case unavailable(VoiceTranscriptionError)
}

enum VoiceTranscriptionEvent: Equatable, Sendable {
    case finished
    case failed(VoiceTranscriptionError)
}

@MainActor
protocol VoiceTranscriptionScheduler: AnyObject {
    func sleep(for duration: Duration) async throws
}

@MainActor
final class TaskVoiceTranscriptionScheduler: VoiceTranscriptionScheduler {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

@MainActor
protocol VoiceTranscriptionService: AnyObject {
    /// Checked before the microphone button is shown; never prompts for permission.
    func availability(languageCode: String) -> VoiceTranscriptionAvailability
    func start(
        languageCode: String,
        onPartialResult: @escaping (String) -> Void,
        onEvent: @escaping (VoiceTranscriptionEvent) -> Void
    ) async throws
    func stop()
}

@MainActor
extension VoiceTranscriptionService {
    func start(languageCode: String, onPartialResult: @escaping (String) -> Void) async throws {
        try await start(languageCode: languageCode, onPartialResult: onPartialResult) { _ in }
    }
}

@MainActor
final class LocalVoiceTranscriptionService: VoiceTranscriptionService {
    private let audioEngine = AVAudioEngine()
    private let scheduler: any VoiceTranscriptionScheduler
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var sessionID = UUID()
    private var stopTask: Task<Void, Never>?

    init(scheduler: any VoiceTranscriptionScheduler) {
        self.scheduler = scheduler
    }

    convenience init() {
        self.init(scheduler: TaskVoiceTranscriptionScheduler())
    }

    func availability(languageCode: String) -> VoiceTranscriptionAvailability {
        guard let locale = locale(for: languageCode),
              let recognizer = SFSpeechRecognizer(locale: locale) else {
            return .unavailable(.unavailable)
        }
        guard recognizer.supportsOnDeviceRecognition else { return .unavailable(.unsupportedLanguage) }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted: return .unavailable(.permissionDenied)
        default: break
        }
        if AVAudioApplication.shared.recordPermission == .denied { return .unavailable(.permissionDenied) }
        return .available
    }

    func start(
        languageCode: String,
        onPartialResult: @escaping (String) -> Void,
        onEvent: @escaping (VoiceTranscriptionEvent) -> Void
    ) async throws {
        stop()
        let currentSession = UUID()
        sessionID = currentSession

        guard let locale = locale(for: languageCode),
              let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw VoiceTranscriptionError.unavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw VoiceTranscriptionError.unsupportedLanguage
        }

        let speechStatus = await requestSpeechAuthorization()
        guard sessionID == currentSession else { throw CancellationError() }
        guard speechStatus == .authorized else {
            throw VoiceTranscriptionError.permissionDenied
        }

        let microphoneGranted = await AVAudioApplication.requestRecordPermission()
        guard sessionID == currentSession else { throw CancellationError() }
        guard microphoneGranted else {
            throw VoiceTranscriptionError.permissionDenied
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        // Sentence punctuation lets several dictated exercises split into blocks.
        request.addsPunctuation = true
        self.recognizer = recognizer
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            stop()
            throw VoiceTranscriptionError.audioFailure
        }

        do {
            inputNode.removeTap(onBus: 0)
            // Capture this request, rather than reading the mutable property, so an
            // old audio callback can never append buffers to a newer recognition task.
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.sessionID == currentSession else { return }
                    if let result {
                        onPartialResult(result.bestTranscription.formattedString)
                        if result.isFinal {
                            onEvent(.finished)
                            self.stop()
                            return
                        }
                    }
                    if error != nil {
                        onEvent(.failed(.recognitionFailure))
                        self.stop()
                    }
                }
            }

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            guard sessionID == currentSession else { throw CancellationError() }
            audioEngine.prepare()
            try audioEngine.start()
        } catch is CancellationError {
            stop()
            throw CancellationError()
        } catch {
            stop()
            throw VoiceTranscriptionError.audioFailure
        }

        let scheduler = self.scheduler
        stopTask = Task { [weak self, scheduler] in
            do {
                try await scheduler.sleep(for: .seconds(60))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.sessionID == currentSession else { return }
                onEvent(.finished)
                self.stop()
            }
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        sessionID = UUID()
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func locale(for languageCode: String) -> Locale? {
        VoiceWorkoutDraftParser.localeIdentifiers[languageCode].map(Locale.init(identifier:))
    }

    deinit {
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}

#if DEBUG
enum VoiceWorkoutDebugFixture: String, CaseIterable, Sendable {
    case bench
    case squat
    case combined
    case unknown
    case ambiguous
    case missing
    case permissionDenied
    case unavailable
    case unsupportedLanguage
    case audioFailure
    case recognitionFailure

    static func fromLaunchArguments(_ arguments: [String]) -> Self? {
        guard let raw = arguments.first(where: { $0.hasPrefix("--gymapp-voice-fixture=") }) else { return nil }
        return Self(rawValue: String(raw.dropFirst("--gymapp-voice-fixture=".count)))
    }
}

@MainActor
final class DebugVoiceTranscriptionService: VoiceTranscriptionService {
    let fixture: VoiceWorkoutDebugFixture
    private let scheduler: any VoiceTranscriptionScheduler
    private var sessionID = UUID()

    init(fixture: VoiceWorkoutDebugFixture, scheduler: any VoiceTranscriptionScheduler) {
        self.fixture = fixture
        self.scheduler = scheduler
    }

    func availability(languageCode: String) -> VoiceTranscriptionAvailability {
        switch fixture {
        case .unavailable: .unavailable(.unavailable)
        case .unsupportedLanguage: .unavailable(.unsupportedLanguage)
        default: .available
        }
    }

    convenience init(fixture: VoiceWorkoutDebugFixture) {
        self.init(fixture: fixture, scheduler: TaskVoiceTranscriptionScheduler())
    }

    func start(
        languageCode: String,
        onPartialResult: @escaping (String) -> Void,
        onEvent: @escaping (VoiceTranscriptionEvent) -> Void
    ) async throws {
        stop()
        let currentSession = UUID()
        sessionID = currentSession
        switch fixture {
        case .permissionDenied: throw VoiceTranscriptionError.permissionDenied
        case .unavailable: throw VoiceTranscriptionError.unavailable
        case .unsupportedLanguage: throw VoiceTranscriptionError.unsupportedLanguage
        case .audioFailure: throw VoiceTranscriptionError.audioFailure
        case .recognitionFailure:
            onEvent(.failed(.recognitionFailure))
            return
        default:
            onPartialResult(fixture.transcript(languageCode: languageCode))
        }
        do {
            try await scheduler.sleep(for: .seconds(60))
        } catch {
            throw CancellationError()
        }
        guard sessionID == currentSession else { throw CancellationError() }
        onEvent(.finished)
    }

    func stop() {
        sessionID = UUID()
    }
}

private extension VoiceWorkoutDebugFixture {
    func transcript(languageCode: String) -> String {
        switch self {
        case .bench:
            switch languageCode {
            case AppLanguage.russian.rawValue: "Жим лёжа, 3 подхода по 10 повторений, 80 килограмм"
            case AppLanguage.ukrainian.rawValue: "Жим лежачи, 3 підходи по 10 повторень, 80 кілограмів"
            default: "Bench press, 3 sets of 10 reps, 80 kilograms"
            }
        case .squat:
            switch languageCode {
            case AppLanguage.russian.rawValue: "Присед: 60 на 12, 80 на 10, 100 на 8"
            case AppLanguage.ukrainian.rawValue: "Присідання: 60 на 12, 80 на 10, 100 на 8"
            default: "Squat: 60 for 12, 80 for 10, 100 for 8"
            }
        case .combined:
            switch languageCode {
            case AppLanguage.russian.rawValue: "Жим лёжа 3 подхода по 10 повторений 80 килограмм потом присед 60 на 12 80 на 10 100 на 8"
            case AppLanguage.ukrainian.rawValue: "Жим лежачи 3 підходи по 10 повторень 80 кілограмів потім присідання 60 на 12 80 на 10 100 на 8"
            default: "Bench press 3 sets of 10 reps 80 kilograms then squat 60 for 12 80 for 10 100 for 8"
            }
        case .unknown: "Mystery lift, 3 sets of 10 reps, 40 kilograms"
        case .ambiguous: "Press, 3 sets of 10 reps, 40 kilograms"
        case .missing: "Bench press, 3 sets"
        case .permissionDenied, .unavailable, .unsupportedLanguage, .audioFailure, .recognitionFailure:
            ""
        }
    }
}

@MainActor
func makeVoiceTranscriptionService(arguments: [String] = ProcessInfo.processInfo.arguments) -> any VoiceTranscriptionService {
    if let fixture = VoiceWorkoutDebugFixture.fromLaunchArguments(arguments) {
        return DebugVoiceTranscriptionService(fixture: fixture)
    }
    return LocalVoiceTranscriptionService()
}
#else
@MainActor
func makeVoiceTranscriptionService(arguments: [String] = []) -> any VoiceTranscriptionService {
    LocalVoiceTranscriptionService()
}
#endif
