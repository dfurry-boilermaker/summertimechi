import XCTest
import CoreLocation
@testable import SummertimeChi

/// Tests for Bar.sunlightHours(on:) — the dynamic daylight-overlap calculation.
/// Uses the summer solstice (June 21, 2024) for predictable sunrise/sunset:
///   Sunrise ≈ 5:16 AM CDT (5.27h), Sunset ≈ 8:29 PM CDT (20.48h)
final class SunlightHoursTests: XCTestCase {

    private let chicagoCoord = CLLocationCoordinate2D(latitude: 41.85, longitude: -87.65)

    private var chicagoCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        return cal
    }

    private var summerSolstice: Date {
        let comps = DateComponents(
            timeZone: TimeZone(identifier: "America/Chicago"),
            year: 2024, month: 6, day: 21
        )
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    private func makeBar(open: Int?, close: Int?) -> Bar {
        Bar(
            id: UUID(),
            name: "Test Bar",
            coordinate: chicagoCoord,
            address: nil,
            neighborhood: nil,
            yelpID: nil,
            yelpURL: nil,
            yelpRating: 0,
            yelpReviewCount: 0,
            hasPatioConfirmed: true,
            dataSourceMask: .osm,
            isFavorite: false,
            sunAlertsEnabled: false,
            cachedSunStatus: nil,
            cachedStatusTimestamp: nil,
            openHour: open,
            closeHour: close
        )
    }

    // MARK: - Nil Hours

    func testNilHoursReturnsNil() {
        let bar = makeBar(open: nil, close: nil)
        XCTAssertNil(bar.sunlightHours(on: summerSolstice, calendar: chicagoCalendar))
    }

    func testPartialNilHoursReturnsNil() {
        let bar = makeBar(open: 11, close: nil)
        XCTAssertNil(bar.sunlightHours(on: summerSolstice, calendar: chicagoCalendar))
    }

    // MARK: - Daytime Bars

    /// Bar open 9 AM – 6 PM: fully within daylight. Expected overlap = 9 hours.
    func testDaytimeBarFullOverlap() {
        let bar = makeBar(open: 9, close: 18)
        let hours = bar.sunlightHours(on: summerSolstice, calendar: chicagoCalendar)
        XCTAssertNotNil(hours)
        XCTAssertEqual(hours!, 9.0, accuracy: 0.5)
    }

    /// Bar open 7 AM – 2 PM: all hours within daylight. Expected overlap = 7 hours.
    func testMorningBarFullOverlap() {
        let bar = makeBar(open: 7, close: 14)
        let hours = bar.sunlightHours(on: summerSolstice, calendar: chicagoCalendar)
        XCTAssertNotNil(hours)
        XCTAssertEqual(hours!, 7.0, accuracy: 0.5)
    }

    /// Bar open 7 AM – 10 PM: extends past sunset. Expected overlap ≈ 13.5h (sunrise is before 7).
    func testAllDayBarClippedBySunset() {
        let bar = makeBar(open: 7, close: 22)
        let hours = bar.sunlightHours(on: summerSolstice, calendar: chicagoCalendar)
        XCTAssertNotNil(hours)
        // Overlap = sunset(~20.48) - 7 = ~13.48h
        XCTAssertEqual(hours!, 13.5, accuracy: 1.0)
    }

    // MARK: - Evening / Overnight Bars

    /// Bar open 5 PM – midnight (close=0): partial overlap with late daylight.
    /// Expected overlap ≈ 3.5h (sunset ~20:29 minus 17:00).
    func testEveningBarPartialOverlap() {
        let bar = makeBar(open: 17, close: 0)
        let hours = bar.sunlightHours(on: summerSolstice, calendar: chicagoCalendar)
        XCTAssertNotNil(hours)
        XCTAssertEqual(hours!, 3.5, accuracy: 1.0)
    }

    /// Bar open 8 PM – 2 AM: opens near sunset. Expected overlap ≈ 0.5h.
    func testLateEveningBarMinimalOverlap() {
        let bar = makeBar(open: 20, close: 2)
        let hours = bar.sunlightHours(on: summerSolstice, calendar: chicagoCalendar)
        XCTAssertNotNil(hours)
        XCTAssertEqual(hours!, 0.5, accuracy: 0.5)
    }

    /// Bar open 10 PM – 4 AM: entirely after sunset. Expected overlap = 0.
    func testNightOnlyBarZeroOverlap() {
        let bar = makeBar(open: 22, close: 4)
        let hours = bar.sunlightHours(on: summerSolstice, calendar: chicagoCalendar)
        XCTAssertNotNil(hours)
        XCTAssertEqual(hours!, 0.0, accuracy: 0.1)
    }

    // MARK: - Winter

    /// Winter solstice (Dec 21) has much shorter daylight (~9h).
    /// Bar open 9 AM – 6 PM should get less sunlight than in summer.
    func testWinterSolsticeShorterDaylight() {
        let comps = DateComponents(
            timeZone: TimeZone(identifier: "America/Chicago"),
            year: 2024, month: 12, day: 21
        )
        let winterDate = Calendar(identifier: .gregorian).date(from: comps)!
        let bar = makeBar(open: 9, close: 18)
        let hours = bar.sunlightHours(on: winterDate, calendar: chicagoCalendar)
        XCTAssertNotNil(hours)
        // Winter sunset ~4:20 PM CDT → overlap = ~16.33 - 9 = ~7.3h
        // (sunrise ~7:15, sunset ~16:20, overlap = 16.33 - 9 = 7.33)
        XCTAssertLessThan(hours!, 8.0, "Winter daylight overlap should be less than summer")
        XCTAssertGreaterThan(hours!, 5.0)
    }

    // MARK: - Total Open Hours

    func testTotalOpenHoursNormal() {
        let bar = makeBar(open: 9, close: 18)
        XCTAssertEqual(bar.totalOpenHours, 9.0)
    }

    func testTotalOpenHoursOvernight() {
        let bar = makeBar(open: 20, close: 2)
        XCTAssertEqual(bar.totalOpenHours, 6.0)
    }

    func testTotalOpenHoursMidnight() {
        let bar = makeBar(open: 11, close: 0)
        XCTAssertEqual(bar.totalOpenHours, 13.0)
    }

    func testTotalOpenHoursNil() {
        let bar = makeBar(open: nil, close: nil)
        XCTAssertNil(bar.totalOpenHours)
    }

    // MARK: - Sunlight Fraction

    /// Daytime bar (9-18) on summer solstice: all 9 open hours are in daylight → fraction ≈ 1.0
    func testSunlightFractionFullDaylight() {
        let bar = makeBar(open: 9, close: 18)
        let fraction = bar.sunlightFraction(on: summerSolstice, calendar: chicagoCalendar)
        XCTAssertNotNil(fraction)
        XCTAssertEqual(fraction!, 1.0, accuracy: 0.05)
    }

    /// Night bar (22-4) on summer solstice: 0 sun hours / 6 total → fraction ≈ 0.0
    func testSunlightFractionNoDaylight() {
        let bar = makeBar(open: 22, close: 4)
        let fraction = bar.sunlightFraction(on: summerSolstice, calendar: chicagoCalendar)
        XCTAssertNotNil(fraction)
        XCTAssertEqual(fraction!, 0.0, accuracy: 0.05)
    }

    func testSunlightFractionNilForUnknownHours() {
        let bar = makeBar(open: nil, close: nil)
        XCTAssertNil(bar.sunlightFraction(on: summerSolstice, calendar: chicagoCalendar))
    }

    // MARK: - Formatted Display

    func testFormattedSunlightHoursDisplay() {
        let bar = makeBar(open: 9, close: 18)
        let text = bar.formattedSunlightHours(on: summerSolstice, calendar: chicagoCalendar)
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("hrs of sun") || text!.contains("hr of sun"))
    }

    func testFormattedNoDaylightHours() {
        let bar = makeBar(open: 22, close: 4)
        let text = bar.formattedSunlightHours(on: summerSolstice, calendar: chicagoCalendar)
        XCTAssertEqual(text, "No daylight hours")
    }

    func testFormattedNilForUnknownHours() {
        let bar = makeBar(open: nil, close: nil)
        XCTAssertNil(bar.formattedSunlightHours(on: summerSolstice, calendar: chicagoCalendar))
    }
}
