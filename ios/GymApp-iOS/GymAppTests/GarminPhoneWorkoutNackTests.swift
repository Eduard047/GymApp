import XCTest
@testable import GymApp

final class GarminPhoneWorkoutNackTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private let binding = GarminPhoneBinding(
        account: String(repeating: "a", count: 64),
        device: "nack-test-device",
        pairingGeneration: String(repeating: "b", count: 64)
    )
    private let allowedKeys: Set<String> = [
        "type", "requestId", "reason", "bindingVersion",
        "accountBinding", "deviceBinding", "pairingGeneration"
    ]

    private func validMessage() -> [String: Any] {
        [
            "type": "create_workout", "bindingVersion": 2, "workoutMode": "planned",
            "requestId": "workout-nack-test-001", "accountBinding": binding.account,
            "deviceBinding": binding.device, "pairingGeneration": binding.pairingGeneration,
            "startedAtSeconds": Int64(now.timeIntervalSince1970) - 3600,
            "durationSeconds": 3600, "gymCalories": 60.0,
            "sets": [["exerciseName": "Bench Press", "weight": 50.0, "reps": 8]]
        ]
    }

    private func reason(_ message: Any) -> GarminPhoneNackReason {
        GarminPhoneWorkoutParser.rejectReason(message, expectedBinding: binding)
    }

    func testFixtureParsesBeforeMutation() {
        XCTAssertNotNil(GarminPhoneWorkoutParser.parse(validMessage(), expectedBinding: binding, now: now))
    }

    func testPayloadEchoesValidRequestIDWithFixedReasonAndBindings() {
        let payload = GarminPhoneWorkoutParser.nackPayload(
            for: validMessage(), reason: .rateLimited, binding: binding
        )
        XCTAssertEqual(payload.count, 7)
        XCTAssertEqual(Set(payload.keys), allowedKeys)
        XCTAssertEqual(payload["type"] as? String, "nack")
        XCTAssertEqual(payload["requestId"] as? String, "workout-nack-test-001")
        XCTAssertEqual(payload["reason"] as? String, "rate_limited")
        XCTAssertEqual(payload["bindingVersion"] as? Int, GarminPhoneWorkoutParser.bindingVersion)
        XCTAssertEqual(payload["accountBinding"] as? String, binding.account)
        XCTAssertEqual(payload["deviceBinding"] as? String, binding.device)
        XCTAssertEqual(payload["pairingGeneration"] as? String, binding.pairingGeneration)
    }

    func testRequestIDIsOmittedWhenNotPrintableASCIIWithinBound() {
        let invalid: [Any?] = [
            nil, 42, true, NSNull(), "", String(repeating: "a", count: 129),
            "bad\nid", "tab\tid", "caf\u{00E9}", "\u{7F}"
        ]
        for raw in invalid {
            XCTAssertNil(GarminPhoneWorkoutParser.nackRequestID(raw), "\(String(describing: raw))")
            var message = validMessage()
            message["requestId"] = raw ?? NSNull()
            let payload = GarminPhoneWorkoutParser.nackPayload(for: message, reason: .invalid, binding: binding)
            XCTAssertNil(payload["requestId"])
            XCTAssertEqual(payload.count, 6)
        }
        XCTAssertEqual(GarminPhoneWorkoutParser.nackRequestID("x"), "x")
        XCTAssertEqual(GarminPhoneWorkoutParser.nackRequestID(String(repeating: "a", count: 128))?.count, 128)
        XCTAssertEqual(GarminPhoneWorkoutParser.nackRequestID("a b~"), "a b~")
        // Missing key and non-dictionary messages carry no request id either.
        var missing = validMessage()
        missing.removeValue(forKey: "requestId")
        XCTAssertNil(GarminPhoneWorkoutParser.nackPayload(for: missing, reason: .invalid, binding: binding)["requestId"])
        let notDictionary = GarminPhoneWorkoutParser.nackPayload(for: "text", reason: .invalid, binding: binding)
        XCTAssertNil(notDictionary["requestId"])
        XCTAssertEqual(notDictionary.count, 6)
    }

    func testRejectReasonClassification() {
        var missingGeneration = validMessage()
        missingGeneration.removeValue(forKey: "pairingGeneration")
        XCTAssertNil(GarminPhoneWorkoutParser.parse(missingGeneration, expectedBinding: binding, now: now))
        XCTAssertEqual(reason(missingGeneration), .generationMissing)
        var nullGeneration = validMessage()
        nullGeneration["pairingGeneration"] = NSNull()
        XCTAssertEqual(reason(nullGeneration), .generationMissing)

        var staleGeneration = validMessage()
        staleGeneration["pairingGeneration"] = String(repeating: "c", count: 64)
        XCTAssertNil(GarminPhoneWorkoutParser.parse(staleGeneration, expectedBinding: binding, now: now))
        XCTAssertEqual(reason(staleGeneration), .generationMismatch)

        var wrongAccount = validMessage()
        wrongAccount["accountBinding"] = String(repeating: "d", count: 64)
        XCTAssertNil(GarminPhoneWorkoutParser.parse(wrongAccount, expectedBinding: binding, now: now))
        XCTAssertEqual(reason(wrongAccount), .bindingMismatch)

        var wrongDevice = validMessage()
        wrongDevice["deviceBinding"] = "other-device"
        XCTAssertNil(GarminPhoneWorkoutParser.parse(wrongDevice, expectedBinding: binding, now: now))
        XCTAssertEqual(reason(wrongDevice), .bindingMismatch)

        var brokenSets = validMessage()
        brokenSets["sets"] = [["exerciseName": "Bench Press", "weight": 50.0, "reps": 0]]
        XCTAssertNil(GarminPhoneWorkoutParser.parse(brokenSets, expectedBinding: binding, now: now))
        XCTAssertEqual(reason(brokenSets), .invalid)

        XCTAssertEqual(reason("not a dictionary"), .invalid)
        XCTAssertEqual(reason([1, 2, 3]), .invalid)
    }

    func testReasonRawValuesMatchAndroidContract() {
        XCTAssertEqual(
            Set(GarminPhoneNackReason.allCases.map(\.rawValue)),
            [
                "generation_missing", "generation_mismatch", "binding_mismatch",
                "invalid", "rejected", "rate_limited", "reset_required"
            ]
        )
        XCTAssertEqual(GarminPhoneNackReason.allCases.count, 7)
    }

    func testPayloadNeverCarriesWorkoutOrAccountDataBeyondTheAllowedKeys() {
        var message = validMessage()
        message["note"] = "private note"
        message["setMetrics"] = [[1, 2, 3]]
        for reason in GarminPhoneNackReason.allCases {
            let payload = GarminPhoneWorkoutParser.nackPayload(for: message, reason: reason, binding: binding)
            XCTAssertTrue(Set(payload.keys).isSubset(of: allowedKeys))
            XCTAssertNil(payload["sets"])
            XCTAssertNil(payload["note"])
            XCTAssertNil(payload["setMetrics"])
            XCTAssertEqual(payload["reason"] as? String, reason.rawValue)
        }
    }
}
