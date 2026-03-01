import XCTest
import CoreLocation
@testable import SummertimeChi

/// Unit tests for DataMergeService — geohash and Jaro-Winkler algorithms.
final class DataMergeTests: XCTestCase {
    let service = DataMergeService.shared

    // MARK: - Geohash

    func testGeohashChicagoLoop() {
        // Chicago Loop coordinates should produce a consistent geohash
        let hash = service.geohash(lat: 41.8827, lon: -87.6233, precision: 7)
        XCTAssertEqual(hash.count, 7)
        // dp3wjzt is the known geohash for ~Chicago Loop center
        XCTAssertTrue(hash.hasPrefix("dp3"), "Chicago Loop geohash should start with 'dp3'")
    }

    func testGeohashProximity() {
        // Two bars within 150m should share the same precision-7 geohash cell
        let bar1Hash = service.geohash(lat: 41.9472, lon: -87.6539, precision: 7)
        let bar2Hash = service.geohash(lat: 41.9473, lon: -87.6540, precision: 7) // ~15m away
        XCTAssertEqual(bar1Hash, bar2Hash, "Very close bars should share a precision-7 geohash cell")
    }

    // MARK: - Jaro-Winkler

    func testJaroWinklerIdentical() {
        XCTAssertEqual(service.jaroWinkler("Gman Tavern", "Gman Tavern"), 1.0, accuracy: 0.001)
    }

    func testJaroWinklerCaseInsensitive() {
        let score = service.jaroWinkler("GMAN TAVERN", "gman tavern")
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testJaroWinklerSimilarNames() {
        // "Piece" vs "Piece Brewery & Pizzeria" — should be high similarity
        let score = service.jaroWinkler("Piece", "Piece Brewery & Pizzeria")
        XCTAssertGreaterThan(score, 0.7)
    }

    func testJaroWinklerDifferentNames() {
        let score = service.jaroWinkler("Green Mill", "Hopleaf")
        XCTAssertLessThan(score, 0.6)
    }

    func testJaroWinklerEmpty() {
        XCTAssertEqual(service.jaroWinkler("", "Anything"), 0.0)
        XCTAssertEqual(service.jaroWinkler("Anything", ""), 0.0)
        XCTAssertEqual(service.jaroWinkler("", ""), 0.0)
    }

    // MARK: - Deduplication

    func testDeduplicateSameBar() {
        let coordinate = CLLocationCoordinate2D(latitude: 41.9472, longitude: -87.6539)
        let bar1 = makeBar(name: "Gman Tavern", coordinate: coordinate, source: .cityPermit)
        let bar2 = makeBar(name: "G-Man Tavern", coordinate: coordinate, source: .yelp)

        let result = service.deduplicate([bar1, bar2])
        XCTAssertEqual(result.count, 1, "Two bars with same location and similar name should be merged")
    }

    func testDeduplicateDifferentBars() {
        let bar1 = makeBar(
            name: "Hopleaf",
            coordinate: CLLocationCoordinate2D(latitude: 41.9802, longitude: -87.6692),
            source: .osm
        )
        let bar2 = makeBar(
            name: "Green Mill",
            coordinate: CLLocationCoordinate2D(latitude: 41.9651, longitude: -87.6698),
            source: .yelp
        )
        let result = service.deduplicate([bar1, bar2])
        XCTAssertEqual(result.count, 2, "Two different bars should not be merged")
    }

    // MARK: - Helpers

    private func makeBar(
        name: String,
        coordinate: CLLocationCoordinate2D,
        source: Bar.DataSourceMask
    ) -> Bar {
        Bar(
            id: UUID(),
            name: name,
            coordinate: coordinate,
            yelpRating: 0,
            yelpReviewCount: 0,
            hasPatioConfirmed: true,
            dataSourceMask: source,
            isFavorite: false,
            sunAlertsEnabled: false
        )
    }
}
