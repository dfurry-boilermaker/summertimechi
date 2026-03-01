import Foundation
import CoreLocation
import CoreData

/// A building footprint retrieved from OpenStreetMap.
struct OSMBuilding: Identifiable, Hashable {
    let id: Int64  // OSM way ID
    var footprint: [CLLocationCoordinate2D]
    var heightMeters: Double
    var centroid: CLLocationCoordinate2D

    // MARK: - Height Resolution

    /// Chicago neighborhood default heights (meters) used when OSM has no height tag.
    enum ChicagoHeightDefault {
        static let loop: Double = 60.0
        static let riverNorth: Double = 30.0
        static let wickerPark: Double = 10.0
        static let general: Double = 10.0

        static func height(forNeighborhood neighborhood: String?) -> Double {
            guard let n = neighborhood?.lowercased() else { return general }
            if n.contains("loop") { return loop }
            if n.contains("river north") || n.contains("rivnorth") { return riverNorth }
            return general
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: OSMBuilding, rhs: OSMBuilding) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - BuildingGeometryEntity → OSMBuilding

extension OSMBuilding {
    init?(entity: BuildingGeometryEntity) {
        guard let data = entity.encodedCoordinates,
              let pairs = try? JSONDecoder().decode([[Double]].self, from: data),
              !pairs.isEmpty else {
            return nil
        }
        self.id = entity.osmWayID
        self.heightMeters = entity.heightMeters
        self.centroid = CLLocationCoordinate2D(
            latitude: entity.centroidLatitude,
            longitude: entity.centroidLongitude
        )
        self.footprint = pairs.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }

    func toEntity(context: NSManagedObjectContext) -> BuildingGeometryEntity {
        let entity = BuildingGeometryEntity(context: context)
        entity.osmWayID = id
        entity.heightMeters = heightMeters
        entity.centroidLatitude = centroid.latitude
        entity.centroidLongitude = centroid.longitude
        entity.fetchedAt = Date()
        let pairs = footprint.map { [$0.latitude, $0.longitude] }
        entity.encodedCoordinates = try? JSONEncoder().encode(pairs)
        return entity
    }
}
