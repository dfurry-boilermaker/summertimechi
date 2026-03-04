import Foundation
import CoreLocation
import CoreData

/// Lightweight in-memory bar model used throughout the app.
/// Backed by `BarEntity` in CoreData for persistence.
struct Bar: Identifiable, Hashable {
    let id: UUID
    var name: String
    var coordinate: CLLocationCoordinate2D
    var address: String?
    var neighborhood: String?
    var yelpID: String?
    var yelpURL: URL?
    var yelpRating: Double
    var yelpReviewCount: Int
    var hasPatioConfirmed: Bool
    var dataSourceMask: DataSourceMask
    var isFavorite: Bool
    var sunAlertsEnabled: Bool
    var cachedSunStatus: SunStatus?
    var cachedStatusTimestamp: Date?
    /// Operating hours from remote JSON (24h). Not persisted to CoreData.
    var openHour: Int?
    var closeHour: Int?

    /// Returns true if the bar is open at the given hour (24h). Nil hours = always open.
    func isOpen(atHour hour: Int) -> Bool {
        guard let open = openHour, let close = closeHour else { return true }
        if close > open {
            return hour >= open && hour < close
        } else {
            // Handles overnight bars e.g. open=20, close=2 → open 20:00–01:59
            return hour >= open || hour < close
        }
    }

    // MARK: - Data Source Bitmask

    struct DataSourceMask: OptionSet, Hashable {
        let rawValue: Int16
        static let cityPermit = DataSourceMask(rawValue: 1)
        static let osm        = DataSourceMask(rawValue: 2)
        static let yelp       = DataSourceMask(rawValue: 4)
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Bar, rhs: Bar) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - BarEntity → Bar

extension Bar {
    init(entity: BarEntity) {
        self.id = entity.id ?? UUID()
        self.name = entity.name ?? "Unknown Bar"
        self.coordinate = CLLocationCoordinate2D(
            latitude: entity.latitude,
            longitude: entity.longitude
        )
        self.address = entity.address
        self.neighborhood = entity.neighborhood
        self.yelpID = entity.yelpID
        self.yelpURL = entity.yelpID.flatMap { id in
            URL(string: "https://www.yelp.com/biz/\(id)")
        }
        self.yelpRating = entity.yelpRating
        self.yelpReviewCount = Int(entity.yelpReviewCount)
        self.hasPatioConfirmed = entity.hasPatioConfirmed
        self.dataSourceMask = DataSourceMask(rawValue: entity.dataSourceMask)
        self.isFavorite = entity.isFavorite
        self.sunAlertsEnabled = entity.sunAlertsEnabled
        self.cachedSunStatus = SunStatus(rawValue: entity.cachedSunStatus ?? "")
        self.cachedStatusTimestamp = entity.cachedStatusTimestamp
        // openHour/closeHour are overlaid from SeedDataService after loadBars()
        self.openHour = nil
        self.closeHour = nil
    }

    func apply(to entity: BarEntity) {
        entity.id = id
        entity.name = name
        entity.latitude = coordinate.latitude
        entity.longitude = coordinate.longitude
        entity.address = address
        entity.neighborhood = neighborhood
        entity.yelpID = yelpID
        entity.yelpRating = yelpRating
        entity.yelpReviewCount = Int32(yelpReviewCount)
        entity.hasPatioConfirmed = hasPatioConfirmed
        entity.dataSourceMask = dataSourceMask.rawValue
        entity.isFavorite = isFavorite
        entity.sunAlertsEnabled = sunAlertsEnabled
        entity.cachedSunStatus = cachedSunStatus?.rawValue
        entity.cachedStatusTimestamp = cachedStatusTimestamp
    }
}
