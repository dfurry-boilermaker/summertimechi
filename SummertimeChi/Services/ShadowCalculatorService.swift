import Foundation
import CoreLocation

/// Computes shadow polygons from OSM building footprints and sun position,
/// then tests whether a patio point falls inside any shadow.
final class ShadowCalculatorService {
    static let shared = ShadowCalculatorService()
    private let solar = SolarCalculatorService.shared
    private init() {}

    // MARK: - Public API

    /// Returns the sun status for a patio given surrounding buildings and current time.
    func sunStatus(
        forPatio patio: CLLocationCoordinate2D,
        buildings: [OSMBuilding],
        date: Date,
        cloudCover: Double = 0.0
    ) -> SunStatus {
        // Cloud cover override
        if cloudCover > 0.8 { return .cloudy }
        if cloudCover > 0.4 { return .partialSun }

        let solarPos = solar.solarPosition(at: patio, date: date)
        guard solarPos.isAboveHorizon else { return .belowHorizon }

        let inShadow = buildings.contains { building in
            isPoint(patio, inShadowOf: building, solarPosition: solarPos)
        }

        return inShadow ? .shaded : .sunlit
    }

    /// Generates a 15-minute resolution timeline for a full day.
    func generateTimeline(
        forBar bar: Bar,
        buildings: [OSMBuilding],
        date: Date,
        cloudCover: Double = 0.0
    ) -> SunTimeline {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        var entries: [SunTimelineEntry] = []

        // 96 entries × 15 min = 24 hours
        for i in 0..<96 {
            let entryDate = startOfDay.addingTimeInterval(Double(i) * 15 * 60)
            let status = sunStatus(
                forPatio: bar.coordinate,
                buildings: buildings,
                date: entryDate,
                cloudCover: cloudCover
            )
            entries.append(SunTimelineEntry(date: entryDate, status: status))
        }

        return SunTimeline(bar: bar, date: date, entries: entries)
    }

    // MARK: - Shadow Polygon Check

    /// Returns `true` if `patio` falls inside the shadow cast by `building` at the given solar position.
    func isPoint(
        _ patio: CLLocationCoordinate2D,
        inShadowOf building: OSMBuilding,
        solarPosition: SolarPosition
    ) -> Bool {
        guard solarPosition.isAboveHorizon,
              solarPosition.altitude > 0.5,   // Ignore near-horizon (very long shadows, unreliable)
              building.footprint.count >= 3 else {
            return false
        }

        let altRad = solar.toRadians(solarPosition.altitude)
        let shadowLength = building.heightMeters / tan(altRad)
        let shadowAzimuth = (solarPosition.azimuth + 180.0).truncatingRemainder(dividingBy: 360.0)

        // Convert to flat-earth local coordinate system (meters, origin = building centroid)
        let origin = building.centroid
        let footprintLocal = building.footprint.map { coord in
            toLocal(coord: coord, origin: origin)
        }
        let patioLocal = toLocal(coord: patio, origin: origin)

        // Extrude footprint in shadow direction
        let shadowDX = shadowLength * sin(solar.toRadians(shadowAzimuth))
        let shadowDY = shadowLength * cos(solar.toRadians(shadowAzimuth))

        let extrudedFootprint = footprintLocal.map { pt in
            CGPoint(x: pt.x + shadowDX, y: pt.y + shadowDY)
        }

        // Convex hull of original + extruded footprint
        let allPoints = footprintLocal + extrudedFootprint
        let hull = convexHull(of: allPoints)

        return isPointInPolygon(patioLocal, polygon: hull)
    }

    // MARK: - Coordinate Transform

    private func toLocal(coord: CLLocationCoordinate2D, origin: CLLocationCoordinate2D) -> CGPoint {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(solar.toRadians(origin.latitude))
        let dx = (coord.longitude - origin.longitude) * metersPerDegreeLon
        let dy = (coord.latitude  - origin.latitude)  * metersPerDegreeLat
        return CGPoint(x: dx, y: dy)
    }

    // MARK: - Point-in-Polygon (Ray Casting)

    /// Returns `true` if `point` is inside `polygon` using the ray-casting algorithm
    /// (Jordan curve theorem). Works for convex and concave polygons.
    func isPointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].x, yi = polygon[i].y
            let xj = polygon[j].x, yj = polygon[j].y
            let intersect = ((yi > point.y) != (yj > point.y))
                         && (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi)
            if intersect { inside = !inside }
            j = i
        }
        return inside
    }

    // MARK: - Convex Hull (Graham Scan)

    /// Computes the convex hull of a set of 2D points using the Graham scan algorithm.
    func convexHull(of points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        // Find the lowest (then leftmost) point
        let pivot = points.min { a, b in
            a.y < b.y || (a.y == b.y && a.x < b.x)
        }!

        // Sort by polar angle relative to pivot
        let sorted = points.filter { $0 != pivot }.sorted { a, b in
            let angleA = atan2(Double(a.y - pivot.y), Double(a.x - pivot.x))
            let angleB = atan2(Double(b.y - pivot.y), Double(b.x - pivot.x))
            if abs(angleA - angleB) < 1e-10 {
                let distA = hypot(Double(a.x - pivot.x), Double(a.y - pivot.y))
                let distB = hypot(Double(b.x - pivot.x), Double(b.y - pivot.y))
                return distA < distB
            }
            return angleA < angleB
        }

        var hull: [CGPoint] = [pivot]
        for point in sorted {
            while hull.count >= 2 {
                let o = hull[hull.count - 2]
                let a = hull[hull.count - 1]
                let b = point
                if crossProduct(o: o, a: a, b: b) <= 0 {
                    hull.removeLast()
                } else {
                    break
                }
            }
            hull.append(point)
        }
        return hull
    }

    /// Returns the cross product of vectors OA and OB.
    /// Positive = counter-clockwise turn, Negative = clockwise, Zero = collinear.
    private func crossProduct(o: CGPoint, a: CGPoint, b: CGPoint) -> Double {
        Double((a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x))
    }
}
