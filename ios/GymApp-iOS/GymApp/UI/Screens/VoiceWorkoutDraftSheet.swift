import SwiftUI

@MainActor
struct VoiceWorkoutDraftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var transcript = ""
    @State private var parsed = VoiceWorkoutDraft()
    @State private var isListening = false
    @State private var errorMessage: String?
    @State private var availability: VoiceTranscriptionAvailability = .available
    /// Raw field text per set, so partially typed values ("8", "82,") are never reformatted.
    @State private var weightTexts: [UUID: String] = [:]
    @State private var repsTexts: [UUID: String] = [:]
    @State private var showingReplaceConfirmation = false
    @State private var listeningTask: Task<Void, Never>?
    @State private var listeningGeneration = UUID()

    let exercises: [Exercise]
    let existingDrafts: [WorkoutEditorExerciseDraft]
    let transcriptionService: any VoiceTranscriptionService
    let languageCode: String
    let onApply: ([WorkoutEditorExerciseDraft], VoiceWorkoutApplyMode) -> Void

    private static let unresolvedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var body: some View {
        NavigationStack {
            Form {
                dictationSection

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("voiceWorkout.error")
                    }
                }

                if !parsed.blocks.isEmpty {
                    Section {
                        ForEach(parsed.blocks) { block in
                            blockEditor(block)
                        }
                    } header: {
                        Text(text("Preview", "Попередній перегляд", "Предпросмотр"))
                            .accessibilityIdentifier("voiceWorkout.preview")
                    }
                }

                if !notices.isEmpty {
                    Section {
                        ForEach(notices, id: \.self) { notice in
                            Label(notice, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .accessibilityIdentifier("voiceWorkout.notices")
                }

                applySection
            }
            .navigationTitle(text("Voice workout", "Голосове тренування", "Голосовая тренировка"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("Cancel", "Скасувати", "Отмена")) {
                        stopListening()
                        dismiss()
                    }
                    .accessibilityIdentifier("voiceWorkout.cancel")
                }
            }
            .confirmationDialog(
                text("Replace current plan?", "Замінити поточний план?", "Заменить текущий план?"),
                isPresented: $showingReplaceConfirmation,
                titleVisibility: .visible
            ) {
                Button(text("Replace plan", "Замінити план", "Заменить план"), role: .destructive) {
                    apply(.replace)
                }
                .accessibilityIdentifier("voiceWorkout.replace.confirm")
                Button(text("Cancel", "Скасувати", "Отмена"), role: .cancel) {}
            } message: {
                Text(text(
                    "All exercises and sets will be removed.",
                    "Усі вправи й підходи буде видалено.",
                    "Все упражнения и подходы будут удалены."
                ))
            }
            .onAppear {
                availability = transcriptionService.availability(languageCode: languageCode)
            }
            .onDisappear {
                stopListening()
            }
        }
    }

    // MARK: Sections

    private var dictationSection: some View {
        Section {
            TextField(
                text("Describe exercises, sets, reps and weight", "Опиши вправи, підходи, повторення і вагу", "Опиши упражнения, подходы, повторы и вес"),
                text: $transcript,
                axis: .vertical
            )
            .lineLimit(3 ... 8)
            .accessibilityIdentifier("voiceWorkout.transcript")
            .onChange(of: transcript) { _, value in
                let bounded = VoiceWorkoutDraftParser.truncatedUTF8(value)
                if bounded != value {
                    transcript = bounded
                    return
                }
                reparse(value)
            }

            switch availability {
            case .available:
                Button {
                    if isListening { stopListening() } else { startListening() }
                } label: {
                    Label(
                        isListening
                            ? text("Stop listening", "Зупинити прослуховування", "Остановить прослушивание")
                            : text("Speak workout", "Диктувати тренування", "Диктовать тренировку"),
                        systemImage: isListening ? "stop.circle.fill" : "mic.fill"
                    )
                }
                .accessibilityIdentifier("voiceWorkout.speakButton")
                .accessibilityValue(
                    isListening
                        ? text("Listening", "Слухаю", "Слушаю")
                        : text("Ready", "Готово", "Готово")
                )
                .accessibilityHint(text(
                    "Starts or stops local on-device speech recognition",
                    "Запускає або зупиняє локальне розпізнавання мовлення на пристрої",
                    "Запускает или останавливает локальное распознавание речи на устройстве"
                ))

                if isListening {
                    HStack(spacing: 8) {
                        SwiftUI.ProgressView()
                        Text(text("Listening…", "Слухаю…", "Слушаю…"))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("voiceWorkout.listening")
                }
            case let .unavailable(reason):
                Label(reason.localizedDescription(languageCode: languageCode), systemImage: "mic.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("voiceWorkout.unavailable")
            }
        } header: {
            Text(text("Dictation", "Диктування", "Диктовка"))
        } footer: {
            Text(text(
                "Audio and transcript stay on this device and are not saved.",
                "Аудіо й транскрипт залишаються на цьому пристрої та не зберігаються.",
                "Аудио и транскрипт остаются на этом устройстве и не сохраняются."
            ))
            .accessibilityIdentifier("voiceWorkout.privacyNotice")
        }
    }

    @ViewBuilder
    private var applySection: some View {
        if !existingDrafts.isEmpty {
            Section {
                Button(text("Add to current plan", "Додати до поточного плану", "Добавить к текущему плану")) {
                    apply(.add)
                }
                .disabled(!canApply || !canAdd)
                .accessibilityIdentifier("voiceWorkout.apply.add")
                Button(text("Replace current plan", "Замінити поточний план", "Заменить текущий план"), role: .destructive) {
                    showingReplaceConfirmation = true
                }
                .disabled(!canApply)
                .accessibilityIdentifier("voiceWorkout.apply.replace")
            } header: {
                Text(text("The editor already has exercises", "У редакторі вже є вправи", "В редакторе уже есть упражнения"))
            } footer: {
                if !canAdd {
                    Text(text(
                        "A workout can have up to 100 exercises.",
                        "У тренуванні може бути не більше 100 вправ.",
                        "В тренировке может быть не больше 100 упражнений."
                    ))
                }
            }
        } else {
            Section {
                Button(text("Apply to plan", "Застосувати до плану", "Применить к плану")) {
                    apply(.replace)
                }
                .disabled(!canApply)
                .accessibilityIdentifier("voiceWorkout.apply.replace")
            }
        }
    }

    private func blockEditor(_ block: VoiceWorkoutExerciseBlock) -> some View {
        let blockID = block.id
        return VStack(alignment: .leading, spacing: 8) {
            if !block.spokenName.isEmpty {
                Text(verbatim: "“\(block.spokenName)”")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Picker(
                text("Exercise", "Вправа", "Упражнение"),
                selection: exerciseSelectionBinding(blockID: blockID)
            ) {
                Text(text("Choose exercise", "Виберіть вправу", "Выберите упражнение"))
                    .tag(Self.unresolvedExerciseID)
                ForEach(pickerExercises(for: block)) { exercise in
                    Text(gymExerciseName(exercise, languageCode: languageCode))
                        .tag(exercise.id)
                }
            }
            .accessibilityIdentifier("voiceWorkout.preview.\(blockID.uuidString).exercise")

            ForEach(block.sets) { set in
                HStack(spacing: 8) {
                    TextField(text("Weight", "Вага", "Вес"), text: weightBinding(blockID: blockID, setID: set.id))
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("voiceWorkout.preview.\(blockID.uuidString).set.\(set.id.uuidString).weight")
                    Text(text("kg ×", "кг ×", "кг ×"))
                        .foregroundStyle(.secondary)
                    TextField(text("Reps", "Повтори", "Повторы"), text: repsBinding(blockID: blockID, setID: set.id))
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("voiceWorkout.preview.\(blockID.uuidString).set.\(set.id.uuidString).reps")
                    Button(role: .destructive) {
                        removeSet(blockID: blockID, setID: set.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(text("Remove set", "Видалити підхід", "Удалить подход"))
                }
            }

            if let issue = block.issue {
                Label(issueText(issue, block: block), systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("voiceWorkout.preview.\(blockID.uuidString).issue")
            }

            HStack {
                Button {
                    addSet(blockID: blockID)
                } label: {
                    Label(text("Add set", "Додати підхід", "Добавить подход"), systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(block.sets.count >= VoiceWorkoutDraftParser.maximumSetsPerBlock)
                .accessibilityIdentifier("voiceWorkout.preview.\(blockID.uuidString).addSet")
                Spacer()
                Button(role: .destructive) {
                    removeBlock(blockID: blockID)
                } label: {
                    Label(text("Remove exercise", "Видалити вправу", "Удалить упражнение"), systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("voiceWorkout.preview.\(blockID.uuidString).remove")
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("voiceWorkout.preview.\(blockID.uuidString)")
    }

    // MARK: State

    private var canAdd: Bool {
        existingDrafts.count + parsed.blocks.count <= VoiceWorkoutDraftParser.maximumBlocks
    }

    private var canApply: Bool {
        !isListening && !parsed.blocks.isEmpty && parsed.blocks.allSatisfy(\.isValid)
    }

    /// Transcript-wide notices; per-block problems are shown live under each block.
    private var notices: [String] {
        parsed.diagnostics.compactMap { diagnostic in
            switch diagnostic.kind {
            case .transcriptTooLong:
                text("The dictated text is too long.", "Надиктований текст задовгий.", "Надиктованный текст слишком длинный.")
            case .limitsExceeded:
                text(
                    "Only the first 100 exercises and 100 sets per exercise were kept.",
                    "Збережено лише перші 100 вправ і 100 підходів на вправу.",
                    "Сохранены только первые 100 упражнений и 100 подходов на упражнение."
                )
            default:
                nil
            }
        }
        .reduce(into: [String]()) { result, notice in
            if !result.contains(notice) { result.append(notice) }
        }
    }

    private func issueText(_ issue: VoiceWorkoutBlockIssue, block: VoiceWorkoutExerciseBlock) -> String {
        switch issue {
        case .chooseExercise:
            if case .ambiguous = block.matching {
                return text("Several exercises match. Choose one.", "Підходить кілька вправ. Вибери одну.", "Подходит несколько упражнений. Выбери одно.")
            }
            return text("Choose an exercise from the list.", "Вибери вправу зі списку.", "Выбери упражнение из списка.")
        case .fixSets:
            return text("Add a valid weight and repetition count.", "Додай правильні вагу й кількість повторень.", "Добавь правильные вес и количество повторений.")
        }
    }

    private func pickerExercises(for block: VoiceWorkoutExerciseBlock) -> [Exercise] {
        guard case let .ambiguous(candidates) = block.matching else { return exercises }
        let candidateIDs = Set(candidates.map(\.id))
        return exercises.filter { candidateIDs.contains($0.id) } + exercises.filter { !candidateIDs.contains($0.id) }
    }

    private func reparse(_ value: String) {
        weightTexts.removeAll()
        repsTexts.removeAll()
        parsed = value.isEmpty ? VoiceWorkoutDraft() : VoiceWorkoutDraftParser.parse(transcript: value, exercises: exercises)
    }

    private func exerciseSelectionBinding(blockID: UUID) -> Binding<UUID> {
        Binding(
            get: { parsed.blocks.first(where: { $0.id == blockID })?.exerciseID ?? Self.unresolvedExerciseID },
            set: { selectExercise($0, for: blockID) }
        )
    }

    private func selectExercise(_ exerciseID: UUID, for blockID: UUID) {
        guard let index = parsed.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        guard exerciseID != Self.unresolvedExerciseID,
              let exercise = exercises.first(where: { $0.id == exerciseID }) else {
            parsed.blocks[index].exerciseID = nil
            parsed.blocks[index].catalogKey = nil
            return
        }
        parsed.blocks[index].exerciseID = exercise.id
        parsed.blocks[index].catalogKey = exercise.catalogKey
    }

    private func weightBinding(blockID: UUID, setID: UUID) -> Binding<String> {
        Binding(
            get: { weightTexts[setID] ?? VoiceWorkoutDraftParser.formatWeight(set(blockID: blockID, setID: setID)?.weight) },
            set: { value in
                weightTexts[setID] = value
                updateSet(blockID: blockID, setID: setID) { set in
                    set.weight = VoiceWorkoutDraftParser.parseWeightInput(value)
                }
            }
        )
    }

    private func repsBinding(blockID: UUID, setID: UUID) -> Binding<String> {
        Binding(
            get: { repsTexts[setID] ?? set(blockID: blockID, setID: setID)?.reps.map(String.init) ?? "" },
            set: { value in
                repsTexts[setID] = value
                updateSet(blockID: blockID, setID: setID) { set in
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    // Non-numeric text keeps the set invalid instead of silently clearing it.
                    set.reps = trimmed.isEmpty ? nil : (Int(trimmed) ?? -1)
                }
            }
        )
    }

    private func set(blockID: UUID, setID: UUID) -> VoiceWorkoutSet? {
        parsed.blocks.first(where: { $0.id == blockID })?.sets.first(where: { $0.id == setID })
    }

    private func updateSet(blockID: UUID, setID: UUID, _ update: (inout VoiceWorkoutSet) -> Void) {
        guard let blockIndex = parsed.blocks.firstIndex(where: { $0.id == blockID }),
              let setIndex = parsed.blocks[blockIndex].sets.firstIndex(where: { $0.id == setID }) else { return }
        update(&parsed.blocks[blockIndex].sets[setIndex])
    }

    private func addSet(blockID: UUID) {
        guard let blockIndex = parsed.blocks.firstIndex(where: { $0.id == blockID }),
              parsed.blocks[blockIndex].sets.count < VoiceWorkoutDraftParser.maximumSetsPerBlock else { return }
        // Repeat the last set's values, like the workout editor's add-set action.
        let last = parsed.blocks[blockIndex].sets.last
        parsed.blocks[blockIndex].sets.append(VoiceWorkoutSet(weight: last?.weight, reps: last?.reps))
    }

    private func removeSet(blockID: UUID, setID: UUID) {
        guard let blockIndex = parsed.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        parsed.blocks[blockIndex].sets.removeAll { $0.id == setID }
        weightTexts.removeValue(forKey: setID)
        repsTexts.removeValue(forKey: setID)
    }

    private func removeBlock(blockID: UUID) {
        parsed.blocks.removeAll { $0.id == blockID }
    }

    // MARK: Listening

    private func startListening() {
        stopListening()
        errorMessage = nil
        let generation = UUID()
        listeningGeneration = generation
        isListening = true
        let service = transcriptionService
        listeningTask = Task { @MainActor in
            do {
                try await service.start(
                    languageCode: languageCode,
                    onPartialResult: { value in
                        guard listeningGeneration == generation else { return }
                        transcript = VoiceWorkoutDraftParser.truncatedUTF8(value)
                    },
                    onEvent: { event in
                        guard listeningGeneration == generation else { return }
                        isListening = false
                        if case let .failed(error) = event {
                            errorMessage = error.localizedDescription(languageCode: languageCode)
                        }
                    }
                )
            } catch is CancellationError {
                // Cancellation is expected for manual stop, dismiss, and restart.
            } catch let error as VoiceTranscriptionError {
                guard listeningGeneration == generation else { return }
                isListening = false
                errorMessage = error.localizedDescription(languageCode: languageCode)
                if error == .unsupportedLanguage || error == .unavailable { availability = .unavailable(error) }
            } catch {
                guard listeningGeneration == generation else { return }
                isListening = false
                errorMessage = VoiceTranscriptionError.recognitionFailure.localizedDescription(languageCode: languageCode)
            }
        }
    }

    private func stopListening() {
        listeningGeneration = UUID()
        listeningTask?.cancel()
        listeningTask = nil
        transcriptionService.stop()
        isListening = false
    }

    private func apply(_ mode: VoiceWorkoutApplyMode) {
        guard canApply, mode == .replace || canAdd else { return }
        let newDrafts = parsed.blocks.compactMap { block -> WorkoutEditorExerciseDraft? in
            guard let exerciseID = block.exerciseID else { return nil }
            return WorkoutEditorExerciseDraft(
                exerciseID: exerciseID,
                sets: block.sets.compactMap { set in
                    guard let weight = set.weight, let reps = set.reps else { return nil }
                    return WorkoutEditorSetDraft(weight: weight, reps: reps)
                }
            )
        }
        guard newDrafts.count == parsed.blocks.count, !newDrafts.isEmpty else { return }
        stopListening()
        onApply(newDrafts, mode)
        dismiss()
    }

    private func text(_ english: String, _ ukrainian: String, _ russian: String) -> String {
        gymText(english, ukrainian, russian, languageCode: languageCode)
    }
}

enum VoiceWorkoutApplyMode: Equatable, Sendable {
    case add
    case replace
}
