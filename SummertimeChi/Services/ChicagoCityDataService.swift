import Foundation
import CoreLocation // CLLocationCoordinate2D

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

        guard var components = URLComponents(string: baseURL) else {
            throw CityDataError.parseError
        }
        // Only fetch records that already have coordinates — skip geocoding entirely
        // to avoid the 1.2 s/request delay that causes the app to hang.
        components.queryItems = [
            URLQueryItem(name: "$limit",  value: "5000"),
            URLQueryItem(name: "$where",  value: "latitude IS NOT NULL AND longitude IS NOT NULL"),
            URLQueryItem(name: "$select", value: "doing_business_as_name,address,latitude,longitude,ward")
        ]

        guard let url = components.url else { throw CityDataError.parseError }
        var request = URLRequest(url: url)
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

        return permits.compactMap { barFromPermit($0) }
    }

    private func barFromPermit(_ permit: SidewalkCafePermit) -> Bar? {
        guard let latStr = permit.latitude, let lonStr = permit.longitude,
              let lat = Double(latStr), let lon = Double(lonStr) else { return nil }

        return Bar(
            id: UUID(),
            name: permit.doing_business_as_name ?? "Unknown Business",
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            address: permit.address,
            neighborhood: permit.ward.map { "Ward \($0)" },
            yelpID: nil,
            yelpURL: nil,
            yelpRating: 0,
            yelpReviewCount: 0,
            hasPatioConfirmed: false, // permit confirms address/name only, not patio quality
            dataSourceMask: .cityPermit,
            isFavorite: false,
            sunAlertsEnabled: false
        )
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
