import Foundation
import CoreLocation
import CoreData

/// Fetches bar listings and building footprints from OpenStreetMap via the Overpass API.
final class OSMService {
    static let shared = OSMService()
    private init() {}

    private let overpassURL = URL(string: "https://overpass-api.de/api/interpreter")!
    private let chicagoBBox = "41.64,-87.94,42.02,-87.52"

    /// Deduplicates concurrent building fetch requests for the same ~200m grid cell.
    private let buildingDeduplicator = InFlightDeduplicator<String, [OSMBuilding]>()

    // MARK: - Bar Query

    /// Fetches Chicago bars/pubs/biergarens with confirmed outdoor seating from OSM.
    func fetchBars() async throws -> [Bar] {
        let query = """
        [out:json][timeout:45];
        (
          node["amenity"~"^(bar|pub|biergarten)$"]["outdoor_seating"="yes"](\(chicagoBBox));
          way["amenity"~"^(bar|pub|biergarten)$"]["outdoor_seating"="yes"](\(chicagoBBox));
          node["amenity"="biergarten"](\(chicagoBBox));
          way["amenity"="biergarten"](\(chicagoBBox));
        );
        out center qt;
        """
        let elements = try await withRetry(maxAttempts: 3, initialDelay: 2.0) {
            try await self.runQuery(query)
        }
        return elements.compactMap { barFromElement($0) }
    }

    private func barFromElement(_ element: [String: Any]) -> Bar? {
        let lat: Double
        let lon: Double
        if let l = element["lat"] as? Double, let o = element["lon"] as? Double {
            lat = l; lon = o
        } else if let center = element["center"] as? [String: Double],
                  let l = center["lat"], let o = center["lon"] {
            lat = l; lon = o
        } else {
            return nil
        }

        guard let tags = element["tags"] as? [String: String] else { return nil }
        let name = tags["name"] ?? tags["brand"] ?? "Unnamed Bar"
        return Bar(
            id: UUID(),
            name: name,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            address: buildAddress(from: tags),
            neighborhood: tags["addr:suburb"] ?? tags["addr:neighborhood"],
            yelpID: nil,
            yelpURL: nil,
            yelpRating: 0,
            yelpReviewCount: 0,
            hasPatioConfirmed: true,
            dataSourceMask: .osm,
            isFavorite: false,
            sunAlertsEnabled: false
        )
    }

    private func buildAddress(from tags: [String: String]) -> String? {
        var parts: [String] = []
        if let num    = tags["addr:housenumber"] { parts.append(num) }
        if let street = tags["addr:street"]      { parts.append(street) }
        if let city   = tags["addr:city"]        { parts.append(city) }
        if let state  = tags["addr:state"]       { parts.append(state) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Building Query

    /// Fetches building footprints within 200 m of `coordinate`.
    ///
    /// Concurrent requests for the same ~200 m grid cell are deduplicated: only
    /// one Overpass request fires; all callers share its result.
    func fetchBuildings(
        near coordinate: CLLocationCoordinate2D,
        context: NSManagedObjectContext
    ) async throws -> [OSMBuilding] {
        if let cached = cachedBuildings(near: coordinate, context: context) {
            return cached
        }

        let key = gridKey(for: coordinate)
        return try await buildingDeduplicator.deduplicate(key: key) {
            try await self.fetchBuildingsFromOverpass(near: coordinate, context: context)
        }
    }

    private func fetchBuildingsFromOverpass(
        near coordinate: CLLocationCoordinate2D,
        context: NSManagedObjectContext
    ) async throws -> [OSMBuilding] {
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let query = """
        [out:json][timeout:30];
        (
          way["building"](around:200,\(lat),\(lon));
        );
        (._;>;);
        out body qt;
        """
        let elements = try await withRetry(maxAttempts: 2, initialDelay: 1.0) {
            try await self.runQuery(query)
        }
        let buildings = parseBuildingElements(elements, near: coordinate)

        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        await bgContext.perform {
            for building in buildings {
                let entity = BuildingGeometryEntity(context: bgContext)
                entity.osmWayID = building.id
                entity.heightMeters = building.heightMeters
                entity.centroidLatitude = building.centroid.latitude
                entity.centroidLongitude = building.centroid.longitude
                entity.fetchedAt = Date()
                let pairs = building.footprint.map { [$0.latitude, $0.longitude] }
                entity.encodedCoordinates = try? JSONEncoder().encode(pairs)
            }
            try? bgContext.save()
        }

        return buildings
    }

    private func cachedBuildings(
        near coordinate: CLLocationCoordinate2D,
        context: NSManagedObjectContext
    ) -> [OSMBuilding]? {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let radius = 0.002

        let request = BuildingGeometryEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "osmWayID > 0 AND centroidLatitude BETWEEN {%f, %f} AND centroidLongitude BETWEEN {%f, %f} AND fetchedAt > %@",
            coordinate.latitude - radius, coordinate.latitude + radius,
            coordinate.longitude - radius, coordinate.longitude + radius,
            sevenDaysAgo as NSDate
        )

        guard let entities = try? context.fetch(request), !entities.isEmpty else { return nil }
        return entities.compactMap { OSMBuilding(entity: $0) }
    }

    // MARK: - Grid Key (for deduplication)

    /// Returns a stable key for the ~200 m grid cell containing `coordinate`.
    private func gridKey(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude  * 500).rounded() / 500  // 0.002° ≈ 200 m
        let lon = (coordinate.longitude * 500).rounded() / 500
        return "\(lat),\(lon)"
    }

    // MARK: - Building Parsing

    private func parseBuildingElements(_ elements: [[String: Any]], near origin: CLLocationCoordinate2D) -> [OSMBuilding] {
        var nodeMap: [Int64: CLLocationCoordinate2D] = [:]
        for element in elements {
            guard let type = element["type"] as? String, type == "node",
                  let id = element["id"] as? Int,
                  let lat = element["lat"] as? Double,
                  let lon = element["lon"] as? Double else { continue }
            nodeMap[Int64(id)] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        var buildings: [OSMBuilding] = []
        for element in elements {
            guard let type = element["type"] as? String, type == "way",
                  let id = element["id"] as? Int,
                  let nodeIDs = element["nodes"] as? [Int] else { continue }

            let tags = element["tags"] as? [String: String] ?? [:]
            let coords = nodeIDs.compactMap { nodeMap[Int64($0)] }
            guard coords.count >= 3 else { continue }

            buildings.append(OSMBuilding(
                id: Int64(id),
                footprint: coords,
                heightMeters: resolveHeight(from: tags),
                centroid: computeCentroid(coords)
            ))
        }
        return buildings
    }

    private func resolveHeight(from tags: [String: String]) -> Double {
        if let heightStr = tags["height"],
           let height = Double(heightStr.replacingOccurrences(of: " m", with: "")) {
            return height
        }
        if let levelsStr = tags["building:levels"],
           let levels = Double(levelsStr) {
            return levels * 3.5
        }
        return OSMBuilding.ChicagoHeightDefault.general
    }

    private func computeCentroid(_ coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let n = Double(coords.count)
        let latSum = coords.reduce(0.0) { $0 + $1.latitude }
        let lonSum = coords.reduce(0.0) { $0 + $1.longitude }
        return CLLocationCoordinate2D(latitude: latSum / n, longitude: lonSum / n)
    }

    // MARK: - Overpass HTTP

    private func runQuery(_ query: String) async throws -> [[String: Any]] {
        var request = URLRequest(url: overpassURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")".data(using: .utf8)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OSMError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else {
            throw OSMError.parseError
        }
        return elements
    }

    // MARK: - Errors

    enum OSMError: LocalizedError {
        case httpError(Int)
        case parseError

        var errorDescription: String? {
            switch self {
            case .httpError(let code): return "Overpass API returned status \(code)"
            case .parseError:          return "Failed to parse Overpass API response"
            }
        }
    }
}
