import Foundation
import CoreLocation
import WeatherKit

/// Fetches cloud cover from Apple WeatherKit to override shadow calculations on overcast days.
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

    // MARK: - Public API

    /// Fetches current weather conditions for a given coordinate.
    /// Returns `nil` if WeatherKit is unavailable or the request fails.
    func fetchConditions(for coordinate: CLLocationCoordinate2D) async -> WeatherConditions? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let weather = try await service.weather(for: location, including: .current)
            return WeatherConditions(
                cloudCoverFraction: weather.cloudCover,
                conditionDescription: weather.condition.description,
                temperatureFahrenheit: weather.temperature.converted(to: .fahrenheit).value,
                fetchedAt: Date()
            )
        } catch {
            // WeatherKit may fail in simulator; gracefully return nil
            return nil
        }
    }

    /// Returns the SunStatus override based on cloud cover.
    /// Returns `nil` if no override is needed (let shadow calc decide).
    func sunStatusOverride(cloudCover: Double) -> SunStatus? {
        if cloudCover > 0.8 { return .cloudy }
        if cloudCover > 0.4 { return .partialSun }
        return nil
    }
}

// Internal alias to avoid name collision with the class itself
private typealias WeatherService_ = WeatherKit.WeatherService
