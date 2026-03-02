import Foundation
import CoreLocation
import WeatherKit

/// Fetches cloud cover from Apple WeatherKit to override shadow calculations on overcast days.
///
/// Results are cached in memory for 10 minutes per ~1 km grid cell to avoid
/// redundant network calls when multiple views request the same location.
@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()
    private init() {}

    private let service = WeatherService_()

    struct WeatherConditions {
        let cloudCoverFraction: Double  // 0.0 (clear) to 1.0 (fully overcast)
        let conditionDescription: String
        let temperatureFahrenheit: Double?
        let fetchedAt: Date
    }

    private var cache: [String: WeatherConditions] = [:]
    private static let cacheTTL: TimeInterval = 10 * 60  // 10 minutes

    // MARK: - Public API

    /// Fetches current weather conditions for `coordinate`, returning a cached value
    /// if one exists that is less than 10 minutes old.
    func fetchConditions(for coordinate: CLLocationCoordinate2D) async -> WeatherConditions? {
        let key = cacheKey(for: coordinate)
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < Self.cacheTTL {
            return cached
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
            return conditions
        } catch {
            return cache[key]
        }
    }

    /// Returns the SunStatus override based on cloud cover.
    func sunStatusOverride(cloudCover: Double) -> SunStatus? {
        if cloudCover > 0.8 { return .cloudy }
        if cloudCover > 0.4 { return .partialSun }
        return nil
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
