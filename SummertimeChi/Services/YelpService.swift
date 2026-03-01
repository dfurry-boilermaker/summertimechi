import Foundation
import CoreLocation

/// Fetches bar listings with outdoor seating from Yelp Fusion API.
/// Per Yelp ToS, the Yelp logo must be displayed alongside any Yelp data.
final class YelpService {
    static let shared = YelpService()
    private init() {}

    private let baseURL = "https://api.yelp.com/v3/businesses/search"
    private var apiKey: String {
        Bundle.main.infoDictionary?["YELP_API_KEY"] as? String ?? ""
    }

    // MARK: - Public API

    func fetchBars(in city: String = "Chicago, IL") async throws -> [Bar] {
        var allBars: [Bar] = []
        var offset = 0
        let limit = 50

        repeat {
            let batch = try await fetchPage(city: city, limit: limit, offset: offset)
            allBars.append(contentsOf: batch)
            offset += limit
            // Respect Yelp rate limits with a small delay between pages
            if !batch.isEmpty {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
        } while offset < 1000 && !allBars.isEmpty // Cap at 1000 results (Yelp max offset)

        return allBars
    }

    // MARK: - Pagination

    private func fetchPage(city: String, limit: Int, offset: Int) async throws -> [Bar] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "location",   value: city),
            URLQueryItem(name: "categories", value: "bars"),
            URLQueryItem(name: "limit",      value: String(limit)),
            URLQueryItem(name: "offset",     value: String(offset))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YelpError.networkError
        }
        guard httpResponse.statusCode != 401 else {
            throw YelpError.unauthorized
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw YelpError.httpError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(YelpSearchResponse.self, from: data)
        return decoded.businesses.compactMap { barFromYelpBusiness($0) }
    }

    private func barFromYelpBusiness(_ business: YelpBusiness) -> Bar? {
        guard let lat = business.coordinates?.latitude,
              let lon = business.coordinates?.longitude,
              let name = business.name else {
            return nil
        }

        let address = [
            business.location?.address1,
            business.location?.city,
            business.location?.state
        ].compactMap { $0 }.joined(separator: ", ")

        return Bar(
            id: UUID(),
            name: name,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            address: address.isEmpty ? nil : address,
            neighborhood: business.location?.neighborhood ?? business.location?.city,
            yelpID: business.id,
            yelpURL: business.url.flatMap { URL(string: $0) },
            yelpRating: business.rating ?? 0,
            yelpReviewCount: business.review_count ?? 0,
            hasPatioConfirmed: true, // filtered by outdoor_seating attribute
            dataSourceMask: .yelp,
            isFavorite: false,
            sunAlertsEnabled: false
        )
    }

    // MARK: - Errors

    enum YelpError: LocalizedError {
        case networkError
        case unauthorized
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .networkError:         return "Network request failed"
            case .unauthorized:         return "Invalid Yelp API key. Check Secrets.xcconfig."
            case .httpError(let code):  return "Yelp API returned status \(code)"
            }
        }
    }
}

// MARK: - Decodable Models

private struct YelpSearchResponse: Decodable {
    let businesses: [YelpBusiness]
    let total: Int?
}

private struct YelpBusiness: Decodable {
    let id: String?
    let name: String?
    let rating: Double?
    let review_count: Int?
    let url: String?
    let coordinates: YelpCoordinates?
    let location: YelpLocation?
}

private struct YelpCoordinates: Decodable {
    let latitude: Double?
    let longitude: Double?
}

private struct YelpLocation: Decodable {
    let address1: String?
    let city: String?
    let state: String?
    let neighborhood: String?
}
