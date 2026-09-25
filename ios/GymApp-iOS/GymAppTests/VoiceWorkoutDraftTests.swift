import XCTest
@testable import GymApp

#if DEBUG
@MainActor
private final class ImmediateVoiceTranscriptionScheduler: VoiceTranscriptionScheduler {
    func sleep(for duration: Duration) async throws {}
}
#endif

final class VoiceWorkoutDraftTests: XCTestCase {
    private func sharedContract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/voice-workout-v1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func expectedSets(_ value: Any?) throws -> [[Double?]] {
        func pair(_ raw: Any?) throws -> [Double?] {
            let values = try XCTUnwrap(raw as? [Any])
            return values.map { ($0 as? NSNumber)?.doubleValue }
        }
        if let list = value as? [Any] { return try list.map(pair) }
        let repeated = try XCTUnwrap(value as? [String: Any])
        let count = try XCTUnwrap(repeated["repeat"] as? Int)
        return Array(repeating: try pair(repeated["set"]), count: count)
    }

    func testSwiftTablesEqualTheSharedVoiceContract() throws {
        let contract = try sharedContract()
        let limits = try XCTUnwrap(contract["limits"] as? [String: Any])
        XCTAssertEqual(limits["maxTranscriptBytes"] as? Int, VoiceWorkoutDraftParser.maximumTranscriptBytes)
        XCTAssertEqual(limits["maxBlocks"] as? Int, VoiceWorkoutDraftParser.maximumBlocks)
        XCTAssertEqual(limits["maxSetsPerBlock"] as? Int, VoiceWorkoutDraftParser.maximumSetsPerBlock)
        XCTAssertEqual((limits["maxWeight"] as? NSNumber)?.doubleValue, VoiceWorkoutDraftParser.maximumWeight)
        XCTAssertEqual(limits["maxReps"] as? Int, VoiceWorkoutDraftParser.maximumReps)
        XCTAssertEqual(contract["locales"] as? [String: String], VoiceWorkoutDraftParser.localeIdentifiers)
        let rules = try XCTUnwrap(contract["rules"] as? [String: Any])
        XCTAssertEqual(rules["separatorPhrases"] as? [String], VoiceWorkoutDraftParser.separatorPhrases)
        XCTAssertEqual(rules["setWords"] as? [String], VoiceWorkoutDraftParser.setWords)
        XCTAssertEqual(rules["repWords"] as? [String], VoiceWorkoutDraftParser.repWords)
        XCTAssertEqual(rules["weightWords"] as? [String], VoiceWorkoutDraftParser.weightWords)
        XCTAssertEqual(rules["weightPrefixWords"] as? [String], VoiceWorkoutDraftParser.weightPrefixWords)
        XCTAssertEqual(rules["connectorWords"] as? [String], VoiceWorkoutDraftParser.connectorWords)
        XCTAssertEqual(rules["containsMatchMinimumLength"] as? Int, VoiceWorkoutDraftParser.containsMatchMinimumLength)
        XCTAssertEqual(rules["voiceAliases"] as? [String: [String]], VoiceWorkoutDraftParser.voiceAliasesByCatalogKey)
        let numbers = try XCTUnwrap(rules["numberWords"] as? [String: Any])
        XCTAssertEqual(numbers["units"] as? [String: Int], VoiceWorkoutDraftParser.numberUnits)
        XCTAssertEqual(numbers["teens"] as? [String: Int], VoiceWorkoutDraftParser.numberTeens)
        XCTAssertEqual(numbers["tens"] as? [String: Int], VoiceWorkoutDraftParser.numberTens)
        XCTAssertEqual(numbers["hundreds"] as? [String: Int], VoiceWorkoutDraftParser.numberHundreds)
        XCTAssertEqual(numbers["hundredMultipliers"] as? [String], VoiceWorkoutDraftParser.hundredMultipliers)
    }

    func testSharedGoldenCasesThroughTheProductionExerciseAdapter() throws {
        let contract = try sharedContract()
        let fixtureDefinitions = try XCTUnwrap(contract["fixtureExercises"] as? [String: [String: Any]])
        let defaultFixtures = try XCTUnwrap(contract["defaultFixtures"] as? [String])
        let cases = try XCTUnwrap(contract["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 30)

        for testCase in cases {
            let caseID = try XCTUnwrap(testCase["id"] as? String)
            let keys = (testCase["fixtures"] as? [String]) ?? defaultFixtures
            var fixtureKeyByID: [UUID: String] = [:]
            let exercises = try keys.map { key -> Exercise in
                let definition = try XCTUnwrap(fixtureDefinitions[key])
                let id = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(definition["id"] as? String)))
                fixtureKeyByID[id] = key
                return Exercise(id: id, name: try XCTUnwrap(definition["name"] as? String), catalogKey: definition["catalogKey"] as? String)
            }
            let transcript: String
            if let repeated = testCase["transcriptRepeat"] as? [String: Any] {
                transcript = String(repeating: try XCTUnwrap(repeated["text"] as? String), count: try XCTUnwrap(repeated["count"] as? Int))
            } else {
                transcript = try XCTUnwrap(testCase["transcript"] as? String)
            }
            let result = VoiceWorkoutDraftParser.parse(transcript: transcript, exercises: exercises)
            let expectedBlocks = try XCTUnwrap(testCase["blocks"] as? [[String: Any]])
            XCTAssertEqual(result.blocks.count, expectedBlocks.count, caseID)
            for (index, expected) in expectedBlocks.enumerated() where index < result.blocks.count {
                let block = result.blocks[index]
                XCTAssertEqual(block.exerciseID.flatMap { fixtureKeyByID[$0] }, expected["exercise"] as? String, "\(caseID) block \(index)")
                let match: String
                switch block.matching {
                case .resolved: match = "resolved"
                case .unresolved: match = "unresolved"
                case let .ambiguous(candidates):
                    match = "ambiguous"
                    if let expectedCandidates = expected["candidates"] as? [String] {
                        XCTAssertEqual(Set(candidates.compactMap { fixtureKeyByID[$0.id] }), Set(expectedCandidates), caseID)
                    }
                }
                XCTAssertEqual(match, expected["match"] as? String, "\(caseID) block \(index)")
                let actualSets = block.sets.map { [$0.weight, $0.reps.map(Double.init)] }
                XCTAssertEqual(actualSets, try expectedSets(expected["sets"]), "\(caseID) block \(index)")
            }
            let blockIndex = Dictionary(uniqueKeysWithValues: result.blocks.enumerated().map { ($1.id, $0) })
            let diagnostics = result.diagnostics.map { diagnostic in
                diagnostic.blockID.flatMap { blockIndex[$0] }.map { "\(diagnostic.kind.rawValue):\($0)" } ?? diagnostic.kind.rawValue
            }
            XCTAssertEqual(diagnostics, testCase["diagnostics"] as? [String], caseID)
        }
    }

    func testByteTruncationWeightFormattingAndLiveReadiness() {
        let truncated = VoiceWorkoutDraftParser.truncatedUTF8(String(repeating: "ж", count: 5000))
        XCTAssertEqual(truncated.count, 4096)
        XCTAssertLessThanOrEqual(truncated.utf8.count, VoiceWorkoutDraftParser.maximumTranscriptBytes)
        XCTAssertEqual(VoiceWorkoutDraftParser.formatWeight(80), "80")
        XCTAssertEqual(VoiceWorkoutDraftParser.formatWeight(82.5), "82.5")
        XCTAssertEqual(VoiceWorkoutDraftParser.parseWeightInput("82,5"), 82.5)
        XCTAssertNil(VoiceWorkoutDraftParser.parseWeightInput(" "))
        XCTAssertTrue(VoiceWorkoutDraftParser.parseWeightInput("8a")?.isNaN == true)

        let bench = Exercise(name: "Bench Press", catalogKey: "bench_press")
        let tooMany = VoiceWorkoutDraftParser.parse(transcript: "Bench press: 101 sets of 10 reps, 80 kilograms", exercises: [bench])
        XCTAssertEqual(tooMany.blocks.first?.sets.count, 100)
        XCTAssertEqual(tooMany.blocks.first?.isValid, true)
        var unknown = VoiceWorkoutDraftParser.parse(transcript: "Mystery lift 40 for 10", exercises: [bench])
        XCTAssertEqual(unknown.blocks.first?.issue, .chooseExercise)
        unknown.blocks[0].exerciseID = bench.id
        XCTAssertNil(unknown.blocks[0].issue)
    }

    func testLocalizedVoiceErrorsAreAvailableForAllSupportedLanguages() {
        XCTAssertNotEqual(VoiceTranscriptionError.permissionDenied.localizedDescription(languageCode: "en"), VoiceTranscriptionError.permissionDenied.localizedDescription(languageCode: "uk"))
        XCTAssertNotEqual(VoiceTranscriptionError.permissionDenied.localizedDescription(languageCode: "en"), VoiceTranscriptionError.permissionDenied.localizedDescription(languageCode: "ru"))
        XCTAssertTrue(VoiceTranscriptionError.audioFailure.localizedDescription(languageCode: "uk").contains("мікрофон"))
    }

    #if DEBUG
    @MainActor
    func testDebugFixtureServiceEmitsFixedBenchScenarioAndStopsByCancellation() async throws {
        let service = DebugVoiceTranscriptionService(fixture: .bench)
        let partial = expectation(description: "fixed fixture partial result")
        var transcript = ""
        let task = Task { @MainActor in
            try await service.start(languageCode: "en", onPartialResult: { value in
                transcript = value
                partial.fulfill()
            }, onEvent: { _ in })
        }
        await fulfillment(of: [partial], timeout: 1)
        XCTAssertEqual(transcript, "Bench press, 3 sets of 10 reps, 80 kilograms")
        service.stop()
        task.cancel()
        _ = await task.result
    }

    @MainActor
    func testDebugFixtureServicePropagatesPermissionFailure() async {
        let service = DebugVoiceTranscriptionService(fixture: .permissionDenied)
        do {
            try await service.start(languageCode: "en", onPartialResult: { _ in }, onEvent: { _ in })
            XCTFail("Expected permission failure")
        } catch let error as VoiceTranscriptionError {
            XCTAssertEqual(error, .permissionDenied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testDebugFixtureServiceReportsRecognitionFailureEvent() async throws {
        let service = DebugVoiceTranscriptionService(fixture: .recognitionFailure)
        var receivedEvent: VoiceTranscriptionEvent?
        try await service.start(
            languageCode: "en",
            onPartialResult: { _ in },
            onEvent: { receivedEvent = $0 }
        )
        XCTAssertEqual(receivedEvent, .failed(.recognitionFailure))
    }

    @MainActor
    func testDebugFixtureServiceUsesInjectedSchedulerForSixtySecondTimeout() async throws {
        let service = DebugVoiceTranscriptionService(
            fixture: .bench,
            scheduler: ImmediateVoiceTranscriptionScheduler()
        )
        var receivedEvent: VoiceTranscriptionEvent?
        try await service.start(
            languageCode: "en",
            onPartialResult: { _ in },
            onEvent: { receivedEvent = $0 }
        )
        XCTAssertEqual(receivedEvent, .finished)
    }
    #endif
}
