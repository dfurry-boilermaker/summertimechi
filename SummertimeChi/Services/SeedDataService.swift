import Foundation
import CoreLocation

struct SeedBarData {
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String
    let neighborhood: String
}

// MARK: - Remote JSON Models

private struct RemoteBarData: Codable {
    let version: Int
    let bars: [RemoteSeedBar]
    let sunOverrides: [RemoteSunOverride]?
}

private struct RemoteSeedBar: Codable {
    let name: String
    let lat: Double
    let lon: Double
    let address: String
    let neighborhood: String
    let openHour: Int?
    let closeHour: Int?
}

/// A manual sun status override for a specific bar during a range of hours.
/// Hours are 24-hour local time (Chicago). `fromHour` is inclusive, `toHour` is exclusive.
/// Example: fromHour=12, toHour=17, status="sunlit" → overrides 12:00–16:59.
private struct RemoteSunOverride: Codable {
    let barName: String
    let fromHour: Int   // 0–23, inclusive
    let toHour: Int     // 0–23, exclusive
    let status: String  // "sunlit" or "shaded"
}

// MARK: - Service

final class SeedDataService {
    static let shared = SeedDataService()

    /// Remote JSON URL — edit `Data/bars.json` in the GitHub repo to update without a new build.
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/dfurry-boilermaker/summertimechi/main/Data/bars.json")!

    private static var cacheFileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bars_remote_v1.json")
    }

    private var remoteData: RemoteBarData?

    private init() {
        loadCachedData()
    }

    // MARK: - Remote Refresh

    /// Fetches the latest bar list from GitHub and caches it to disk.
    /// Safe to call from any async context; updates take effect immediately.
    /// Returns `true` if the remote data was successfully fetched and applied.
    @MainActor
    @discardableResult
    func refreshFromRemote() async -> Bool {
        guard let (data, response) = try? await URLSession.shared.data(from: Self.remoteURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let fetched = try? JSONDecoder().decode(RemoteBarData.self, from: data) else {
            return false
        }
        try? data.write(to: Self.cacheFileURL, options: .atomic)
        remoteData = fetched
        return true
    }

    private func loadCachedData() {
        guard let data = try? Data(contentsOf: Self.cacheFileURL),
              let cached = try? JSONDecoder().decode(RemoteBarData.self, from: data) else { return }
        remoteData = cached
    }

    /// Removes the cached bars JSON so the next refresh fetches fresh data from GitHub.
    func clearCache() {
        try? FileManager.default.removeItem(at: Self.cacheFileURL)
    }

    // MARK: - Hours Lookup

    /// Returns operating hours for a bar by name (and optionally neighborhood for multi-location bars).
    func hours(forBarNamed name: String, neighborhood: String? = nil) -> (open: Int, close: Int)? {
        guard let bars = remoteData?.bars else { return nil }
        let match: RemoteSeedBar?
        if let nb = neighborhood, !nb.isEmpty {
            match = bars.first(where: { $0.name == name && $0.neighborhood == nb })
        } else {
            match = bars.first(where: { $0.name == name })
        }
        guard let m = match, let open = m.openHour, let close = m.closeHour else { return nil }
        return (open, close)
    }

    /// Returns the address for a bar by name (and optionally neighborhood for multi-location bars).
    func address(forBarNamed name: String, neighborhood: String? = nil) -> String? {
        guard let bars = remoteData?.bars else { return nil }
        let match: RemoteSeedBar?
        if let nb = neighborhood, !nb.isEmpty {
            match = bars.first(where: { $0.name == name && $0.neighborhood == nb })
        } else {
            match = bars.first(where: { $0.name == name })
        }
        guard let m = match, !m.address.isEmpty else { return nil }
        return m.address
    }

    // MARK: - Sun Override Lookup

    /// Returns a manually overridden sun status for the given bar at the given hour (24h local),
    /// or `nil` if no override applies. When non-nil, the caller should skip shadow computation.
    func sunOverride(forBarNamed name: String, atHour hour: Int) -> SunStatus? {
        guard let overrides = remoteData?.sunOverrides else { return nil }
        for entry in overrides where entry.barName == name {
            if hour >= entry.fromHour && hour < entry.toHour {
                return SunStatus(rawValue: entry.status)
            }
        }
        return nil
    }

    // MARK: - Public Data

    /// Bar names from the curated bars.json. Used to filter out stale CoreData entries.
    var curatedBarNames: Set<String> {
        guard let remote = remoteData else { return Set(hardcodedBars.map(\.name)) }
        return Set(remote.bars.map(\.name))
    }

    var curatedBars: [Bar] {
        let seeds: [SeedBarData]
        if let remote = remoteData {
            seeds = remote.bars.map {
                SeedBarData(name: $0.name, latitude: $0.lat, longitude: $0.lon,
                            address: $0.address, neighborhood: $0.neighborhood)
            }
        } else {
            seeds = hardcodedBars
        }
        let hoursByKey: [String: (Int, Int)] = remoteData.map { data in
            var dict: [String: (Int, Int)] = [:]
            for b in data.bars {
                guard let o = b.openHour, let c = b.closeHour else { continue }
                let key = b.neighborhood.isEmpty ? b.name : "\(b.name)|\(b.neighborhood)"
                dict[key] = (o, c)
            }
            return dict
        } ?? [:]

        return seeds.map { seed in
            let key = seed.neighborhood.isEmpty ? seed.name : "\(seed.name)|\(seed.neighborhood)"
            let h = hoursByKey[key]
            return Bar(
                id: UUID(),
                name: seed.name,
                coordinate: CLLocationCoordinate2D(latitude: seed.latitude, longitude: seed.longitude),
                address: seed.address.isEmpty ? nil : seed.address,
                neighborhood: seed.neighborhood,
                yelpID: nil,
                yelpURL: nil,
                yelpRating: 0,
                yelpReviewCount: 0,
                hasPatioConfirmed: true,
                dataSourceMask: .osm,
                isFavorite: false,
                sunAlertsEnabled: false,
                cachedSunStatus: nil,
                cachedStatusTimestamp: nil,
                openHour: h?.0,
                closeHour: h?.1
            )
        }
    }

    // 600 venues sourced from Chicago Patios map + Chi Bar Project (fallback if remote unavailable)
    private let hardcodedBars: [SeedBarData] = [
        SeedBarData(name: "City Winery Chicago", latitude: 41.884588, longitude: -87.6571111, address: "", neighborhood: "River West"),
        SeedBarData(name: "m.henry", latitude: 41.9856429, longitude: -87.6690756, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Bang Bang Pie & Biscuits", latitude: 41.9190185, longitude: -87.6971122, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Barcocina Lakeview", latitude: 41.934704, longitude: -87.6535878, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Ipsento 606", latitude: 41.9144273, longitude: -87.6832607, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Colectivo Coffee of Lincoln Park", latitude: 41.9286629, longitude: -87.64255, address: "", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Homeslice Pizza + Patio", latitude: 41.9219686, longitude: -87.6524768, address: "", neighborhood: "River West"),
        SeedBarData(name: "Hopleaf", latitude: 41.975817, longitude: -87.6685797, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Big Star", latitude: 41.9093725, longitude: -87.6772728, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Homestead On The Roof", latitude: 41.8961175, longitude: -87.675648, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Kaiser Tiger", latitude: 41.8838854, longitude: -87.663, address: "", neighborhood: "West Loop"),
        SeedBarData(name: "Cindy's Rooftop", latitude: 41.881662, longitude: -87.6249684, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Drew's on Halsted", latitude: 41.9401276, longitude: -87.6490726, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "El Jardin", latitude: 41.942726, longitude: -87.6527613, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Deuces Major League Bar", latitude: 41.945873, longitude: -87.6551795, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "The Dawson", latitude: 41.891371, longitude: -87.647252, address: "", neighborhood: "River West"),
        SeedBarData(name: "Small Cheval- Wicker Park", latitude: 41.9128179, longitude: -87.6815051, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Sidetrack", latitude: 41.9432557, longitude: -87.6491089, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Sheffield's Wine & Beer Garden", latitude: 41.941589, longitude: -87.6545179, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Maison Parisienne - French Café", latitude: 41.9420258, longitude: -87.6521259, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Lonesome Rose", latitude: 41.9196289, longitude: -87.6970688, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Royal Palms Chicago", latitude: 41.91305, longitude: -87.6820556, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Gene's Sausage Shop and Delicatessen", latitude: 41.9678232, longitude: -87.6883044, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Bistro Campagne", latitude: 41.9636039, longitude: -87.685707, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "LondonHouse Chicago, Curio Collection by Hilton", latitude: 41.8878318, longitude: -87.6254261, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Aba", latitude: 41.887005, longitude: -87.6488501, address: "", neighborhood: "River West"),
        SeedBarData(name: "George Street Pub", latitude: 41.9344118, longitude: -87.6492334, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "The Wiener's Circle", latitude: 41.9301746, longitude: -87.6437788, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Park & Field", latitude: 41.9242299, longitude: -87.7142944, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Parson's Chicken & Fish", latitude: 41.9265305, longitude: -87.6483828, address: "", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Parson's Chicken & Fish", latitude: 41.9176144, longitude: -87.7013261, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Parson's Chicken & Fish", latitude: 41.8957371, longitude: -87.6800025, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Parson's Chicken & Fish", latitude: 41.9861142, longitude: -87.669107, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Hexe Coffee Co.", latitude: 41.9325695, longitude: -87.6790478, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Old Crow Smokehouse - Wrigleyville", latitude: 41.945776, longitude: -87.655655, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Tanta Chicago", latitude: 41.8917705, longitude: -87.6320169, address: "", neighborhood: "River North"),
        SeedBarData(name: "The Galway Arms", latitude: 41.9266257, longitude: -87.6413218, address: "", neighborhood: "Lincoln Park"),
        SeedBarData(name: "The Waterfront Cafe", latitude: 41.9952591, longitude: -87.6547877, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Serai", latitude: 41.9206769, longitude: -87.6934715, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "DueLire Vino & Cucina", latitude: 41.9637792, longitude: -87.685528, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Pilot Project Brewing", latitude: 41.919946, longitude: -87.692981, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Volo Restaurant Wine Bar", latitude: 41.943401, longitude: -87.678866, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "RPM Seafood", latitude: 41.8879836, longitude: -87.6307625, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Lark", latitude: 41.9448838, longitude: -87.6491223, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Eden", latitude: 41.9429754, longitude: -87.6967306, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Cerise Rooftop", latitude: 41.8860366, longitude: -87.6259928, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Trader Todd's", latitude: 41.9404424, longitude: -87.6543697, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "The Dandy Crown", latitude: 41.8942026, longitude: -87.6525585, address: "", neighborhood: "River West"),
        SeedBarData(name: "Fiya", latitude: 41.9804581, longitude: -87.6680728, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Ranalli's Lincoln Park", latitude: 41.9173169, longitude: -87.6369621, address: "", neighborhood: "Lincoln Park"),
        SeedBarData(name: "J9 Wine Bar", latitude: 41.91775, longitude: -87.6483383, address: "", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Replay Andersonville", latitude: 41.979732, longitude: -87.668449, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Daily Bar & Grill", latitude: 41.9646474, longitude: -87.6861564, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Bacino's Italian Grill", latitude: 41.933573, longitude: -87.6354685, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Cody's Public House", latitude: 41.938063, longitude: -87.6708476, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Roscoe Village Pub", latitude: 41.9466082, longitude: -87.6832375, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Village Tap", latitude: 41.943072, longitude: -87.6805961, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Ludlow Liquors", latitude: 41.9355891, longitude: -87.6975375, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Begyle Brewing", latitude: 41.9552432, longitude: -87.6744982, address: "", neighborhood: "North Center"),
        SeedBarData(name: "Flo & Santos", latitude: 41.8653731, longitude: -87.6262352, address: "", neighborhood: "South Loop"),
        SeedBarData(name: "Grant Park Bistro", latitude: 41.8716758, longitude: -87.6244647, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Il Culaccino - Chicago Italian Restaurant", latitude: 41.853206, longitude: -87.622482, address: "", neighborhood: "South Loop"),
        SeedBarData(name: "Spoke & Bird Cafe (South Loop)", latitude: 41.857757, longitude: -87.6219582, address: "", neighborhood: "South Loop"),
        SeedBarData(name: "Bungalow by Middle Brow", latitude: 41.9177853, longitude: -87.6988914, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Clark Street Ale House - River North", latitude: 41.8960607, longitude: -87.6315373, address: "", neighborhood: "River North"),
        SeedBarData(name: "Weeds Tavern", latitude: 41.909967, longitude: -87.6492982, address: "", neighborhood: "Old Town"),
        SeedBarData(name: "Pizza Lobo Andersonville", latitude: 41.9814421, longitude: -87.6679379, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Moody's Pub", latitude: 41.9894408, longitude: -87.6605921, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "KOVAL Tasting Room", latitude: 41.9588329, longitude: -87.6734748, address: "", neighborhood: "North Center"),
        SeedBarData(name: "Burning Bush Brewery", latitude: 41.9546433, longitude: -87.6936031, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Will's Northwoods Inn", latitude: 41.9372595, longitude: -87.6590706, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Las Fuentes Lincoln Park", latitude: 41.9289583, longitude: -87.6491462, address: "", neighborhood: "Lincoln Park"),
        SeedBarData(name: "La Crêperie Chicago Restaurant", latitude: 41.9340989, longitude: -87.6455685, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "BienMeSabe Venezuelan Cafe & Restaurant", latitude: 41.9614123, longitude: -87.6706271, address: "", neighborhood: "North Center"),
        SeedBarData(name: "The Warbler", latitude: 41.9641823, longitude: -87.68551, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "The Dugout Bar", latitude: 41.9473973, longitude: -87.6539586, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Montrose Saloon", latitude: 41.9610574, longitude: -87.7023153, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Nighthawk", latitude: 41.9678997, longitude: -87.7135782, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Best Intentions", latitude: 41.9171619, longitude: -87.7101417, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Weegee's Lounge", latitude: 41.9170145, longitude: -87.7190122, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Golden Crust Pizza and Tap", latitude: 41.9653823, longitude: -87.7086975, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Small Cheval- Old Town", latitude: 41.9070399, longitude: -87.6339962, address: "", neighborhood: "Old Town"),
        SeedBarData(name: "Reggies Chicago", latitude: 41.853918, longitude: -87.6268523, address: "", neighborhood: "South Loop"),
        SeedBarData(name: "Kirkwood", latitude: 41.9354632, longitude: -87.654276, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Pilsen Yards", latitude: 41.8574584, longitude: -87.6556094, address: "", neighborhood: "Pilsen"),
        SeedBarData(name: "La Vaca Margarita Bar", latitude: 41.8581731, longitude: -87.6557236, address: "", neighborhood: "Pilsen"),
        SeedBarData(name: "Cleos Bar and Grill", latitude: 41.8958056, longitude: -87.676, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Hoosier Mama Pie Company", latitude: 41.8962148, longitude: -87.6680734, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Small Bar", latitude: 41.9355571, longitude: -87.7052853, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "WhirlyBall Chicago", latitude: 41.9212227, longitude: -87.6739273, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "The Dock at Montrose Beach", latitude: 41.964857, longitude: -87.63615, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Half Acre Beer Co", latitude: 41.980193, longitude: -87.681371, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Ravens", latitude: 41.9243411, longitude: -87.6401426, address: "", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Tatas Tacos - Cantina Lakeview", latitude: 41.9331007, longitude: -87.659729, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Chief O'Neill's Pub Restaurant Beer Garden", latitude: 41.9445802, longitude: -87.7055375, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "ERIS Brewery and Cider House", latitude: 41.9538878, longitude: -87.7342515, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Dovetail Brewery", latitude: 41.9562547, longitude: -87.6745423, address: "", neighborhood: "North Center"),
        SeedBarData(name: "Kimski", latitude: 41.8381507, longitude: -87.6509644, address: "", neighborhood: "Bronzeville"),
        SeedBarData(name: "Simone's", latitude: 41.8582389, longitude: -87.6510506, address: "", neighborhood: "Pilsen"),
        SeedBarData(name: "Humble Bar", latitude: 41.9103291, longitude: -87.7030043, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Honey Butter Fried Chicken", latitude: 41.9426262, longitude: -87.7027478, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Land & Lake Ravenswood", latitude: 41.9615931, longitude: -87.678721, address: "", neighborhood: "North Center"),
        SeedBarData(name: "Broken Barrel Bar", latitude: 41.9284581, longitude: -87.6636339, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Open Outcry Brewing Company", latitude: 41.694422, longitude: -87.68155, address: "", neighborhood: "Chicago"),
        SeedBarData(name: "Reggies on the Beach", latitude: 41.7813347, longitude: -87.573005, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "Cafe 53", latitude: 41.7993168, longitude: -87.5924045, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "Irish Nobleman Pub", latitude: 41.8932925, longitude: -87.662066, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Standing Passengers", latitude: 41.8962681, longitude: -87.6647176, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Uptown Taproom", latitude: 41.9650938, longitude: -87.6620846, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "The Moonlighter", latitude: 41.9177333, longitude: -87.7073667, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Spilt Milk", latitude: 41.9250565, longitude: -87.6972779, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "The Freeze", latitude: 41.9173444, longitude: -87.6981028, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Outside Voices", latitude: 41.917601, longitude: -87.7073905, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Scofflaw", latitude: 41.9172977, longitude: -87.7072039, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "The Welcome Back Lounge", latitude: 41.925347, longitude: -87.7011293, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "The Native", latitude: 41.9252358, longitude: -87.7009549, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Easy Does It", latitude: 41.9239719, longitude: -87.6994474, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Cafe Robey", latitude: 41.9106629, longitude: -87.6781234, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "GOLD STAR BAR", latitude: 41.9031389, longitude: -87.67205, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "HERBIVORE", latitude: 41.8381435, longitude: -87.6512729, address: "", neighborhood: "Bronzeville"),
        SeedBarData(name: "Le Midi Wine", latitude: 41.9033121, longitude: -87.6801256, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "The Perch Kitchen and Tap", latitude: 41.903357, longitude: -87.6762365, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Machine: Engineered Dining & Drink", latitude: 41.9033805, longitude: -87.6739614, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Sportsman's Club", latitude: 41.8989899, longitude: -87.6872016, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Kasama", latitude: 41.8996829, longitude: -87.6756519, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Star Bar Chicago", latitude: 41.8973014, longitude: -87.6866003, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Cescas Margarita Bar & Grill \"CMBG\"", latitude: 41.9800139, longitude: -87.668105, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Los Arcos", latitude: 41.9824571, longitude: -87.6682567, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Big Jones", latitude: 41.9794493, longitude: -87.6680875, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "The Embassy Public House", latitude: 41.8691015, longitude: -87.6630266, address: "", neighborhood: "Pilsen"),
        SeedBarData(name: "Paradise Park | Pizza & Patio", latitude: 41.9101936, longitude: -87.6756345, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Kennedy Rooftop", latitude: 41.9103888, longitude: -87.6672841, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Mama Delia", latitude: 41.9030013, longitude: -87.6708347, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Frontier", latitude: 41.9012771, longitude: -87.6634546, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "The Leavitt Street Inn & Tavern", latitude: 41.9240438, longitude: -87.6825284, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Nick's Beer Garden", latitude: 41.9089622, longitude: -87.6756515, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Cebu", latitude: 41.9102522, longitude: -87.6828802, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "The Delta", latitude: 41.9104595, longitude: -87.6718577, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Federales", latitude: 41.8853179, longitude: -87.652454, address: "", neighborhood: "River West"),
        SeedBarData(name: "Logan 11 Bar & Kitchen", latitude: 41.9226055, longitude: -87.6975158, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "SUNNYGUN", latitude: 41.8859054, longitude: -87.6452483, address: "", neighborhood: "River West"),
        SeedBarData(name: "The Duck Inn", latitude: 41.8444845, longitude: -87.6601684, address: "", neighborhood: "Pilsen"),
        SeedBarData(name: "Maria's Packaged Goods and Community Bar", latitude: 41.83811, longitude: -87.6510609, address: "", neighborhood: "Bronzeville"),
        SeedBarData(name: "Medici On 57th", latitude: 41.791276, longitude: -87.5937569, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "Heineken Pub97", latitude: 41.9476432, longitude: -87.6952227, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Reclaimed Bar & Restaurant", latitude: 41.9483221, longitude: -87.6879932, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "BiXi Beer", latitude: 41.9272468, longitude: -87.7039236, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Quality Time", latitude: 41.9322711, longitude: -87.7014615, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Beard & Belly", latitude: 41.9939584, longitude: -87.6601051, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Tapster Lincoln Park", latitude: 41.9287849, longitude: -87.6559709, address: "", neighborhood: "River West"),
        SeedBarData(name: "Boem restaurant", latitude: 41.9610642, longitude: -87.7260128, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Table, Donkey and Stick", latitude: 41.9176028, longitude: -87.6959949, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Colectivo Coffee at Logan Square", latitude: 41.9222334, longitude: -87.6959687, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Central Park Bar", latitude: 41.9344863, longitude: -87.7175804, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "Sleeping Village", latitude: 41.9394177, longitude: -87.7213611, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "The Whistler", latitude: 41.925377, longitude: -87.701037, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Pizza Lobo Logan Square", latitude: 41.9250499, longitude: -87.7025779, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "The Hi-Lo", latitude: 41.9015017, longitude: -87.6972267, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "GO Tavern & Liquors", latitude: 41.9172895, longitude: -87.7078111, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Resi's Bierstube", latitude: 41.9543768, longitude: -87.6801742, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Caffe Oliva", latitude: 41.8931081, longitude: -87.6128897, address: "", neighborhood: "River North"),
        SeedBarData(name: "Robert's Pizza and Dough Company", latitude: 41.8905699, longitude: -87.6164505, address: "", neighborhood: "River North"),
        SeedBarData(name: "Del Toro", latitude: 41.8532156, longitude: -87.6463013, address: "", neighborhood: "Pilsen"),
        SeedBarData(name: "Diner Grill", latitude: 41.9541179, longitude: -87.6705083, address: "", neighborhood: "North Center"),
        SeedBarData(name: "The Piggery", latitude: 41.9540201, longitude: -87.6700252, address: "", neighborhood: "North Center"),
        SeedBarData(name: "Murphy's Bleachers", latitude: 41.9489122, longitude: -87.6542088, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Fiesta Mexicana Restaurant", latitude: 41.9693431, longitude: -87.6599908, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Cary's Lounge", latitude: 41.9976609, longitude: -87.6869716, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Letizia's Natural Bakery", latitude: 41.9032769, longitude: -87.6814928, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Handlebar", latitude: 41.9101705, longitude: -87.685297, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Phyllis’ Musical Inn", latitude: 41.9034362, longitude: -87.6725435, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Parlor Pizza Bar Wicker Park", latitude: 41.9034035, longitude: -87.6734244, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Bluebird", latitude: 41.952492, longitude: -87.7672333, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Eggsperience Irving Park", latitude: 41.953177, longitude: -87.7509158, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Bàrbaro Taqueria", latitude: 41.9101064, longitude: -87.690782, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Gannon's Pub", latitude: 41.959435, longitude: -87.6827244, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "The Rambler Kitchen & Tap", latitude: 41.9567257, longitude: -87.6808462, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Baker Miller", latitude: 41.9663921, longitude: -87.6868274, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Cobblestone", latitude: 41.9605819, longitude: -87.6830807, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Zia's Social", latitude: 41.9933541, longitude: -87.8014231, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "The Garage Bar & Sandwiches", latitude: 41.9934311, longitude: -87.7844772, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Aire Rooftop Bar Chicago", latitude: 41.8809146, longitude: -87.6310919, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Sky Terrace Rooftop Lounge", latitude: 41.8931216, longitude: -87.6214532, address: "", neighborhood: "River North"),
        SeedBarData(name: "RAISED | An Urban Rooftop Bar", latitude: 41.8862369, longitude: -87.6283636, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Upstairs at The Gwen", latitude: 41.891259, longitude: -87.6253432, address: "", neighborhood: "River North"),
        SeedBarData(name: "Z Bar", latitude: 41.8959833, longitude: -87.6250762, address: "", neighborhood: "River North"),
        SeedBarData(name: "Terrace 16", latitude: 41.8888012, longitude: -87.6263094, address: "", neighborhood: "River North"),
        SeedBarData(name: "Mott St", latitude: 41.9071223, longitude: -87.6672277, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Smoke Daddy BBQ - Wicker Park", latitude: 41.9034379, longitude: -87.6726928, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Ten Cat Tavern", latitude: 41.9534445, longitude: -87.6687924, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Mi Tocaya Antojería", latitude: 41.9288865, longitude: -87.6976843, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Bryn Mawr Breakfast Club", latitude: 41.9387335, longitude: -87.7392414, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "The SoFo Tap", latitude: 41.9724308, longitude: -87.6676099, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Glenwood", latitude: 42.0084278, longitude: -87.6662917, address: "", neighborhood: "Rogers Park"),
        SeedBarData(name: "Ropa Cabana", latitude: 42.0106343, longitude: -87.6601883, address: "", neighborhood: "Rogers Park"),
        SeedBarData(name: "Tiztal Cafe", latitude: 41.966197, longitude: -87.6666762, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Bagel Miller", latitude: 41.9664, longitude: -87.6868295, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Big Chicks", latitude: 41.9740414, longitude: -87.6552187, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "El Mariachi Tequila Bar & Grill", latitude: 41.9530185, longitude: -87.6498309, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Tied House", latitude: 41.939548, longitude: -87.6635375, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Happy Camper Pizza - Wrigleyville", latitude: 41.9449962, longitude: -87.6548884, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "The Graystone Tavern", latitude: 41.9447886, longitude: -87.6540066, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Streeterville Social", latitude: 41.8900678, longitude: -87.6188832, address: "", neighborhood: "River North"),
        SeedBarData(name: "Long Room Chicago", latitude: 41.9544231, longitude: -87.6696958, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Bucktown Pub", latitude: 41.9161706, longitude: -87.6701707, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Fatso's Last Stand", latitude: 41.8959556, longitude: -87.6842456, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Twisted Spoke", latitude: 41.8912694, longitude: -87.6585722, address: "", neighborhood: "River West"),
        SeedBarData(name: "Midwest Coast Brewing Company", latitude: 41.8855511, longitude: -87.6807384, address: "", neighborhood: "West Loop"),
        SeedBarData(name: "Gordo's Tiny Taco Bar", latitude: 41.8854186, longitude: -87.6191139, address: "", neighborhood: "Streeterville"),
        SeedBarData(name: "Rosebud Randolph", latitude: 41.8847679, longitude: -87.6235178, address: "", neighborhood: "Loop"),
        SeedBarData(name: "The Avondale Tap", latitude: 41.9393889, longitude: -87.718787, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "Nicky's of Beverly", latitude: 41.7025342, longitude: -87.6817589, address: "", neighborhood: "Chicago"),
        SeedBarData(name: "Smoque BBQ", latitude: 41.9501327, longitude: -87.727667, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "La Nonna", latitude: 41.9429591, longitude: -87.7202261, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "Whiskey Business", latitude: 41.906828, longitude: -87.671423, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Barra Ñ", latitude: 41.9356577, longitude: -87.6925653, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "District Brew Yards", latitude: 41.8894087, longitude: -87.6667095, address: "", neighborhood: "West Loop"),
        SeedBarData(name: "Half Shell", latitude: 41.932969, longitude: -87.6465708, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "South Branch Tavern & Grille (The Loop - Chicago)", latitude: 41.8804843, longitude: -87.6377693, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Tre Kronor", latitude: 41.9758933, longitude: -87.7110012, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Mia Francesca", latitude: 41.9421927, longitude: -87.6521612, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "The Butcher’s Tap", latitude: 41.9467867, longitude: -87.663725, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Alma", latitude: 41.9473643, longitude: -87.6572615, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Willie Lill's Spirits & Kitchen", latitude: 41.9325526, longitude: -87.6407499, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "O's Tap", latitude: 41.9189333, longitude: -87.6877271, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Diversey House", latitude: 41.9320077, longitude: -87.6931263, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Sanders BBQ Supply Co", latitude: 41.7140233, longitude: -87.6671463, address: "", neighborhood: "Chicago"),
        SeedBarData(name: "Dark Matter Coffee - Osmium Coffee Bar", latitude: 41.9397066, longitude: -87.657306, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Franconello", latitude: 41.7075258, longitude: -87.68199, address: "", neighborhood: "Chicago"),
        SeedBarData(name: "Barraco's Pizza", latitude: 41.7208404, longitude: -87.6750974, address: "", neighborhood: "Chicago"),
        SeedBarData(name: "Alarmist Brewing & Taproom", latitude: 41.9898657, longitude: -87.7316169, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Sultan's Market", latitude: 41.9219705, longitude: -87.6975555, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Ascione Bistro", latitude: 41.7953227, longitude: -87.5886498, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "Southport Betty's", latitude: 41.9341505, longitude: -87.6637858, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Replay Lakeview", latitude: 41.9447863, longitude: -87.6492256, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Electric Funeral", latitude: 41.8298354, longitude: -87.6458289, address: "", neighborhood: "Bronzeville"),
        SeedBarData(name: "Elske", latitude: 41.8844672, longitude: -87.6609002, address: "", neighborhood: "West Loop"),
        SeedBarData(name: "Loafers Bar", latitude: 41.9687706, longitude: -87.6939651, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Gaoku Izakaya & Craft Drinks", latitude: 41.8991891, longitude: -87.6966567, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "IO Godfrey Rooftop Lounge", latitude: 41.8945972, longitude: -87.6319889, address: "", neighborhood: "River North"),
        SeedBarData(name: "Panchos Rooftop Cantina", latitude: 41.8774756, longitude: -87.6285532, address: "", neighborhood: "Loop"),
        SeedBarData(name: "TKS - Tatas Kitchen & Social", latitude: 41.9533195, longitude: -87.7696762, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Piccolo Sogno", latitude: 41.8908676, longitude: -87.6478939, address: "", neighborhood: "River West"),
        SeedBarData(name: "Chavas Tacos El Original", latitude: 41.8905006, longitude: -87.6855592, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Rex Tavern", latitude: 41.9705792, longitude: -87.7628823, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Mystic Rogue Irish pub and restaurant", latitude: 41.9913889, longitude: -87.7980556, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "The District House", latitude: 41.9715879, longitude: -87.7715309, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "The Brig", latitude: 41.967917, longitude: -87.7716254, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "The High Stool", latitude: 41.98148, longitude: -87.7623456, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Moretti's Ristorante & Pizzeria", latitude: 42.0028269, longitude: -87.8175636, address: "", neighborhood: "Rogers Park"),
        SeedBarData(name: "Max's Place", latitude: 41.9659318, longitude: -87.6667111, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Diego Mexican Restaurant", latitude: 41.8905025, longitude: -87.6591762, address: "", neighborhood: "River West"),
        SeedBarData(name: "Small Cheval - Hyde Park", latitude: 41.7993369, longitude: -87.5946436, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "MAHARI", latitude: 41.7954642, longitude: -87.5886482, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "Nella Pizza e Pasta", latitude: 41.794878, longitude: -87.5985437, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "Build Coffee", latitude: 41.7841599, longitude: -87.5905214, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "Community Tavern", latitude: 41.9541155, longitude: -87.7487216, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Mesler Kitchen | Bar | Lounge", latitude: 41.7994338, longitude: -87.5916013, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "D'Amato's Bakery", latitude: 41.8912922, longitude: -87.6556771, address: "", neighborhood: "River West"),
        SeedBarData(name: "Café Touché", latitude: 42.003559, longitude: -87.816943, address: "", neighborhood: "Rogers Park"),
        SeedBarData(name: "Butterfly Sushi Bar", latitude: 41.8909173, longitude: -87.656215, address: "", neighborhood: "River West"),
        SeedBarData(name: "Tempesta Market", latitude: 41.8912479, longitude: -87.6618113, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Sabroso! Mexican Grill", latitude: 41.8932267, longitude: -87.6674153, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Legno by Suparossa", latitude: 41.9584265, longitude: -87.7675452, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Tatas Tacos - Original Six Corners", latitude: 41.9531549, longitude: -87.7510565, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Flaco's Tacos", latitude: 41.8727352, longitude: -87.6289697, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Kasey's Tavern", latitude: 41.8733028, longitude: -87.6289909, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Metric", latitude: 41.8864901, longitude: -87.6783, address: "", neighborhood: "West Loop"),
        SeedBarData(name: "Jefferson Tap & Grille", latitude: 41.8875369, longitude: -87.6425399, address: "", neighborhood: "River West"),
        SeedBarData(name: "Candlelite Chicago", latitude: 42.0174602, longitude: -87.6905589, address: "", neighborhood: "Rogers Park"),
        SeedBarData(name: "Sauce & Bread Kitchen", latitude: 41.997515, longitude: -87.6706889, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Heritage Restaurant & Caviar Bar", latitude: 41.8959557, longitude: -87.6944326, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "The Walk In", latitude: 41.9308298, longitude: -87.7099462, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "La Boulangerie & Co Logan", latitude: 41.9277528, longitude: -87.7060819, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "The Monkey's Paw", latitude: 41.9278243, longitude: -87.6636453, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Little Goat Diner", latitude: 41.9423438, longitude: -87.6635606, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Green Street Local", latitude: 41.8795582, longitude: -87.6487722, address: "", neighborhood: "West Loop"),
        SeedBarData(name: "Two Hearted Queen", latitude: 41.9433093, longitude: -87.6592828, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Pingpong", latitude: 41.9425462, longitude: -87.6446476, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Afro Joes Coffee & Tea", latitude: 41.7142066, longitude: -87.6681594, address: "", neighborhood: "Chicago"),
        SeedBarData(name: "Cafe Korzo", latitude: 41.9359385, longitude: -87.6441187, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Dash of Salt and Pepper Diner", latitude: 41.9222606, longitude: -87.6440452, address: "", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Guthries Tavern", latitude: 41.9473109, longitude: -87.6617549, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Los Molcajetes", latitude: 41.9612428, longitude: -87.7170507, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Monsignor Murphy's", latitude: 41.9371401, longitude: -87.6441058, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "The Bad Apple", latitude: 41.959756, longitude: -87.682822, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "The VIG Chicago", latitude: 41.909915, longitude: -87.6344753, address: "", neighborhood: "Old Town"),
        SeedBarData(name: "Bokeh", latitude: 41.9672034, longitude: -87.708616, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Queen Mary", latitude: 41.9029715, longitude: -87.6807371, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Miku Sushi", latitude: 41.9635439, longitude: -87.6854695, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Angelo's Wine Bar", latitude: 41.9613729, longitude: -87.7043617, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Joy's Noodles & Rice", latitude: 41.9417746, longitude: -87.6442449, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Gideon Welles Craft Beer Bar & Kitchen", latitude: 41.9633317, longitude: -87.6852834, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Jerry's Sandwiches", latitude: 41.9677019, longitude: -87.68774, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "O'Shaughnessy's Public House", latitude: 41.9650497, longitude: -87.6738805, address: "", neighborhood: "North Center"),
        SeedBarData(name: "Half Sour", latitude: 41.872448, longitude: -87.630322, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Tapas Valencia", latitude: 41.8611004, longitude: -87.6274644, address: "", neighborhood: "South Loop"),
        SeedBarData(name: "Wolcott Tap", latitude: 41.9617122, longitude: -87.6758162, address: "", neighborhood: "North Center"),
        SeedBarData(name: "Bayan Ko", latitude: 41.96162, longitude: -87.674965, address: "", neighborhood: "North Center"),
        SeedBarData(name: "Rewired Pizza Cafe & Bar", latitude: 41.9901949, longitude: -87.6584932, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "O'Donovan's", latitude: 41.9543967, longitude: -87.6814438, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Burke's Public House", latitude: 41.9801139, longitude: -87.6596917, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Tweet", latitude: 41.9739945, longitude: -87.6552682, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Umai", latitude: 41.8725288, longitude: -87.6308608, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Sociale Chicago", latitude: 41.8717573, longitude: -87.630913, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Paisans Pizzeria", latitude: 41.8732967, longitude: -87.6307898, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Four Moon Tavern", latitude: 41.9430298, longitude: -87.6758638, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "First Draft", latitude: 41.8734567, longitude: -87.6305, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Rockwell's Neighborhood Grill", latitude: 41.9658519, longitude: -87.6938468, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Bitter Pops", latitude: 41.9431545, longitude: -87.6708106, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Basil Leaf Cafe", latitude: 41.9272732, longitude: -87.6413781, address: "", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Cesar's Killer Margaritas - Broadway", latitude: 41.9357037, longitude: -87.6444198, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Farm Bar", latitude: 41.9363515, longitude: -87.6614204, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "GEMINI", latitude: 41.919968, longitude: -87.640866, address: "", neighborhood: "Lincoln Park"),
        SeedBarData(name: "ROCKS lakeview", latitude: 41.9450508, longitude: -87.6456566, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "XOchimilco Mexican Restaurant", latitude: 41.9616808, longitude: -87.680264, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Old Pueblo Cantina", latitude: 41.9218607, longitude: -87.6584957, address: "", neighborhood: "River West"),
        SeedBarData(name: "Dom's Kitchen & Market", latitude: 41.9324289, longitude: -87.649256, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Happy Camper Pizza", latitude: 41.90428, longitude: -87.6343128, address: "", neighborhood: "River North"),
        SeedBarData(name: "Fireside Restaurant & Lounge", latitude: 41.986208, longitude: -87.6744778, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Lady Gregory's Irish Bar & Restaurant", latitude: 41.977892, longitude: -87.66856, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Ella Elli", latitude: 41.9451534, longitude: -87.6634667, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Andros Taverna", latitude: 41.9273607, longitude: -87.7048376, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Coda di Volpe", latitude: 41.9426398, longitude: -87.663589, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Colectivo Coffee of Andersonville", latitude: 41.9805961, longitude: -87.6681113, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Blue Line Lounge & Grill", latitude: 41.9095818, longitude: -87.6777204, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Corridor Brewery & Provisions", latitude: 41.9447567, longitude: -87.6641486, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Fish Bar", latitude: 41.9361475, longitude: -87.654148, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Avli Taverna", latitude: 41.9286547, longitude: -87.6623906, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Maison Marcel", latitude: 41.9381728, longitude: -87.644511, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Wakamono", latitude: 41.9424833, longitude: -87.6442806, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Esencia Urban Kitchen", latitude: 41.943171, longitude: -87.644568, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Pick Me Up Cafe", latitude: 41.9712284, longitude: -87.668092, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Le Sud Mediterranean Kitchen", latitude: 41.942847, longitude: -87.6858752, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Dear Margaret", latitude: 41.9358605, longitude: -87.6629129, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Vaughan's Pub", latitude: 41.9349966, longitude: -87.6537787, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Kie-Gol-Lanee", latitude: 41.9735653, longitude: -87.6550888, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Roscoe's Tavern", latitude: 41.9434929, longitude: -87.6495816, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Jake Melnick's Corner Tap", latitude: 41.895538, longitude: -87.6265138, address: "", neighborhood: "River North"),
        SeedBarData(name: "Jennivee's Bakery", latitude: 41.9419149, longitude: -87.6538832, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Wilde Bar & Restaurant", latitude: 41.9386917, longitude: -87.6445083, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Intelligentsia Coffee Broadway Coffeebar", latitude: 41.9382904, longitude: -87.644182, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Stella's Diner", latitude: 41.93776, longitude: -87.644538, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Tuman's Tap and Grill", latitude: 41.8956882, longitude: -87.6817697, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "West Town Bakery & Diner", latitude: 41.896158, longitude: -87.675407, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "All Together Now", latitude: 41.8956527, longitude: -87.680383, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Split-Rail", latitude: 41.8959317, longitude: -87.6895912, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Printer's Row Brewing", latitude: 41.967949, longitude: -87.7772749, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Tatas Tacos- Kitchen & Social", latitude: 41.9534232, longitude: -87.7696836, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Easy Street Pizza & Patio", latitude: 41.9541937, longitude: -87.7017427, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Portage Grounds", latitude: 41.9530632, longitude: -87.7647698, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Forno Rosso Pizzeria Napoletana", latitude: 41.8846823, longitude: -87.6541832, address: "", neighborhood: "River West"),
        SeedBarData(name: "Forno Rosso Pizzeria Napoletana", latitude: 41.947658, longitude: -87.806747, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "The Windsor Tavern and Grill", latitude: 41.9631659, longitude: -87.7569389, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Sutherlands", latitude: 41.9530117, longitude: -87.7617277, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Land & Lake Kitchen", latitude: 41.8877775, longitude: -87.6255015, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Forbidden Root Restaurant & Brewery", latitude: 41.896238, longitude: -87.671559, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "The Whale", latitude: 41.9254885, longitude: -87.7011997, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Lula Cafe", latitude: 41.9276583, longitude: -87.7067917, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Big Kids", latitude: 41.9278168, longitude: -87.706826, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Lardon", latitude: 41.9217938, longitude: -87.6974593, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Second Generation", latitude: 41.9279602, longitude: -87.7047721, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Websters Wine Bar Chicago", latitude: 41.9289723, longitude: -87.7069424, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Dos Urban Cantina", latitude: 41.9173333, longitude: -87.6984194, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Craft Pizza", latitude: 41.9048917, longitude: -87.6774336, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Innjoy", latitude: 41.9029882, longitude: -87.6792612, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Fatpour Tap Works - Wicker Park", latitude: 41.9029889, longitude: -87.6776167, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Gracie O' Malley's- Wicker Park", latitude: 41.911238, longitude: -87.6784739, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "DSTRKT Bar & Grill", latitude: 41.9093324, longitude: -87.6762451, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Lone Owl", latitude: 41.9097565, longitude: -87.6760519, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "The Fifty/50", latitude: 41.9029936, longitude: -87.6790664, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Cafe Istanbul", latitude: 41.903386, longitude: -87.6778378, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Little Wok - Wicker Park", latitude: 41.9033844, longitude: -87.6769543, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Little Wok - Lakeview", latitude: 41.9390403, longitude: -87.6444995, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Janik's Cafe", latitude: 41.9030212, longitude: -87.6777642, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Folklore | Argentine Restaurant", latitude: 41.9033182, longitude: -87.6798869, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Easy Bar", latitude: 41.9033373, longitude: -87.6766132, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Via Carducci La Sorella", latitude: 41.9033539, longitude: -87.6759751, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Little Victories", latitude: 41.9031501, longitude: -87.6709634, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Bangers & Lace Wicker Park", latitude: 41.903454, longitude: -87.670302, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Tortello", latitude: 41.9035048, longitude: -87.6718648, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Sushi Taku - Wicker Park", latitude: 41.9033716, longitude: -87.6751109, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Vincent", latitude: 41.9797424, longitude: -87.6677757, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Bar Roma", latitude: 41.9744963, longitude: -87.6680821, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Little Bad Wolf", latitude: 41.9833483, longitude: -87.6690624, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Uvae Kitchen and Wine Bar", latitude: 41.9833723, longitude: -87.6685482, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Yellowtail Sushi Bar & Asian Kitchen", latitude: 41.9387933, longitude: -87.6445207, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "DryHop Brewers", latitude: 41.9393174, longitude: -87.6441967, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "bartaco", latitude: 41.9115342, longitude: -87.6772531, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Ina Mae", latitude: 41.907664, longitude: -87.6721947, address: "", neighborhood: "Wicker Park"),
        SeedBarData(name: "Lottie's Pub", latitude: 41.9157902, longitude: -87.6761834, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Club Lucky", latitude: 41.9125167, longitude: -87.6736917, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Bronzeville Winery", latitude: 41.8142126, longitude: -87.6069235, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "Ja' Grill Hyde Park", latitude: 41.8004929, longitude: -87.5886243, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "Norman's Bistro", latitude: 41.8167265, longitude: -87.6016437, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "Daisy's Po-Boy and Tavern", latitude: 41.8004309, longitude: -87.5889202, address: "", neighborhood: "Hyde Park"),
        SeedBarData(name: "La Palapa", latitude: 41.832427, longitude: -87.675546, address: "", neighborhood: "Bronzeville"),
        SeedBarData(name: "5 Rabanitos Restaurante & Taqueria", latitude: 41.858, longitude: -87.6709447, address: "", neighborhood: "Pilsen"),
        SeedBarData(name: "Franco's Ristorante", latitude: 41.8383615, longitude: -87.6343646, address: "", neighborhood: "Bridgeport"),
        SeedBarData(name: "Turtle's Bar & Grill", latitude: 41.8346954, longitude: -87.6330665, address: "", neighborhood: "Bridgeport"),
        SeedBarData(name: "Al Bawadi Grill", latitude: 41.7338135, longitude: -87.8012114, address: "", neighborhood: "Chicago"),
        SeedBarData(name: "Jimmy's Pizza Cafe", latitude: 41.9615397, longitude: -87.690125, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Cafe Beograd", latitude: 41.9537535, longitude: -87.7021033, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Mima's Taste Of Cuba", latitude: 41.9537291, longitude: -87.7017075, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "El Cid", latitude: 41.9297305, longitude: -87.7072083, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "TIM TIM'S HALAL GRILL", latitude: 41.9610734, longitude: -87.7318769, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Navigator Taproom", latitude: 41.920928, longitude: -87.693845, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Mother's Ruin", latitude: 41.934971, longitude: -87.7164668, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "Sushi Taku-Logan Square", latitude: 41.9226034, longitude: -87.696516, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Longman & Eagle", latitude: 41.9300853, longitude: -87.7071462, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Reno", latitude: 41.9291558, longitude: -87.7071787, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Frank and Mary's Tavern", latitude: 41.9342697, longitude: -87.6905625, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Alulu Brewery and Pub", latitude: 41.854742, longitude: -87.6634119, address: "", neighborhood: "Pilsen"),
        SeedBarData(name: "The Bar on Buena", latitude: 41.9586012, longitude: -87.6535884, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Holiday Club", latitude: 41.954588, longitude: -87.654726, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "The Reservoir", latitude: 41.9620847, longitude: -87.6517652, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Michael's Original Pizzeria & Tavern", latitude: 41.9568838, longitude: -87.6517546, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Port & Park Bistro & Bar", latitude: 41.954514, longitude: -87.6644832, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Wrigleyville North", latitude: 41.9528615, longitude: -87.6547795, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "A Taste of Heaven", latitude: 41.9799916, longitude: -87.6680196, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Kopi Cafe", latitude: 41.9785917, longitude: -87.6681583, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Eggsperience Cafe - Lakeview", latitude: 41.9410085, longitude: -87.6442497, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Rogers Park Social", latitude: 42.0073911, longitude: -87.6662572, address: "", neighborhood: "Rogers Park"),
        SeedBarData(name: "Web Pub Bucktown", latitude: 41.9214968, longitude: -87.6788471, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Brownstone", latitude: 41.9533808, longitude: -87.6779202, address: "", neighborhood: "North Center"),
        SeedBarData(name: "ROCKS Northcenter", latitude: 41.9569889, longitude: -87.6809849, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Don Pedro Mexican Restaurant", latitude: 41.9558307, longitude: -87.6801799, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Kraken Sushi & Beyond", latitude: 41.9548156, longitude: -87.6888566, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "ROJO GUSANO", latitude: 41.9584455, longitude: -87.6736955, address: "", neighborhood: "North Center"),
        SeedBarData(name: "Mezcala Agave Bar & Kitchen", latitude: 41.9318979, longitude: -87.7002296, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Cafe Tola", latitude: 41.9475469, longitude: -87.6642316, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "D'Agostino's Pizza and Pub Wrigleyville", latitude: 41.9468886, longitude: -87.6636778, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Coalfire", latitude: 41.949185, longitude: -87.6637704, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Doña Tola", latitude: 41.950413, longitude: -87.6638338, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Tango Sur", latitude: 41.950742, longitude: -87.663864, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Sushi Mura", latitude: 41.9484917, longitude: -87.6638861, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Crosby's Kitchen", latitude: 41.9450902, longitude: -87.6637174, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Tuco And Blondie", latitude: 41.943315, longitude: -87.6640819, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "R Public House", latitude: 42.0162849, longitude: -87.6685864, address: "", neighborhood: "Rogers Park"),
        SeedBarData(name: "Jarvis Square Tavern", latitude: 42.0162636, longitude: -87.6684901, address: "", neighborhood: "Rogers Park"),
        SeedBarData(name: "Charmers Cafe", latitude: 42.0161854, longitude: -87.6683297, address: "", neighborhood: "Rogers Park"),
        SeedBarData(name: "Le Piano", latitude: 42.0087316, longitude: -87.6663314, address: "", neighborhood: "Rogers Park"),
        SeedBarData(name: "Spacca Napoli Pizzeria", latitude: 41.9631881, longitude: -87.6737274, address: "", neighborhood: "North Center"),
        SeedBarData(name: "Cafe El Tapatio", latitude: 41.943492, longitude: -87.66908, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Frasca Pizzeria & Wine Bar", latitude: 41.9432039, longitude: -87.6713328, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "PR Italian Bistro", latitude: 41.9530746, longitude: -87.6547562, address: "", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Fat Cat", latitude: 41.970098, longitude: -87.6599373, address: "", neighborhood: "Andersonville"),
        SeedBarData(name: "Rootstock Wine & Beer Bar", latitude: 41.8990434, longitude: -87.6970562, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "The Aberdeen Tap", latitude: 41.8901494, longitude: -87.6550042, address: "", neighborhood: "River West"),
        SeedBarData(name: "Wildberry Pancakes & Cafe", latitude: 41.8847209, longitude: -87.6228606, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Avli River North", latitude: 41.8949625, longitude: -87.6344994, address: "", neighborhood: "River North"),
        SeedBarData(name: "Carlucci Restaurant Chicago", latitude: 41.8846725, longitude: -87.6170409, address: "", neighborhood: "Streeterville"),
        SeedBarData(name: "Tacos Tequilas", latitude: 41.9344223, longitude: -87.7158281, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "Crawford's Food & Spirits", latitude: 41.9410966, longitude: -87.7264423, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "La Celia Latin Kitchen", latitude: 41.9337552, longitude: -87.7154691, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "The Aviary", latitude: 41.8865074, longitude: -87.6519833, address: "", neighborhood: "River West"),
        SeedBarData(name: "Five Star Bar", latitude: 41.896379, longitude: -87.6634469, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Breakfast House", latitude: 41.9387598, longitude: -87.7454079, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "Dunning Pour House", latitude: 41.9453574, longitude: -87.8204284, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "Breakfast House", latitude: 41.9361711, longitude: -87.6681863, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Cafe Urbano", latitude: 41.956658, longitude: -87.7238115, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Sfera Sicilian Street Food", latitude: 41.9871154, longitude: -87.6598145, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Regalia bar & restaurant", latitude: 41.9906259, longitude: -87.6600204, address: "", neighborhood: "Edgewater"),
        SeedBarData(name: "Itoko", latitude: 41.9422969, longitude: -87.6636994, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Oak and Honey", latitude: 41.9384546, longitude: -87.6446285, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Strapoli Pizzeria", latitude: 41.9326967, longitude: -87.643098, address: "", neighborhood: "Lake View"),
        SeedBarData(name: "Cara Cara Club", latitude: 41.9277119, longitude: -87.7067453, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "Avenue Tap and Kitchen", latitude: 41.9435579, longitude: -87.6709717, address: "", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Tryzub Ukrainian Kitchen", latitude: 41.8956611, longitude: -87.6821111, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Chile Toreado", latitude: 41.8305054, longitude: -87.6762836, address: "", neighborhood: "Bronzeville"),
        SeedBarData(name: "Maplewood Brewery & Distillery", latitude: 41.930889, longitude: -87.6913468, address: "", neighborhood: "Logan Square"),
        SeedBarData(name: "The Harding Tavern", latitude: 41.9307704, longitude: -87.7103996, address: "", neighborhood: "Avondale"),
        SeedBarData(name: "Smack Dab Chicago", latitude: 42.0044516, longitude: -87.6731663, address: "", neighborhood: "Rogers Park"),
        SeedBarData(name: "Red June Cafe", latitude: 41.9183072, longitude: -87.682681, address: "", neighborhood: "Bucktown"),
        SeedBarData(name: "Printers Row Wine Bar and Shop", latitude: 41.8729785, longitude: -87.629016, address: "", neighborhood: "Loop"),
        SeedBarData(name: "Gracie O'Malley's Portage Park", latitude: 41.9543621, longitude: -87.7492787, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Moonflower", latitude: 41.9603178, longitude: -87.7540484, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Junebug Cafe Six Corners", latitude: 41.9541593, longitude: -87.7487733, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Simòn Tacos", latitude: 41.9586767, longitude: -87.752287, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Las Tablas", latitude: 41.9536111, longitude: -87.7508333, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "BRGRBELLY", latitude: 41.9529851, longitude: -87.7709558, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Uncle Mike's Place", latitude: 41.8910764, longitude: -87.6699019, address: "", neighborhood: "Noble Square"),
        SeedBarData(name: "Filonek's Bar and Grill", latitude: 41.9942708, longitude: -87.7844894, address: "", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Liberation Kitchen", latitude: 41.890979, longitude: -87.679076, address: "", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Rebel & Rye", latitude: 41.891395, longitude: -87.6470038, address: "", neighborhood: "River West"),
        SeedBarData(name: "Maxwells Trading", latitude: 41.8876644, longitude: -87.6652479, address: "", neighborhood: "West Loop"),
        SeedBarData(name: "Alcock's", latitude: 41.8764187, longitude: -87.6335258, address: "411 S. Wells St.", neighborhood: "Loop"),
        SeedBarData(name: "Franklin Tap", latitude: 41.8777297, longitude: -87.6350867, address: "325 S. Franklin St.", neighborhood: "Loop"),
        SeedBarData(name: "Green at Grant Park", latitude: 41.8809677, longitude: -87.6198472, address: "352 E. Monroe St.", neighborhood: "Loop"),
        SeedBarData(name: "Lloyd's Chicago", latitude: 41.8815863, longitude: -87.636141, address: "1 S. Wacker Dr.", neighborhood: "Loop"),
        SeedBarData(name: "Poag Mahone's", latitude: 41.877664, longitude: -87.6336054, address: "333 S. Wells St.", neighborhood: "Loop"),
        SeedBarData(name: "Rivers", latitude: 41.8808631, longitude: -87.6375286, address: "30 S. Wacker Dr.", neighborhood: "Loop"),
        SeedBarData(name: "Salseria Cantina & Grill", latitude: 41.8787381, longitude: -87.6359612, address: "233 S. Wacker Dr.", neighborhood: "Loop"),
        SeedBarData(name: "Athena Restaurant", latitude: 41.8787225, longitude: -87.6476234, address: "212 S. Halsted St.", neighborhood: "Greektown"),
        SeedBarData(name: "Bottom Lounge", latitude: 41.8851506, longitude: -87.6618035, address: "1375 W. Lake St.", neighborhood: "West Loop"),
        SeedBarData(name: "Fulton Lounge", latitude: 41.8864563, longitude: -87.6520185, address: "955 W. Fulton Mkt.", neighborhood: "West Loop"),
        SeedBarData(name: "Greek Islands", latitude: 41.8789853, longitude: -87.6475092, address: "200 S. Halsted St.", neighborhood: "Greektown"),
        SeedBarData(name: "Pegasus Restaurant & Taverna", latitude: 41.8800805, longitude: -87.6474185, address: "130 S. Halsted St.", neighborhood: "Greektown"),
        SeedBarData(name: "Union Park", latitude: 41.878113, longitude: -87.657139, address: "228 S. Racine Ave.", neighborhood: "West Loop"),
        SeedBarData(name: "Blackie's", latitude: 41.8724347, longitude: -87.630304, address: "755 S. Clark St.", neighborhood: "South Loop"),
        SeedBarData(name: "Hackney's", latitude: 41.8729784, longitude: -87.6290456, address: "733 S. Dearborn St.", neighborhood: "South Loop"),
        SeedBarData(name: "Via Ventuno", latitude: 41.8540264, longitude: -87.6256347, address: "2110 S. Wabash Ave.", neighborhood: "South Loop"),
        SeedBarData(name: "Flatwater", latitude: 41.8881696, longitude: -87.6306139, address: "321 N. Clark St.", neighborhood: "River North"),
        SeedBarData(name: "Fulton's on the River", latitude: 41.8878923, longitude: -87.6323948, address: "315 N. LaSalle St.", neighborhood: "River North"),
        SeedBarData(name: "Gilt Bar", latitude: 41.8892822, longitude: -87.6351136, address: "230 W. Kinzie St.", neighborhood: "River North"),
        SeedBarData(name: "Joynt", latitude: 41.8938569, longitude: -87.6299761, address: "650 N. Dearborn St.", neighborhood: "River North"),
        SeedBarData(name: "Kerryman", latitude: 41.8941753, longitude: -87.6309917, address: "661 N. Clark St.", neighborhood: "River North"),
        SeedBarData(name: "Martini Ranch", latitude: 41.896328, longitude: -87.6362385, address: "311 W. Chicago Ave.", neighborhood: "River North"),
        SeedBarData(name: "Naniwa", latitude: 41.8927063, longitude: -87.6337894, address: "607 N. Wells St.", neighborhood: "River North"),
        SeedBarData(name: "Rock Bottom", latitude: 41.8914012, longitude: -87.6284125, address: "1 W. Grand Ave.", neighborhood: "River North"),
        SeedBarData(name: "Pippin's Tavern", latitude: 41.8970321, longitude: -87.6259225, address: "806 N. Rush St.", neighborhood: "Gold Coast"),
        SeedBarData(name: "Rosebud on Rush", latitude: 41.895595, longitude: -87.6258346, address: "720 N. Rush St.", neighborhood: "Gold Coast"),
        SeedBarData(name: "Burton Place", latitude: 41.9090324, longitude: -87.6343154, address: "1447 N. Wells St.", neighborhood: "Old Town"),
        SeedBarData(name: "Fireplace Inn", latitude: 41.9090911, longitude: -87.6349971, address: "1448 N. Wells St.", neighborhood: "Old Town"),
        SeedBarData(name: "Orso's", latitude: 41.9077806, longitude: -87.6343086, address: "1401 N. Wells St.", neighborhood: "Old Town"),
        SeedBarData(name: "Topo Gigio Ristorante", latitude: 41.9096419, longitude: -87.6349973, address: "1516 N. Wells St.", neighborhood: "Old Town"),
        SeedBarData(name: "Joe's", latitude: 41.9101115, longitude: -87.6521126, address: "940 W. Weed St.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Red Canary", latitude: 41.8945638, longitude: -87.6526456, address: "695 N. Milwaukee Ave.", neighborhood: "River West"),
        SeedBarData(name: "Corcoran's Grill & Pub", latitude: 41.9115994, longitude: -87.6340281, address: "1615 N. Wells St.", neighborhood: "Old Town"),
        SeedBarData(name: "Twin Anchors", latitude: 41.9127037, longitude: -87.6383321, address: "1655 N. Sedgwick St.", neighborhood: "Old Town"),
        SeedBarData(name: "Castaways", latitude: 41.914957, longitude: -87.6263188, address: "1603 N. Lake Shore Dr.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Forno Diablo", latitude: 41.9325882, longitude: -87.6407578, address: "433 W. Diversey Pkwy.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "John Barleycorn", latitude: 41.9237973, longitude: -87.6461095, address: "658 W. Belden Ave.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Manhandler", latitude: 41.9174001, longitude: -87.6487959, address: "1948 N. Halsted St.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Mickey's", latitude: 41.9268031, longitude: -87.6415082, address: "2450 N. Clark St.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Pars Cove", latitude: 41.9325882, longitude: -87.6408456, address: "435 W. Diversey Pkwy.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Café Ba-Ba-Reeba!", latitude: 41.9189677, longitude: -87.6488891, address: "2024 N. Halsted St.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Clybar and Grille", latitude: 41.9257458, longitude: -87.6698008, address: "2417 N. Clybourn Ave.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "King Crab Tavern", latitude: 41.9143547, longitude: -87.6486669, address: "1816 N. Halsted St.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Tripoli Tap", latitude: 41.9179216, longitude: -87.6571757, address: "1147 W. Armitage Ave.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Lincoln Station", latitude: 41.9261095, longitude: -87.650008, address: "2432 N. Lincoln Ave.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Seven Ten Lounge", latitude: 41.9316698, longitude: -87.6573105, address: "2747 N. Lincoln Ave.", neighborhood: "Lincoln Park"),
        SeedBarData(name: "Duke of Perth", latitude: 41.93525, longitude: -87.646598, address: "2913 N. Clark St.", neighborhood: "Lake View"),
        SeedBarData(name: "El Nuevo Mexicano", latitude: 41.9353036, longitude: -87.6471628, address: "2914 N. Clark St.", neighborhood: "Lake View"),
        SeedBarData(name: "F.O. Mahony's", latitude: 41.9494171, longitude: -87.6483014, address: "3701 N. Broadway", neighborhood: "Lake View"),
        SeedBarData(name: "Mayan Palace", latitude: 41.9317245, longitude: -87.6486746, address: "2703 N. Halsted St.", neighborhood: "Lake View"),
        SeedBarData(name: "Renaldi's Pizza", latitude: 41.9338338, longitude: -87.6443079, address: "2827 N. Broadway", neighborhood: "Lake View"),
        SeedBarData(name: "Café Orchid", latitude: 41.9470147, longitude: -87.6731341, address: "1746 W. Addison St.", neighborhood: "Lake View"),
        SeedBarData(name: "Grand River", latitude: 41.9367709, longitude: -87.6649807, address: "3032 N. Lincoln Ave.", neighborhood: "Lake View"),
        SeedBarData(name: "Hungry Brain", latitude: 41.9392772, longitude: -87.6864288, address: "2319 W. Belmont Ave.", neighborhood: "Lake View"),
        SeedBarData(name: "Matilda", latitude: 41.9382088, longitude: -87.6538954, address: "3101 N. Sheffield Ave.", neighborhood: "Lake View"),
        SeedBarData(name: "Pour Drinks & Eats", latitude: 41.9432168, longitude: -87.6690575, address: "3358 N. Ashland Ave.", neighborhood: "Lake View"),
        SeedBarData(name: "Union", latitude: 41.9344071, longitude: -87.6492749, address: "2858 N. Halsted St.", neighborhood: "Lake View"),
        SeedBarData(name: "Witt's", latitude: 41.93485, longitude: -87.6615865, address: "2913 N. Lincoln Ave.", neighborhood: "Lake View"),
        SeedBarData(name: "Bernie's Tap & Grill", latitude: 41.9487946, longitude: -87.6581049, address: "3664 N. Clark St.", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Casey Moran's", latitude: 41.9486558, longitude: -87.6580598, address: "3660 N. Clark St.", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Cubby Bear", latitude: 41.9469428, longitude: -87.6566341, address: "1059 W. Addison St.", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Dark Horse Tap & Grill", latitude: 41.944868, longitude: -87.6540224, address: "3443 N. Sheffield Ave.", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Deleece Grill Pub", latitude: 41.9421958, longitude: -87.6523157, address: "3313 N. Clark St.", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Goose Island Wrigleyville", latitude: 41.9460496, longitude: -87.6554599, address: "3535 N. Clark St.", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Mullen's on Clark", latitude: 41.9460022, longitude: -87.6554217, address: "3527 N. Clark St.", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Piano Man", latitude: 41.9512414, longitude: -87.6595104, address: "3801 N. Clark St.", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Redmond's", latitude: 41.9428003, longitude: -87.6543055, address: "3358 N. Sheffield Ave.", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Vines on Clark", latitude: 41.9466762, longitude: -87.6562226, address: "3554 N. Clark St.", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Yak-zies on Clark", latitude: 41.9493082, longitude: -87.6584942, address: "3710 N. Clark St.", neighborhood: "Wrigleyville"),
        SeedBarData(name: "Bucks Saloon", latitude: 41.9447878, longitude: -87.6491698, address: "3439 N. Halsted St.", neighborhood: "Boystown"),
        SeedBarData(name: "Halsted's Bar + Grill", latitude: 41.944889, longitude: -87.6492509, address: "3441 N. Halsted St.", neighborhood: "Boystown"),
        SeedBarData(name: "Blue Bayou", latitude: 41.9499649, longitude: -87.6644599, address: "3734 N. Southport Ave.", neighborhood: "Lake View"),
        SeedBarData(name: "Justin's", latitude: 41.9433087, longitude: -87.6640752, address: "3358 N. Southport Ave.", neighborhood: "Lake View"),
        SeedBarData(name: "Mystic Celt", latitude: 41.9447252, longitude: -87.6635883, address: "3443 N. Southport Ave.", neighborhood: "Lake View"),
        SeedBarData(name: "Schoolyard Tavern", latitude: 41.941467, longitude: -87.6641554, address: "3258 N. Southport Ave.", neighborhood: "Lake View"),
        SeedBarData(name: "Southport Lanes", latitude: 41.9423668, longitude: -87.6637206, address: "3325 N. Southport Ave.", neighborhood: "Lake View"),
        SeedBarData(name: "Beat Kitchen", latitude: 41.9397346, longitude: -87.6809524, address: "2100 W. Belmont Ave.", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Kitsch'n on Roscoe", latitude: 41.9430031, longitude: -87.6787943, address: "2005 W. Roscoe St.", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Que Rico", latitude: 41.9428539, longitude: -87.6858857, address: "2301 W. Roscoe St.", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Riverview Tavern", latitude: 41.9433545, longitude: -87.6782948, address: "1958 W. Roscoe St.", neighborhood: "Roscoe Village"),
        SeedBarData(name: "Chicago Joe's", latitude: 41.9541508, longitude: -87.6853332, address: "2256 W. Irving Park Rd.", neighborhood: "North Center"),
        SeedBarData(name: "Jury's", latitude: 41.9605977, longitude: -87.6830261, address: "4337 N. Lincoln Ave.", neighborhood: "North Center"),
        SeedBarData(name: "Laschet's Inn", latitude: 41.9538877, longitude: -87.6819932, address: "2119 W. Irving Park Rd.", neighborhood: "North Center"),
        SeedBarData(name: "Bowman's Bar", latitude: 41.9611831, longitude: -87.6840178, address: "4356 N. Leavitt St.", neighborhood: "Lincoln Square"),
        SeedBarData(name: "Bistro Compagne", latitude: 41.9636419, longitude: -87.6856278, address: "4518 N. Lincoln Ave.", neighborhood: "Lincoln Square"),
        SeedBarData(name: "O'Shaughnessy's Pub", latitude: 41.9650164, longitude: -87.673635, address: "4557 N. Ravenswood Ave.", neighborhood: "Ravenswood"),
        SeedBarData(name: "Ravenswood Pub", latitude: 41.9813329, longitude: -87.6742489, address: "5455 N. Ravenswood Ave.", neighborhood: "Ravenswood"),
        SeedBarData(name: "Sunnyside Tap", latitude: 41.9617109, longitude: -87.6889938, address: "4410 N. Western Ave.", neighborhood: "Ravenswood"),
        SeedBarData(name: "Spot", latitude: 41.9628158, longitude: -87.6554539, address: "4437 N. Broadway", neighborhood: "Uptown"),
        SeedBarData(name: "Anteprima", latitude: 41.9785777, longitude: -87.6684866, address: "5316 N. Clark St.", neighborhood: "Andersonville"),
        SeedBarData(name: "In Fine Spirits", latitude: 41.9804725, longitude: -87.6685868, address: "5420 N. Clark St.", neighborhood: "Andersonville"),
        SeedBarData(name: "Joie de Vine", latitude: 41.9798802, longitude: -87.6741256, address: "1744 W. Balmoral Ave.", neighborhood: "Andersonville"),
        SeedBarData(name: "SoFo", latitude: 41.9724246, longitude: -87.6676699, address: "4923 N. Clark St.", neighborhood: "Andersonville"),
        SeedBarData(name: "Fireside Restaurant", latitude: 41.9862289, longitude: -87.6743927, address: "5739 N. Ravenswood Ave.", neighborhood: "Edgewater"),
        SeedBarData(name: "Pumping Company", latitude: 41.9939521, longitude: -87.6601108, address: "6157 N. Broadway", neighborhood: "Edgewater"),
        SeedBarData(name: "Heartland Café", latitude: 42.009241, longitude: -87.666334, address: "7000 N. Glenwood Ave.", neighborhood: "Rogers Park"),
        SeedBarData(name: "Hop Häus", latitude: 42.0186015, longitude: -87.6758706, address: "7545 N. Clark St.", neighborhood: "Rogers Park"),
        SeedBarData(name: "Jackhammer", latitude: 41.9983713, longitude: -87.6709397, address: "6406 N. Clark St.", neighborhood: "Rogers Park"),
        SeedBarData(name: "Pitchfork Saloon", latitude: 41.954188, longitude: -87.7017101, address: "2922 W. Irving Park Rd.", neighborhood: "Albany Park"),
        SeedBarData(name: "Cobra Lounge", latitude: 41.8863879, longitude: -87.6667177, address: "235 N. Ashland Ave.", neighborhood: "West Town"),
        SeedBarData(name: "Happy Village", latitude: 41.9012796, longitude: -87.6745795, address: "1059 N. Wolcott Ave.", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Old Oak Tap", latitude: 41.8956186, longitude: -87.6799577, address: "2109 W. Chicago Ave.", neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Boundary", latitude: 41.9033893, longitude: -87.6762203, address: "1932 W. Division St.", neighborhood: "Wicker Park"),
        SeedBarData(name: "Enoteca Roma", latitude: 41.9033412, longitude: -87.6815533, address: "2146 W. Division St.", neighborhood: "Wicker Park"),
        SeedBarData(name: "Moonshine", latitude: 41.9034707, longitude: -87.6734502, address: "1824 W. Division St.", neighborhood: "Wicker Park"),
        SeedBarData(name: "Northside Café", latitude: 41.9115666, longitude: -87.6771517, address: "1635 N. Damen Ave.", neighborhood: "Wicker Park"),
        SeedBarData(name: "Spring Restaurant", latitude: 41.9103756, longitude: -87.678902, address: "2039 W. North Ave.", neighborhood: "Wicker Park"),
        SeedBarData(name: "Cortland Garage", latitude: 41.9159176, longitude: -87.6695803, address: "1645 W. Cortland St.", neighborhood: "Bucktown"),
        SeedBarData(name: "Floyd's Pub", latitude: 41.9174886, longitude: -87.6851722, address: "1944 N. Oakley Ave.", neighborhood: "Bucktown"),
        SeedBarData(name: "Dunlay's on the Square", latitude: 41.9277163, longitude: -87.706427, address: "3137 W. Logan Blvd.", neighborhood: "Logan Square"),
        SeedBarData(name: "Bristol Lounge", latitude: 41.9370294, longitude: -87.7209972, address: "3084 N. Milwaukee Ave.", neighborhood: "Avondale"),
        SeedBarData(name: "Orbit Room", latitude: 41.935612, longitude: -87.69751, address: "2959 N. California Ave.", neighborhood: "Avondale"),
        SeedBarData(name: "Cork & Kerry", latitude: 41.7004465, longitude: -87.6817644, address: "10614 S. Western Ave.", neighborhood: "Beverly"),
        SeedBarData(name: "Rosebud", latitude: 41.8694789, longitude: -87.6642957, address: "1500 W. Taylor St.", neighborhood: "Little Italy"),
    ]
}
