import XCTest
@testable import GymApp

final class PlateCalculatorTests: XCTestCase {
    func testLoadsTheHeaviestPlatesFirstOnEachSide() {
        let load = PlateCalculator.load(total: 82.5)

        XCTAssertEqual(load.status, .loaded)
        XCTAssertEqual(load.platesPerSide, [25, 5, 1.25])
        XCTAssertEqual(load.remainderPerSide, 0)
    }

    func testCommonTotals() {
        XCTAssertEqual(PlateCalculator.load(total: 100).platesPerSide, [25, 15])
        XCTAssertEqual(PlateCalculator.load(total: 140).platesPerSide, [25, 25, 10])
        XCTAssertEqual(PlateCalculator.load(total: 22.5).platesPerSide, [1.25])
        XCTAssertEqual(PlateCalculator.load(total: 25).platesPerSide, [2.5])
    }

    func testEmptyBarAndLighterTotals() {
        XCTAssertEqual(PlateCalculator.load(total: 20), PlateLoad(status: .barOnly, platesPerSide: [], remainderPerSide: 0))
        XCTAssertEqual(PlateCalculator.load(total: 15).status, .belowBar)
        XCTAssertEqual(PlateCalculator.load(total: 0).status, .belowBar)
        XCTAssertEqual(PlateCalculator.load(total: .nan).status, .belowBar)
    }

    func testReportsWhatThePlatesCannotMakeUp() {
        let load = PlateCalculator.load(total: 83)

        XCTAssertEqual(load.platesPerSide, [25, 5, 1.25])
        XCTAssertEqual(load.remainderPerSide, 0.25, accuracy: 1e-9)

        let tooSmall = PlateCalculator.load(total: 21)
        XCTAssertEqual(tooSmall.status, .loaded)
        XCTAssertEqual(tooSmall.platesPerSide, [])
        XCTAssertEqual(tooSmall.remainderPerSide, 0.5, accuracy: 1e-9)
    }

    func testSummaryIsLocalized() {
        let load = PlateCalculator.load(total: 82.5)

        XCTAssertEqual(PlateCalculator.summaryLines(for: load, languageCode: "ru"), ["На каждую сторону: 25 + 5 + 1,25"])
        XCTAssertEqual(PlateCalculator.summaryLines(for: load, languageCode: "uk"), ["На кожну сторону: 25 + 5 + 1,25"])
        XCTAssertEqual(PlateCalculator.summaryLines(for: load, languageCode: "en"), ["Per side: 25 + 5 + 1.25"])
        XCTAssertEqual(
            PlateCalculator.summaryLines(for: PlateCalculator.load(total: 83), languageCode: "ru"),
            ["На каждую сторону: 25 + 5 + 1,25", "Остаток: 0,25 кг на сторону"]
        )
        XCTAssertEqual(
            PlateCalculator.summaryLines(for: PlateCalculator.load(total: 15), languageCode: "ru"),
            ["Меньше грифа 20 кг"]
        )
        XCTAssertEqual(
            PlateCalculator.summaryLines(for: PlateCalculator.load(total: 20), languageCode: "en"),
            ["Bar only (20 kg)"]
        )
    }

    func testOnlyBarbellExercisesUseTheCalculator() {
        XCTAssertTrue(PlateCalculator.applies(toCatalogKey: "bench_press"))
        XCTAssertTrue(PlateCalculator.applies(toCatalogKey: "squat"))
        XCTAssertFalse(PlateCalculator.applies(toCatalogKey: "dumbbell_bench_press"))
        XCTAssertFalse(PlateCalculator.applies(toCatalogKey: "push_up"))
        XCTAssertFalse(PlateCalculator.applies(toCatalogKey: nil))
    }
}
