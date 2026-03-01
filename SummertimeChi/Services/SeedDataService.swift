import Foundation
import CoreLocation

struct SeedBarData {
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String
    let neighborhood: String
}

final class SeedDataService {
    static let shared = SeedDataService()
    private init() {}

    var curatedBars: [Bar] {
        bars.map { seed in
            Bar(
                id: UUID(),
                name: seed.name,
                coordinate: CLLocationCoordinate2D(latitude: seed.latitude, longitude: seed.longitude),
                address: seed.address,
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
                cachedStatusTimestamp: nil
            )
        }
    }

    private let bars: [SeedBarData] = [
        SeedBarData(name: "Kaiser Tiger",              latitude: 41.8840, longitude: -87.6643, address: "1415 W Randolph St",      neighborhood: "West Loop"),
        SeedBarData(name: "Recess",                    latitude: 41.8893, longitude: -87.6469, address: "838 W Kinzie St",          neighborhood: "River West"),
        SeedBarData(name: "The Dawson",                latitude: 41.8915, longitude: -87.6486, address: "730 W Grand Ave",          neighborhood: "River West"),
        SeedBarData(name: "District Brew Yards",       latitude: 41.8883, longitude: -87.6673, address: "417 N Ashland Ave",        neighborhood: "Noble Square"),
        SeedBarData(name: "Frontier",                  latitude: 41.9003, longitude: -87.6592, address: "1072 N Milwaukee Ave",     neighborhood: "Noble Square"),
        SeedBarData(name: "Big Star",                  latitude: 41.9090, longitude: -87.6777, address: "1531 N Damen Ave",         neighborhood: "Wicker Park"),
        SeedBarData(name: "Handlebar Bar & Grill",     latitude: 41.9100, longitude: -87.6843, address: "2311 W North Ave",         neighborhood: "Bucktown"),
        SeedBarData(name: "Middle Brow Bungalow",      latitude: 41.9172, longitude: -87.6966, address: "2840 W Armitage Ave",      neighborhood: "Bucktown"),
        SeedBarData(name: "Best Intentions",           latitude: 41.9172, longitude: -87.7054, address: "3281 W Armitage Ave",      neighborhood: "Bucktown"),
        SeedBarData(name: "Sportsman's Club",          latitude: 41.8973, longitude: -87.6874, address: "948 N Western Ave",        neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Inner Town Pub",            latitude: 41.8997, longitude: -87.6762, address: "1935 W Thomas St",         neighborhood: "Ukrainian Village"),
        SeedBarData(name: "Mott St",                   latitude: 41.9070, longitude: -87.6673, address: "1401 N Ashland Ave",       neighborhood: "Wicker Park"),
        SeedBarData(name: "The Hi-Lo",                 latitude: 41.9007, longitude: -87.6977, address: "1110 N California Ave",    neighborhood: "Humboldt Park"),
        SeedBarData(name: "Parson's Chicken & Fish",   latitude: 41.9172, longitude: -87.6986, address: "2952 W Armitage Ave",      neighborhood: "Logan Square"),
        SeedBarData(name: "The Whistler",              latitude: 41.9260, longitude: -87.7003, address: "2421 N Milwaukee Ave",     neighborhood: "Logan Square"),
        SeedBarData(name: "The Moonlighter",           latitude: 41.9271, longitude: -87.7012, address: "2523 N Milwaukee Ave",     neighborhood: "Logan Square"),
        SeedBarData(name: "Outside Voices",            latitude: 41.9237, longitude: -87.7003, address: "2259 N Milwaukee Ave",     neighborhood: "Logan Square"),
        SeedBarData(name: "Easy Does It",              latitude: 41.9318, longitude: -87.6990, address: "2934 W Diversey Ave",      neighborhood: "Logan Square"),
        SeedBarData(name: "Ludlow Liquors",            latitude: 41.9365, longitude: -87.6977, address: "2959 N California Ave",    neighborhood: "Avondale"),
        SeedBarData(name: "Sleeping Village",          latitude: 41.9397, longitude: -87.7185, address: "3734 W Belmont Ave",       neighborhood: "Avondale"),
        SeedBarData(name: "Central Park Bar",          latitude: 41.9447, longitude: -87.7182, address: "3549 N Central Park Ave",  neighborhood: "Avondale"),
        SeedBarData(name: "Volo Wine Bar",             latitude: 41.9448, longitude: -87.6769, address: "2008 W Roscoe St",         neighborhood: "Roscoe Village"),
        SeedBarData(name: "Long Room",                 latitude: 41.9538, longitude: -87.6701, address: "1612 W Irving Park Rd",    neighborhood: "Lake View"),
        SeedBarData(name: "Sheffield's Beer & Wine Garden", latitude: 41.9373, longitude: -87.6535, address: "3258 N Sheffield Ave", neighborhood: "Lake View"),
        SeedBarData(name: "Sidetrack",                 latitude: 41.9396, longitude: -87.6487, address: "3349 N Halsted St",        neighborhood: "Boystown"),
        SeedBarData(name: "Big Star Wrigleyville",     latitude: 41.9484, longitude: -87.6537, address: "3640 N Clark St",          neighborhood: "Wrigleyville"),
        SeedBarData(name: "Park & Field",              latitude: 41.9537, longitude: -87.6781, address: "1932 W Irving Park Rd",    neighborhood: "North Center"),
        SeedBarData(name: "Resi's Bierstube",          latitude: 41.9538, longitude: -87.6761, address: "2034 W Irving Park Rd",    neighborhood: "North Center"),
        SeedBarData(name: "Half Acre Beer Company",    latitude: 41.9584, longitude: -87.6862, address: "4257 N Lincoln Ave",       neighborhood: "Lincoln Square"),
        SeedBarData(name: "Goose Island Brewhouse",    latitude: 41.9146, longitude: -87.6654, address: "1800 N Clybourn Ave",      neighborhood: "Lincoln Park"),
        SeedBarData(name: "Old Town Ale House",        latitude: 41.9100, longitude: -87.6336, address: "219 W North Ave",          neighborhood: "Old Town"),
        SeedBarData(name: "Delilah's",                 latitude: 41.9313, longitude: -87.6862, address: "2771 N Lincoln Ave",       neighborhood: "Lincoln Park"),
        SeedBarData(name: "Spilt Milk",                latitude: 41.9084, longitude: -87.6487, address: "1500 N Halsted St",        neighborhood: "Old Town"),
        SeedBarData(name: "Hopleaf",                   latitude: 41.9760, longitude: -87.6542, address: "5148 N Clark St",          neighborhood: "Andersonville"),
        SeedBarData(name: "Moody's Pub",               latitude: 41.9886, longitude: -87.6588, address: "5910 N Broadway",          neighborhood: "Edgewater"),
        SeedBarData(name: "Moonflower",                latitude: 41.9397, longitude: -87.7460, address: "4727 W Belmont Ave",       neighborhood: "Portage Park"),
        SeedBarData(name: "Simone's",                  latitude: 41.8583, longitude: -87.6529, address: "960 W 18th St",            neighborhood: "Pilsen"),
        SeedBarData(name: "Kimski",                    latitude: 41.8584, longitude: -87.6527, address: "954 W 18th St",            neighborhood: "Pilsen"),
        SeedBarData(name: "Pilsen Yards",              latitude: 41.8464, longitude: -87.6487, address: "2119 S Halsted St",        neighborhood: "Pilsen"),
        SeedBarData(name: "Buddy Guy's Legends",       latitude: 41.8729, longitude: -87.6261, address: "700 S Wabash Ave",         neighborhood: "South Loop"),
        SeedBarData(name: "Maria's Packaged Goods",    latitude: 41.8383, longitude: -87.6529, address: "960 W 31st St",            neighborhood: "Bridgeport"),
        SeedBarData(name: "Bronzeville Winery",        latitude: 41.8171, longitude: -87.6068, address: "4335 S Cottage Grove Ave", neighborhood: "Bronzeville"),
        SeedBarData(name: "The Promontory",            latitude: 41.7986, longitude: -87.5872, address: "5311 S Lake Park Ave",     neighborhood: "Hyde Park"),
        SeedBarData(name: "Sifr",                      latitude: 41.8947, longitude: -87.6368, address: "660 N Orleans St",         neighborhood: "River North"),
        SeedBarData(name: "Bar Cargo",                 latitude: 41.8929, longitude: -87.6178, address: "465 N McClurg Ct",         neighborhood: "Streeterville"),
        SeedBarData(name: "Beatnik on the River",      latitude: 41.8870, longitude: -87.6370, address: "180 N Upper Wacker Dr",    neighborhood: "Loop"),
        SeedBarData(name: "Aba",                       latitude: 41.8871, longitude: -87.6473, address: "302 N Green St",           neighborhood: "West Loop"),
        SeedBarData(name: "Cindy's Rooftop",           latitude: 41.8803, longitude: -87.6247, address: "12 S Michigan Ave",        neighborhood: "Loop"),
        SeedBarData(name: "Miru",                      latitude: 41.8854, longitude: -87.6183, address: "401 E Wacker Dr",          neighborhood: "Lakeshore East"),
        SeedBarData(name: "Lula Cafe",                 latitude: 41.9285, longitude: -87.7060, address: "2537 N Kedzie Ave",        neighborhood: "Logan Square"),
    ]
}
