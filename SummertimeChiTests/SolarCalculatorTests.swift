import XCTest
import CoreLocation
@testable import SummertimeChi

/// Unit tests for SolarCalculatorService, validated against the NOAA Solar Calculator.
/// Reference: https://gml.noaa.gov/grad/solcalc/azel.html
final class SolarCalculatorTests: XCTestCase {
    let calculator = SolarCalculatorService.shared

    // Chicago coordinates
    let chicagoLat = 41.85
    let chicagoLon = -87.65
    let chicago = CLLocationCoordinate2D(latitude: 41.85, longitude: -87.65)

    // MARK: - Summer Solstice

    /// Summer solstice 2024 (June 21) solar noon in Chicago.
    /// NOAA reference: altitude ≈ 71.2°, azimuth ≈ 180°
    func testSummerSolsticeNoon() throws {
        // June 21, 2024 18:30 UTC = ~1:30 PM CDT (solar noon in Chicago ≈ 13:15 CDT)
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2024, month: 6, day: 21, hour: 18, minute: 15
        )
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let pos = calculator.solarPosition(at: chicago, date: date)

        XCTAssertGreaterThan(pos.altitude, 68.0, "Summer solstice noon altitude should be ~71°")
        XCTAssertLessThan(pos.altitude,    75.0)
        XCTAssertGreaterThan(pos.azimuth, 160.0, "Solar noon azimuth should be near 180° (south)")
        XCTAssertLessThan(pos.azimuth,    200.0)
        XCTAssertTrue(pos.isAboveHorizon)
    }

    // MARK: - Winter Solstice

    /// Winter solstice 2024 (December 21) solar noon in Chicago.
    /// NOAA reference: altitude ≈ 24.8°, azimuth ≈ 180°
    func testWinterSolsticeNoon() throws {
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2024, month: 12, day: 21, hour: 18, minute: 15
        )
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let pos = calculator.solarPosition(at: chicago, date: date)

        XCTAssertGreaterThan(pos.altitude, 22.0, "Winter solstice noon altitude should be ~24.8°")
        XCTAssertLessThan(pos.altitude,    28.0)
        XCTAssertTrue(pos.isAboveHorizon)
    }

    // MARK: - Sunrise / Sunset

    /// Chicago sunrise on June 21, 2024 should be approximately 5:16 AM CDT.
    func testSummerSolsticeSunrise() throws {
        let components = DateComponents(
            timeZone: TimeZone(identifier: "America/Chicago"),
            year: 2024, month: 6, day: 21
        )
        let date = Calendar.current.date(from: components)!
        let (sunrise, _) = calculator.sunriseSunset(at: chicago, date: date)

        guard let sunrise = sunrise else {
            XCTFail("Sunrise should not be nil on summer solstice")
            return
        }

        let cal = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "America/Chicago")!
        let components2 = cal.dateComponents(in: tz, from: sunrise)
        let hour = components2.hour ?? -1
        let minute = components2.minute ?? -1

        // Expected: 5:16 AM CDT (accept ±20 min tolerance)
        let minuteOfDay = hour * 60 + minute
        let expectedMinuteOfDay = 5 * 60 + 16
        XCTAssertEqual(minuteOfDay, expectedMinuteOfDay, accuracy: 20,
                       "Sunrise should be ~5:16 AM CDT")
    }

    /// Chicago sunset on June 21, 2024 should be approximately 8:29 PM CDT.
    func testSummerSolsticeSunset() throws {
        let components = DateComponents(
            timeZone: TimeZone(identifier: "America/Chicago"),
            year: 2024, month: 6, day: 21
        )
        let date = Calendar.current.date(from: components)!
        let (_, sunset) = calculator.sunriseSunset(at: chicago, date: date)

        guard let sunset = sunset else {
            XCTFail("Sunset should not be nil on summer solstice")
            return
        }

        let cal = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "America/Chicago")!
        let components2 = cal.dateComponents(in: tz, from: sunset)
        let hour = components2.hour ?? -1
        let minute = components2.minute ?? -1

        // Expected: 8:29 PM CDT (accept ±20 min)
        let minuteOfDay = hour * 60 + minute
        let expectedMinuteOfDay = 20 * 60 + 29
        XCTAssertEqual(minuteOfDay, expectedMinuteOfDay, accuracy: 20,
                       "Sunset should be ~8:29 PM CDT")
    }

    // MARK: - Below Horizon

    /// At midnight local time, sun should be below horizon in Chicago.
    func testMidnightBelowHorizon() throws {
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2024, month: 6, day: 22, hour: 5, minute: 0 // Midnight CDT = 5 AM UTC
        )
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let pos = calculator.solarPosition(at: chicago, date: date)
        XCTAssertFalse(pos.isAboveHorizon, "Sun should be below horizon at midnight")
    }

    // MARK: - Julian Day

    func testJulianDayJ2000() throws {
        // J2000.0 = January 1, 2000, 12:00 TT ≈ 12:00 UTC
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2000, month: 1, day: 1, hour: 12
        )
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let jd = calculator.julianDay(from: date)
        XCTAssertEqual(jd, 2451545.0, accuracy: 0.001)
    }

    // MARK: - Geohash Sanity

    func testGeohashLength() {
        let hash = DataMergeService.shared.geohash(lat: 41.85, lon: -87.65, precision: 7)
        XCTAssertEqual(hash.count, 7)
    }

    func testGeohashConsistency() {
        let hash1 = DataMergeService.shared.geohash(lat: 41.85, lon: -87.65, precision: 7)
        let hash2 = DataMergeService.shared.geohash(lat: 41.85, lon: -87.65, precision: 7)
        XCTAssertEqual(hash1, hash2)
    }

    // MARK: - Jaro-Winkler

    func testJaroWinklerIdentical() {
        let score = DataMergeService.shared.jaroWinkler("The Green Mill", "The Green Mill")
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testJaroWinklerSimilar() {
        let score = DataMergeService.shared.jaroWinkler("Green Mill", "Green Mill Cocktail Lounge")
        XCTAssertGreaterThan(score, 0.7)
    }

    func testJaroWinklerDifferent() {
        let score = DataMergeService.shared.jaroWinkler("Wrigley Field", "Soldier Field")
        XCTAssertLessThan(score, 0.75)
    }
}
