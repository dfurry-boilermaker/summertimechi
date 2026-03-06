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

    // MARK: - Sunlight Hours

    /// Returns the number of hours the bar is open during daylight on the given date,
    /// or `nil` if operating hours are unknown. Uses the bar's own coordinates for
    /// sunrise/sunset so rooftop vs street-level differences across the city are captured.
    func sunlightHours(on date: Date, calendar: Calendar = .current) -> Double? {
        guard let open = openHour, let close = closeHour else { return nil }

        let solar = SolarCalculatorService.shared
        let (sunrise, sunset) = solar.sunriseSunset(at: coordinate, date: date)
        guard let rise = sunrise, let set = sunset else { return nil }

        let riseComps = calendar.dateComponents([.hour, .minute, .second], from: rise)
        let setComps  = calendar.dateComponents([.hour, .minute, .second], from: set)
        let sunriseH = Double(riseComps.hour ?? 0) + Double(riseComps.minute ?? 0) / 60.0
                      + Double(riseComps.second ?? 0) / 3600.0
        let sunsetH  = Double(setComps.hour ?? 0) + Double(setComps.minute ?? 0) / 60.0
                      + Double(setComps.second ?? 0) / 3600.0

        let openH  = Double(open)
        let closeH = Double(close)

        func overlap(_ a1: Double, _ a2: Double, _ b1: Double, _ b2: Double) -> Double {
            max(0, min(a2, b2) - max(a1, b1))
        }

        if close > open {
            return overlap(openH, closeH, sunriseH, sunsetH)
        } else {
            // Overnight hours split into [open, 24) and [0, close)
            let evening = overlap(openH, 24.0, sunriseH, sunsetH)
            let morning = overlap(0, closeH, sunriseH, sunsetH)
            return evening + morning
        }
    }

    /// Total operating hours per day (handles overnight wrap).
    var totalOpenHours: Double? {
        guard let open = openHour, let close = closeHour else { return nil }
        if close > open {
            return Double(close - open)
        } else {
            return Double(24 - open + close)
        }
    }

    /// Fraction of operating hours that fall during daylight (0.0–1.0), or `nil` if unknown.
    func sunlightFraction(on date: Date, calendar: Calendar = .current) -> Double? {
        guard let sun = sunlightHours(on: date, calendar: calendar),
              let total = totalOpenHours, total > 0 else { return nil }
        return min(sun / total, 1.0)
    }

    /// Human-readable summary, e.g. "6.5 hrs of sun" or "No daylight hours".
    func formattedSunlightHours(on date: Date, calendar: Calendar = .current) -> String? {
        guard let hours = sunlightHours(on: date, calendar: calendar) else { return nil }
        if hours < 0.1 { return "No daylight hours" }
        let rounded = (hours * 2).rounded() / 2   // round to nearest 0.5
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) hr\(Int(rounded) == 1 ? "" : "s") of sun"
        }
        return String(format: "%.1f hrs of sun", rounded)
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
