import Foundation
import CoreLocation

/// Fetches outdoor sidewalk cafe permit data from Chicago's Open Data Portal (SODA API).
/// Dataset: Sidewalk Cafe Permits (`nxj5-ix6z`)
/// Note: Dataset only contains data from March–December (permit season).
final class ChicagoCityDataService {
    static let shared = ChicagoCityDataService()
    private init() {}

    private let baseURL = "https://data.cityofchicago.org/resource/nxj5-ix6z.json"

    // MARK: - Public API

    func fetchPermits() async throws -> [Bar] {
        let appToken = Bundle.main.infoDictionary?["CHICAGO_APP_TOKEN"] as? String ?? ""
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "$limit", value: "5000"),
            URLQueryItem(name: "$select", value: "doing_business_as_name,address,latitude,longitude,ward,expiration_date")
        ]

        var request = URLRequest(url: components.url!)
        if !appToken.isEmpty {
            request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        }
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CityDataError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let permits = try? JSONDecoder().decode([SidewalkCafePermit].self, from: data) else {
            throw CityDataError.parseError
        }

        // Geocode entries with missing lat/lon (batched, max 50/min)
        return await geocodeAndConvert(permits: permits)
    }

    // MARK: - Geocoding

    private func geocodeAndConvert(permits: [SidewalkCafePermit]) async -> [Bar] {
        var bars: [Bar] = []
        let geocoder = CLGeocoder()
        var geocodedCount = 0

        for permit in permits {
            var latitude: Double?
            var longitude: Double?

            if let latStr = permit.latitude, let lonStr = permit.longitude,
               let lat = Double(latStr), let lon = Double(lonStr) {
                latitude = lat
                longitude = lon
            } else if let address = permit.address {
                // Rate limit: max ~50 geocode requests per minute
                if geocodedCount > 0 && geocodedCount % 50 == 0 {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                }
                if let placemark = try? await geocoder.geocodeAddressString(address + ", Chicago, IL").first,
                   let loc = placemark.location {
                    latitude = loc.coordinate.latitude
                    longitude = loc.coordinate.longitude
                    geocodedCount += 1
                } else {
                    // 1.2-second delay between individual geocode calls
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
            }

            guard let lat = latitude, let lon = longitude else { continue }

            bars.append(Bar(
                id: UUID(),
                name: permit.doing_business_as_name ?? "Unknown Business",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                address: permit.address,
                neighborhood: permit.ward.map { "Ward \($0)" },
                yelpID: nil,
                yelpURL: nil,
                yelpRating: 0,
                yelpReviewCount: 0,
                hasPatioConfirmed: true,
                dataSourceMask: .cityPermit,
                isFavorite: false,
                sunAlertsEnabled: false
            ))
        }
        return bars
    }

    // MARK: - Errors

    enum CityDataError: LocalizedError {
        case httpError(Int)
        case parseError

        var errorDescription: String? {
            switch self {
            case .httpError(let code): return "Chicago Open Data API returned status \(code)"
            case .parseError:          return "Failed to parse Chicago permit data"
            }
        }
    }
}

// MARK: - Decodable Models

private struct SidewalkCafePermit: Decodable {
    let doing_business_as_name: String?
    let address: String?
    let latitude: String?
    let longitude: String?
    let ward: String?
    let expiration_date: String?
}
