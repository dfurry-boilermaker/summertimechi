import Foundation
import CoreLocation
import MapKit

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
        if cloudCover > 0.4 { return .cloudy }

        let solarPos = solar.solarPosition(at: patio, date: date)
        guard solarPos.isAboveHorizon else { return .belowHorizon }

        let inShadow = buildings.contains { building in
            isPoint(patio, inShadowOf: building, solarPosition: solarPos)
        }

        return inShadow ? .shaded : .sunlit
    }

    /// Generates a 15-minute resolution timeline for a full day.
    /// - Parameters:
    ///   - cloudCover: Used when `cloudCoverByHour` is nil (e.g. tests).
    ///   - cloudCoverByHour: Optional per-hour cloud cover from WeatherKit. When provided, overrides `cloudCover` per slot.
    func generateTimeline(
        forBar bar: Bar,
        buildings: [OSMBuilding],
        date: Date,
        cloudCover: Double = 0.0,
        cloudCoverByHour: [Int: Double]? = nil
    ) -> SunTimeline {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        var entries: [SunTimelineEntry] = []

        // 96 entries × 15 min = 24 hours
        for i in 0..<96 {
            let entryDate = startOfDay.addingTimeInterval(Double(i) * 15 * 60)
            let hour = calendar.component(.hour, from: entryDate)
            let effectiveCloudCover = cloudCoverByHour?[hour] ?? cloudCover
            let status = sunStatus(
                forPatio: bar.coordinate,
                buildings: buildings,
                date: entryDate,
                cloudCover: effectiveCloudCover
            )
            entries.append(SunTimelineEntry(date: entryDate, status: status))
        }

        return SunTimeline(bar: bar, date: date, entries: entries)
    }

    // MARK: - Shadow Polygon Check

    /// Returns `true` if `patio` falls inside the shadow cast by `building` at the given solar position.
    ///
    /// Uses a component-polygon approach rather than a convex hull so that non-convex buildings
    /// (L-shapes, U-shapes, setbacks) are handled correctly. The shadow volume consists of:
    ///   1. The building footprint itself (patio directly beneath the roof)
    ///   2. The rooftop footprint translated in the shadow direction (tip of shadow)
    ///   3. One parallelogram quad per footprint edge (the swept shadow between base and tip)
    ///
    /// The convex-hull approach overestimates for concave buildings — e.g. the open notch of an
    /// L-shaped building would be incorrectly marked as shaded. Testing each component separately
    /// with ray-casting is geometrically exact for any polygon shape.
    func isPoint(
        _ patio: CLLocationCoordinate2D,
        inShadowOf building: OSMBuilding,
        solarPosition: SolarPosition
    ) -> Bool {
        guard solarPosition.isAboveHorizon,
              solarPosition.altitude > 0.1,   // Lowered from 0.5° — real shadows still exist at 2-5°
              building.heightMeters > 0,
              building.footprint.count >= 3 else {
            return false
        }

        let altRad = solar.toRadians(solarPosition.altitude)
        // Cap at 300 m so near-horizon shadows stay realistic without sprawling citywide.
        let shadowLength = min(building.heightMeters / tan(altRad), 300.0)
        let shadowAzimuth = (solarPosition.azimuth + 180.0).truncatingRemainder(dividingBy: 360.0)

        // Convert to flat-earth local coordinate system (meters, origin = building centroid)
        let origin = building.centroid
        let footprintLocal = building.footprint.map { toLocal(coord: $0, origin: origin) }
        let patioLocal = toLocal(coord: patio, origin: origin)

        // Shadow offset vector (direction away from sun, scaled to shadow length)
        let shadowDX = shadowLength * sin(solar.toRadians(shadowAzimuth))
        let shadowDY = shadowLength * cos(solar.toRadians(shadowAzimuth))

        let extruded = footprintLocal.map { CGPoint(x: $0.x + shadowDX, y: $0.y + shadowDY) }

        // 1. Patio directly under the building footprint
        if isPointInPolygon(patioLocal, polygon: footprintLocal) { return true }

        // 2. Patio at the tip of the shadow (under the translated rooftop)
        if isPointInPolygon(patioLocal, polygon: extruded) { return true }

        // 3. Each edge's parallelogram quad sweeps the shadow between base and tip.
        //    This handles every wall segment of any polygon — convex or concave.
        let n = footprintLocal.count
        for i in 0..<n {
            let j = (i + 1) % n
            let quad = [footprintLocal[i], footprintLocal[j], extruded[j], extruded[i]]
            if isPointInPolygon(patioLocal, polygon: quad) { return true }
        }

        return false
    }

    // MARK: - Coordinate Transform

    func toLocal(coord: CLLocationCoordinate2D, origin: CLLocationCoordinate2D) -> CGPoint {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(solar.toRadians(origin.latitude))
        let dx = (coord.longitude - origin.longitude) * metersPerDegreeLon
        let dy = (coord.latitude  - origin.latitude)  * metersPerDegreeLat
        return CGPoint(x: dx, y: dy)
    }

    /// Inverse of `toLocal`: converts a local meter-offset `CGPoint` back to geographic coordinates.
    func fromLocal(_ point: CGPoint, origin: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(solar.toRadians(origin.latitude))
        let longitude = origin.longitude + Double(point.x) / metersPerDegreeLon
        let latitude  = origin.latitude  + Double(point.y) / metersPerDegreeLat
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Returns the convex-hull shadow polygon cast by `building` at the given solar position,
    /// or `nil` if the sun is below the horizon or the building footprint is too small.
    /// (Convex hull is an acceptable approximation for map overlay rendering.)
    func shadowPolygon(for building: OSMBuilding, solarPosition: SolarPosition) -> MKPolygon? {
        guard solarPosition.isAboveHorizon,
              solarPosition.altitude > 0.1,
              building.heightMeters > 0,
              building.footprint.count >= 3 else {
            return nil
        }

        let altRad = solar.toRadians(solarPosition.altitude)
        let shadowLength = min(building.heightMeters / tan(altRad), 300.0)
        let shadowAzimuth = (solarPosition.azimuth + 180.0).truncatingRemainder(dividingBy: 360.0)

        let origin = building.centroid
        let footprintLocal = building.footprint.map { toLocal(coord: $0, origin: origin) }

        let shadowDX = shadowLength * sin(solar.toRadians(shadowAzimuth))
        let shadowDY = shadowLength * cos(solar.toRadians(shadowAzimuth))

        let extrudedFootprint = footprintLocal.map { pt in
            CGPoint(x: pt.x + shadowDX, y: pt.y + shadowDY)
        }

        let hull = convexHull(of: footprintLocal + extrudedFootprint)
        guard hull.count >= 3 else { return nil }

        var coords = hull.map { fromLocal($0, origin: origin) }
        return MKPolygon(coordinates: &coords, count: coords.count)
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
