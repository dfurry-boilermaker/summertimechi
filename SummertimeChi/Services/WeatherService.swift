import Foundation
import CoreLocation
import WeatherKit

/// Fetches cloud cover from Apple WeatherKit to override shadow calculations on overcast days.
///
/// Results are cached in memory for 10 minutes per ~1 km grid cell to avoid
/// redundant network calls when multiple views request the same location.
///
/// **WeatherKit requires:**
/// - A physical device (does not work in Simulator)
/// - WeatherKit capability enabled for your App ID at developer.apple.com
/// - A provisioning profile that includes the WeatherKit entitlement
@MainActor
final class WeatherService {
    static let shared = WeatherService()
    private init() {}

    private let service = WeatherService_()

    struct WeatherConditions {
        let cloudCoverFraction: Double  // 0.0 (clear) to 1.0 (fully overcast)
        let conditionDescription: String
        let temperatureFahrenheit: Double?
        let fetchedAt: Date
    }

    /// Result of a weather fetch — either conditions or an error message for debugging.
    enum FetchResult {
        case success(WeatherConditions)
        case failure(String)
    }

    private var cache: [String: WeatherConditions] = [:]
    private static let cacheTTL: TimeInterval = 10 * 60  // 10 minutes

    // MARK: - Public API

    /// Fetches current weather conditions for `coordinate`, returning a cached value
    /// if one exists that is less than 10 minutes old.
    func fetchConditions(for coordinate: CLLocationCoordinate2D) async -> WeatherConditions? {
        switch await fetchConditionsWithResult(for: coordinate) {
        case .success(let conditions): return conditions
        case .failure: return nil
        }
    }

    /// Fetches weather and returns a result with success or error details (for debugging).
    func fetchConditionsWithResult(for coordinate: CLLocationCoordinate2D) async -> FetchResult {
        let key = cacheKey(for: coordinate)
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < Self.cacheTTL {
            return .success(cached)
        }
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.fetchedAt) < Self.cacheTTL }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let weather = try await service.weather(for: location, including: .current)
            let conditions = WeatherConditions(
                cloudCoverFraction: weather.cloudCover,
                conditionDescription: weather.condition.description,
                temperatureFahrenheit: weather.temperature.converted(to: .fahrenheit).value,
                fetchedAt: Date()
            )
            cache[key] = conditions
            return .success(conditions)
        } catch {
            if let cached = cache[key] { return .success(cached) }
            var message = error.localizedDescription
            if message.isEmpty, let wkError = error as? WeatherKit.WeatherError {
                message = String(describing: wkError)
            }
            if message.isEmpty { message = "Unknown error: \(type(of: error))" }
            print("[WeatherService] WeatherKit failed: \(message)")
            return .failure(message)
        }
    }

    /// Returns the SunStatus override based on cloud cover.
    func sunStatusOverride(cloudCover: Double) -> SunStatus? {
        if cloudCover > 0.4 { return .cloudy }
        return nil
    }

    /// Fetches hourly cloud cover for daylight hours only (sunrise–sunset), for use in sun/shade timeline.
    /// Returns `[hour: cloudCover]` where hour is 0–23 in the local calendar and cloudCover is 0.0–1.0.
    /// Returns `nil` on failure (caller should fall back to clear-sky).
    func fetchHourlyCloudCover(for coordinate: CLLocationCoordinate2D, date: Date) async -> [Int: Double]? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        let (sunrise, sunset) = SolarCalculatorService.shared.sunriseSunset(at: coordinate, date: date)
        let (startDate, endDate): (Date, Date) = if let sr = sunrise, let ss = sunset {
            (sr, ss)
        } else {
            // Polar day/night or fallback: request full day
            (startOfDay, startOfDay.addingTimeInterval(24 * 3600))
        }

        let key = "\(cacheKey(for: coordinate))_\(startOfDay.timeIntervalSince1970)"
        if let cached = hourlyCache[key], Date().timeIntervalSince(cached.fetchedAt) < Self.cacheTTL {
            return cached.cloudCoverByHour
        }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let forecast = try await service.weather(for: location, including: .hourly(startDate: startDate, endDate: endDate))
            var map: [Int: Double] = [:]
            for hourWeather in forecast.forecast {
                let h = calendar.component(.hour, from: hourWeather.date)
                map[h] = hourWeather.cloudCover
            }
            hourlyCache[key] = HourlyCacheEntry(cloudCoverByHour: map, fetchedAt: Date())
            purgeOldHourlyEntries()
            return map
        } catch {
            print("[WeatherService] Hourly forecast failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Cache entry for hourly cloud cover.
    private struct HourlyCacheEntry {
        let cloudCoverByHour: [Int: Double]
        let fetchedAt: Date
    }

    private var hourlyCache: [String: HourlyCacheEntry] = [:]

    private func purgeOldHourlyEntries() {
        let now = Date()
        hourlyCache = hourlyCache.filter { now.timeIntervalSince($0.value.fetchedAt) < Self.cacheTTL }
    }

    // MARK: - Cache

    /// Groups coordinates into ~1 km grid cells for cache deduplication.
    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = (coordinate.latitude  * 100).rounded() / 100  // 0.01° ≈ 1 km
        let lon = (coordinate.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
    }
}

// Internal alias to avoid name collision with the class itself
private typealias WeatherService_ = WeatherKit.WeatherService
