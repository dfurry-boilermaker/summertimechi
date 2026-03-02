import Foundation
import CoreLocation
import CoreData

/// Fetches Chicago building footprints and LIDAR heights from the ArcGIS
/// Chicago 3D Buildings Feature Service. Uses `BuildingGeometryEntity` for a 30-day cache.
/// ArcGIS buildings are stored with negative `osmWayID` values to avoid collisions with OSM IDs.
final class ArcGISBuildingService {
    static let shared = ArcGISBuildingService()
    private init() {}

    private let baseURL = URL(
        string: "https://gis.hlplanning.com/server/rest/services/Hosted/Chicago_3D_Buildings/FeatureServer/9/query"
    )!

    /// Deduplicates concurrent requests for the same bounding-box cell.
    private let deduplicator = InFlightDeduplicator<String, [OSMBuilding]>()

    // MARK: - Public API

    func fetchBuildings(
        in bbox: (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double),
        context: NSManagedObjectContext
    ) async -> [OSMBuilding] {
        if let cached = cachedBuildings(in: bbox, context: context) {
            return cached
        }

        let key = bboxKey(bbox)
        return (try? await deduplicator.deduplicate(key: key) {
            try await self.fetchFromArcGIS(bbox: bbox, context: context)
        }) ?? []
    }

    // MARK: - ArcGIS Network Request

    private func fetchFromArcGIS(
        bbox: (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double),
        context: NSManagedObjectContext
    ) async throws -> [OSMBuilding] {
        let geometryJSON = """
        {"xmin":\(bbox.minLon),"ymin":\(bbox.minLat),"xmax":\(bbox.maxLon),"ymax":\(bbox.maxLat),"spatialReference":{"wkid":4326}}
        """

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "geometry",     value: geometryJSON),
            URLQueryItem(name: "geometryType", value: "esriGeometryEnvelope"),
            URLQueryItem(name: "inSR",         value: "4326"),
            URLQueryItem(name: "outSR",        value: "4326"),
            URLQueryItem(name: "outFields",    value: "hl_bldght,OBJECTID"),
            URLQueryItem(name: "returnGeometry", value: "true"),
            URLQueryItem(name: "f",            value: "geojson"),
        ]

        guard let url = components.url else { throw ArcGISError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let buildings = try await withRetry(maxAttempts: 2, initialDelay: 1.0) {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ArcGISError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            return try self.parseGeoJSON(data)
        }

        await persistBuildings(buildings)
        return buildings
    }

    // MARK: - GeoJSON Parsing

    private func parseGeoJSON(_ data: Data) throws -> [OSMBuilding] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            throw ArcGISError.parseError
        }

        var buildings: [OSMBuilding] = []
        for feature in features {
            guard let properties = feature["properties"] as? [String: Any],
                  let geometry   = feature["geometry"]   as? [String: Any],
                  let typeStr    = geometry["type"]       as? String,
                  typeStr == "Polygon",
                  let rings      = geometry["coordinates"] as? [[[Double]]],
                  let outerRing  = rings.first,
                  outerRing.count >= 3 else { continue }

            // hl_bldght is in feet → convert to meters; minimum 3 m (one floor)
            let heightFeet   = (properties["hl_bldght"] as? Double) ?? 30.0
            let heightMeters = max(heightFeet * 0.3048, 3.0)

            // Negate OBJECTID to distinguish ArcGIS buildings from positive OSM IDs
            let objectID   = (properties["OBJECTID"] as? Int) ?? hashFromRing(outerRing)
            let buildingID = Int64(-abs(objectID))

            // GeoJSON coordinates are [longitude, latitude]
            let footprint: [CLLocationCoordinate2D] = outerRing.compactMap { pair in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
            guard footprint.count >= 3 else { continue }

            buildings.append(OSMBuilding(
                id: buildingID,
                footprint: footprint,
                heightMeters: heightMeters,
                centroid: computeCentroid(footprint)
            ))
        }
        return buildings
    }

    // MARK: - CoreData Cache (30-day TTL)

    private func cachedBuildings(
        in bbox: (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double),
        context: NSManagedObjectContext
    ) -> [OSMBuilding]? {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        let centerLat = (bbox.minLat + bbox.maxLat) / 2
        let centerLon = (bbox.minLon + bbox.maxLon) / 2
        let latRadius = (bbox.maxLat - bbox.minLat) / 2
        let lonRadius = (bbox.maxLon - bbox.minLon) / 2

        let request = BuildingGeometryEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "osmWayID < 0 AND centroidLatitude BETWEEN {%f, %f} AND centroidLongitude BETWEEN {%f, %f} AND fetchedAt > %@",
            centerLat - latRadius, centerLat + latRadius,
            centerLon - lonRadius, centerLon + lonRadius,
            thirtyDaysAgo as NSDate
        )
        guard let entities = try? context.fetch(request), !entities.isEmpty else { return nil }
        return entities.compactMap { OSMBuilding(entity: $0) }
    }

    private func persistBuildings(_ buildings: [OSMBuilding]) async {
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        await bgContext.perform {
            for building in buildings {
                _ = building.toEntity(context: bgContext)
            }
            try? bgContext.save()
        }
    }

    // MARK: - Helpers

    private func computeCentroid(_ coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let n = Double(coords.count)
        let latSum = coords.reduce(0.0) { $0 + $1.latitude }
        let lonSum = coords.reduce(0.0) { $0 + $1.longitude }
        return CLLocationCoordinate2D(latitude: latSum / n, longitude: lonSum / n)
    }

    /// Stable fallback ID from the first ring coordinate when OBJECTID is missing.
    private func hashFromRing(_ ring: [[Double]]) -> Int {
        guard let first = ring.first, first.count >= 2 else { return 0 }
        return abs(Int(first[0] * 1_000_000) ^ Int(first[1] * 1_000_000))
    }

    /// Cache key for the bounding-box cell (rounded to 0.01°, ≈1 km).
    private func bboxKey(_ bbox: (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double)) -> String {
        let lat = (((bbox.minLat + bbox.maxLat) / 2) * 100).rounded() / 100
        let lon = (((bbox.minLon + bbox.maxLon) / 2) * 100).rounded() / 100
        return "\(lat),\(lon)"
    }

    // MARK: - Errors

    enum ArcGISError: LocalizedError {
        case invalidURL
        case httpError(Int)
        case parseError

        var errorDescription: String? {
            switch self {
            case .invalidURL:       return "Invalid ArcGIS URL"
            case .httpError(let c): return "ArcGIS API returned status \(c)"
            case .parseError:       return "Failed to parse ArcGIS GeoJSON response"
            }
        }
    }
}
