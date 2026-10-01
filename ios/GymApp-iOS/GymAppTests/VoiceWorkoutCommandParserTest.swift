import XCTest
@testable import GymApp

final class VoiceWorkoutCommandParserTest: XCTestCase {
    private func sharedContract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/voice-workout-command-v1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    // MARK: Contract-constants parity

    func testSwiftConstantsEqualTheSharedCommandContract() throws {
        let contract = try sharedContract()
        let limits = try XCTUnwrap(contract["limits"] as? [String: Any])
        XCTAssertEqual(limits["maxTranscriptBytes"] as? Int, VoiceWorkoutCommandParser.maximumTranscriptBytes)
        XCTAssertEqual((limits["minWeightKg"] as? NSNumber)?.doubleValue, VoiceWorkoutCommandParser.minWeightKg)
        XCTAssertEqual((limits["maxWeightKg"] as? NSNumber)?.doubleValue, VoiceWorkoutCommandParser.maxWeightKg)
        XCTAssertEqual((limits["weightStepKg"] as? NSNumber)?.doubleValue, VoiceWorkoutCommandParser.weightStepKg)
        XCTAssertEqual(limits["minReps"] as? Int, VoiceWorkoutCommandParser.minReps)
        XCTAssertEqual(limits["maxReps"] as? Int, VoiceWorkoutCommandParser.maxReps)
        XCTAssertEqual(contract["fillerWords"] as? [String], VoiceWorkoutCommandParser.fillerWords)

        let intents = try XCTUnwrap(contract["intents"] as? [String: Any])
        let logSet = try XCTUnwrap(intents["logSet"] as? [String: Any])
        XCTAssertEqual(logSet["bodyweightPhrases"] as? [String], VoiceWorkoutCommandParser.bodyweightPhrases)
        let repeatPrevious = try XCTUnwrap(intents["repeatPrevious"] as? [String: Any])
        XCTAssertEqual(repeatPrevious["phrases"] as? [String], VoiceWorkoutCommandParser.repeatPhrases)
        let skipRest = try XCTUnwrap(intents["skipRest"] as? [String: Any])
        XCTAssertEqual(skipRest["phrases"] as? [String], VoiceWorkoutCommandParser.skipPhrases)
        let unknown = try XCTUnwrap(intents["unknown"] as? [String: Any])
        XCTAssertEqual(unknown["diagnosticCodes"] as? [String], VoiceWorkoutCommandParser.diagnosticCodes)
    }

    // MARK: Golden cases

    func testSharedGoldenCases() throws {
        let contract = try sharedContract()
        let cases = try XCTUnwrap(contract["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)

        for testCase in cases {
            let id = try XCTUnwrap(testCase["id"] as? String)
            let language = testCase["language"] as? String ?? "ru"
            let transcript: String
            if let literal = testCase["transcript"] as? String {
                transcript = literal
            } else if let repeated = testCase["transcriptRepeat"] as? [String: Any],
                      let text = repeated["text"] as? String,
                      let count = repeated["count"] as? Int {
                transcript = String(repeating: text, count: count)
            } else {
                XCTFail("Case \(id) has neither transcript nor transcriptRepeat")
                continue
            }

            let expected = try XCTUnwrap(testCase["expected"] as? [String: Any])
            let expectedIntent = try XCTUnwrap(expected["intent"] as? String)
            let result = VoiceWorkoutCommandParser.parse(transcript, locale: language)

            switch expectedIntent {
            case "logSet":
                guard case let .logSet(weightKg, reps) = result else {
                    XCTFail("Case \(id): expected logSet, got \(result)")
                    continue
                }
                let expectedWeight = (expected["weightKg"] as? NSNumber)?.doubleValue
                let expectedReps = expected["reps"] as? Int
                switch (weightKg, expectedWeight) {
                case let (.some(actual), .some(wanted)):
                    XCTAssertEqual(actual, wanted, accuracy: 1e-9, "Case \(id) weightKg")
                case (.none, .none):
                    break
                default:
                    XCTFail("Case \(id) weightKg: expected \(String(describing: expectedWeight)), got \(String(describing: weightKg))")
                }
                XCTAssertEqual(reps, expectedReps, "Case \(id) reps")
            case "repeatPrevious":
                XCTAssertEqual(result, .repeatPrevious, "Case \(id)")
            case "skipRest":
                XCTAssertEqual(result, .skipRest, "Case \(id)")
            case "unknown":
                guard case let .unknown(resultTranscript, code) = result else {
                    XCTFail("Case \(id): expected unknown, got \(result)")
                    continue
                }
                XCTAssertEqual(code, expected["code"] as? String, "Case \(id) code")
                if testCase["transcript"] != nil {
                    XCTAssertEqual(resultTranscript, transcript, "Case \(id) transcript echo")
                }
            default:
                XCTFail("Case \(id): unrecognized expected intent \(expectedIntent)")
            }
        }
    }

    // MARK: Hostile input

    func testNilTranscriptIsUnknownEmpty() {
        XCTAssertEqual(VoiceWorkoutCommandParser.parse(nil), .unknown(transcript: "", code: "empty"))
    }

    func testWhitespaceOnlyTranscriptIsUnknownEmpty() {
        XCTAssertEqual(VoiceWorkoutCommandParser.parse("   \n\t  "), .unknown(transcript: "   \n\t  ", code: "empty"))
    }

    func testOversizedTranscriptIsTruncatedAndFlagged() {
        let huge = String(repeating: "x", count: 20_000)
        let result = VoiceWorkoutCommandParser.parse(huge)
        guard case let .unknown(transcript, code) = result else {
            return XCTFail("Expected unknown, got \(result)")
        }
        XCTAssertEqual(code, "transcriptTooLong")
        XCTAssertLessThanOrEqual(transcript.utf8.count, VoiceWorkoutCommandParser.maximumTranscriptBytes)
    }

    func testEmojiAndControlCharactersNeverTrap() {
        let hostile = "🏋️‍♂️💥 80 \u{0000} на \u{200B} 8 \u{FFFD}"
        let result = VoiceWorkoutCommandParser.parse(hostile)
        if case .logSet(let weightKg, let reps) = result {
            XCTAssertEqual(weightKg, 80)
            XCTAssertEqual(reps, 8)
        }
        // No crash reaching here is the actual assertion.
    }

    func testRepeatedPunctuationNeverTraps() {
        let hostile = String(repeating: "!?;.,", count: 500)
        _ = VoiceWorkoutCommandParser.parse(hostile)
    }

    func testMixedScriptGarbageResolvesToUnknownNoMatch() {
        let result = VoiceWorkoutCommandParser.parse("藍色 qwerty бла-бла")
        XCTAssertEqual(result, .unknown(transcript: "藍色 qwerty бла-бла", code: "noMatch"))
    }

    func testThreeNumbersIsAmbiguous() {
        let result = VoiceWorkoutCommandParser.parse("80 на 8 на 10")
        guard case let .unknown(_, code) = result else {
            return XCTFail("Expected unknown, got \(result)")
        }
        XCTAssertEqual(code, "ambiguousNumbers")
    }

    func testNegativeWeightIsOutOfRange() {
        let result = VoiceWorkoutCommandParser.parse("-5 кг на 8")
        guard case let .unknown(_, code) = result else {
            return XCTFail("Expected unknown, got \(result)")
        }
        XCTAssertEqual(code, "weightOutOfRange")
    }

    func testExtremelyLongSingleWordNeverTraps() {
        let hostile = String(repeating: "а", count: 5_000) + " 80 на 8"
        _ = VoiceWorkoutCommandParser.parse(hostile)
    }

    // MARK: Typed-command submission pipeline (text → command → values)

    /// Mirrors what `ActiveWorkoutView.submitVoiceFallback`/`applyVoiceTranscript`
    /// do with the typed field's raw text: trim, then dispatch on the parsed
    /// intent. Exercising this pure mapping here — with untrimmed input, the
    /// same as a user's raw keystrokes — is the unit-testable half of the
    /// send button's wiring; the view-level half (that the button and
    /// `.onSubmit` both call the same handler, and that the handler captures
    /// `@State` text directly rather than relying on focus loss to commit
    /// it) is verified by code inspection, since it needs a live SwiftUI
    /// hierarchy to exercise.
    private func dispatchTypedCommand(_ rawText: String) -> VoiceWorkoutCommand? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return VoiceWorkoutCommandParser.parse(trimmed)
    }

    func testTypedSubmissionMapsRawTextToLogSetValues() {
        guard case let .logSet(weightKg, reps) = dispatchTypedCommand("  80 на 8  ") else {
            return XCTFail("Expected logSet")
        }
        XCTAssertEqual(weightKg, 80)
        XCTAssertEqual(reps, 8)
    }

    func testTypedSubmissionMapsRawTextToRepeatPrevious() {
        XCTAssertEqual(dispatchTypedCommand("\nповтори\t"), .repeatPrevious)
    }

    func testTypedSubmissionMapsRawTextToSkipRest() {
        XCTAssertEqual(dispatchTypedCommand("  дальше"), .skipRest)
    }

    func testTypedSubmissionOfWhitespaceOnlyTextIsNeverDispatched() {
        XCTAssertNil(dispatchTypedCommand("   \n\t  "))
        XCTAssertNil(dispatchTypedCommand(""))
    }

    @MainActor
    func testTypedCommandPlaceholderIsLocalizedPerLanguage() {
        XCTAssertEqual(ActiveWorkoutView.voiceCommandPlaceholder(languageCode: "en"), "80 by 8")
        XCTAssertEqual(ActiveWorkoutView.voiceCommandPlaceholder(languageCode: "uk"), "80 на 8")
        XCTAssertEqual(ActiveWorkoutView.voiceCommandPlaceholder(languageCode: "ru"), "80 на 8")
    }

    func testTypedSubmissionMapsUnrecognizedTextToUnknown() {
        guard case let .unknown(transcript, code) = dispatchTypedCommand(" bla bla ") else {
            return XCTFail("Expected unknown")
        }
        XCTAssertEqual(transcript, "bla bla")
        XCTAssertEqual(code, "noMatch")
    }
}
