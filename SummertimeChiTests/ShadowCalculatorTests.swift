import XCTest
import CoreLocation
@testable import SummertimeChi

/// Unit tests for ShadowCalculatorService.
/// Uses a simplified Willis Tower footprint for validation.
final class ShadowCalculatorTests: XCTestCase {
    let shadowCalc = ShadowCalculatorService.shared
    let solarCalc  = SolarCalculatorService.shared

    // Willis Tower approximate footprint (~60m × 60m square, simplified)
    let willisCoord = CLLocationCoordinate2D(latitude: 41.8788, longitude: -87.6359)

    func makeWillisTower() -> OSMBuilding {
        // 443m height (architectural), simplified square footprint
        let halfSize = 0.0003 // ~30m in degrees
        let c = willisCoord
        return OSMBuilding(
            id: 99999,
            footprint: [
                CLLocationCoordinate2D(latitude: c.latitude - halfSize, longitude: c.longitude - halfSize),
                CLLocationCoordinate2D(latitude: c.latitude - halfSize, longitude: c.longitude + halfSize),
                CLLocationCoordinate2D(latitude: c.latitude + halfSize, longitude: c.longitude + halfSize),
                CLLocationCoordinate2D(latitude: c.latitude + halfSize, longitude: c.longitude - halfSize),
            ],
            heightMeters: 443.0,
            centroid: c
        )
    }

    // MARK: - Convex Hull

    func testConvexHullSquare() {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
            CGPoint(x: 0.5, y: 0.5) // interior point
        ]
        let hull = shadowCalc.convexHull(of: points)
        XCTAssertEqual(hull.count, 4, "Hull of a square + interior point should have 4 vertices")
    }

    func testConvexHullCollinear() {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)
        ]
        let hull = shadowCalc.convexHull(of: points)
        XCTAssertLessThanOrEqual(hull.count, 3)
    }

    // MARK: - Point-in-Polygon

    func testPointInSquare() {
        let square: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)
        ]
        XCTAssertTrue(shadowCalc.isPointInPolygon(CGPoint(x: 5, y: 5), polygon: square))
        XCTAssertFalse(shadowCalc.isPointInPolygon(CGPoint(x: 15, y: 15), polygon: square))
        XCTAssertFalse(shadowCalc.isPointInPolygon(CGPoint(x: -1, y: 5), polygon: square))
    }

    // MARK: - Shadow Direction Logic

    /// At noon (sun in south), shadows point north.
    /// A patio directly NORTH of Willis Tower should be in shadow.
    func testNoonShadowPointsNorth() {
        // June 21, 2024, solar noon Chicago ≈ 18:15 UTC
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2024, month: 6, day: 21, hour: 18, minute: 15
        )
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let solarPos = solarCalc.solarPosition(at: willisCoord, date: date)

        // Shadow should point roughly north at noon
        let shadowAzimuth = (solarPos.azimuth + 180).truncatingRemainder(dividingBy: 360)
        XCTAssertGreaterThan(shadowAzimuth, 340, "Shadow at noon should point north (azimuth ~360/0)")

        let building = makeWillisTower()

        // Patio ~500m directly north
        let patioNorth = CLLocationCoordinate2D(
            latitude: willisCoord.latitude + 0.0045, // ~500m north
            longitude: willisCoord.longitude
        )
        // Patio ~500m directly south
        let patioSouth = CLLocationCoordinate2D(
            latitude: willisCoord.latitude - 0.0045, // ~500m south
            longitude: willisCoord.longitude
        )

        let northInShadow = shadowCalc.isPoint(patioNorth, inShadowOf: building, solarPosition: solarPos)
        let southInShadow = shadowCalc.isPoint(patioSouth, inShadowOf: building, solarPosition: solarPos)

        XCTAssertTrue(northInShadow, "Patio directly north should be in shadow at noon on summer solstice")
        XCTAssertFalse(southInShadow, "Patio directly south should be in sun at noon")
    }

    /// In the morning (sun in east), shadows point west.
    func testMorningShadowPointsWest() {
        // June 21, 2024, 8 AM CDT = 13:00 UTC
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2024, month: 6, day: 21, hour: 13, minute: 0
        )
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let solarPos = solarCalc.solarPosition(at: willisCoord, date: date)

        XCTAssertTrue(solarPos.isAboveHorizon, "Sun should be above horizon at 8 AM")

        // Sun should be in the east (azimuth ~90°) in the morning
        XCTAssertGreaterThan(solarPos.azimuth, 60)
        XCTAssertLessThan(solarPos.azimuth, 130)

        // Shadow direction should be west
        let shadowAzimuth = (solarPos.azimuth + 180).truncatingRemainder(dividingBy: 360)
        XCTAssertGreaterThan(shadowAzimuth, 200, "Morning shadow should point west (azimuth ~270°)")
        XCTAssertLessThan(shadowAzimuth, 340)
    }

    // MARK: - Sun Status

    func testSunStatusBelowHorizon() {
        // Midnight
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2024, month: 6, day: 22, hour: 5, minute: 0
        )
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let status = shadowCalc.sunStatus(forPatio: willisCoord, buildings: [], date: date)
        XCTAssertEqual(status, .belowHorizon)
    }

    func testSunStatusCloudyOverride() {
        // June 21 noon — should be sunlit, but cloud override kicks in
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2024, month: 6, day: 21, hour: 18, minute: 15
        )
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let status = shadowCalc.sunStatus(forPatio: willisCoord, buildings: [], date: date, cloudCover: 0.9)
        XCTAssertEqual(status, .cloudy)
    }

    func testSunStatusPartialSunOverride() {
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2024, month: 6, day: 21, hour: 18, minute: 15
        )
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let status = shadowCalc.sunStatus(forPatio: willisCoord, buildings: [], date: date, cloudCover: 0.6)
        XCTAssertEqual(status, .partialSun)
    }
}
