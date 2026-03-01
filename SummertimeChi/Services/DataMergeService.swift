import Foundation
import CoreLocation
import CoreData

/// Merges bar data from three sources (City permits, OSM, Yelp) by deduplicating
/// using geohash proximity + Jaro-Winkler name similarity.
final class DataMergeService {
    static let shared = DataMergeService()
    private init() {}

    // MARK: - Public API

    /// Takes bars from all three sources, deduplicates them, and saves to CoreData.
    func mergeAndPersist(
        permits: [Bar],
        osmBars: [Bar],
        yelpBars: [Bar],
        context: NSManagedObjectContext
    ) async {
        let allBars = permits + osmBars + yelpBars
        let deduplicated = deduplicate(allBars)

        await MainActor.run {
            // Delete all existing BarEntity records before re-inserting
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = BarEntity.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            _ = try? context.execute(deleteRequest)

            for bar in deduplicated {
                let entity = BarEntity(context: context)
                bar.apply(to: entity)
            }
            try? context.save()
        }
    }

    // MARK: - Deduplication

    func deduplicate(_ bars: [Bar]) -> [Bar] {
        // Group by geohash cell (precision 7 ≈ 150m × 150m)
        var grid: [String: [Bar]] = [:]
        for bar in bars {
            let hash = geohash(lat: bar.coordinate.latitude, lon: bar.coordinate.longitude, precision: 7)
            grid[hash, default: []].append(bar)
        }

        var result: [Bar] = []
        for (_, cluster) in grid {
            result.append(contentsOf: mergeCluster(cluster))
        }
        return result
    }

    private func mergeCluster(_ bars: [Bar]) -> [Bar] {
        guard bars.count > 1 else { return bars }

        var merged: [Bar] = []
        var used = Set<UUID>()

        for bar in bars {
            guard !used.contains(bar.id) else { continue }
            var best = bar
            for other in bars where other.id != bar.id && !used.contains(other.id) {
                if jaroWinkler(bar.name, other.name) > 0.85 {
                    best = combinedBar(preferred: best, secondary: other)
                    used.insert(other.id)
                }
            }
            used.insert(bar.id)
            merged.append(best)
        }
        return merged
    }

    /// Combines two bars that represent the same venue, preferring higher-quality data per field.
    private func combinedBar(preferred: Bar, secondary: Bar) -> Bar {
        var result = preferred

        // Prefer city permit address
        if preferred.dataSourceMask.contains(.cityPermit) {
            // keep preferred.address
        } else if secondary.dataSourceMask.contains(.cityPermit), let addr = secondary.address {
            result.address = addr
        }

        // Prefer OSM coordinates (more precise)
        if preferred.dataSourceMask.contains(.osm) {
            // keep preferred.coordinate
        } else if secondary.dataSourceMask.contains(.osm) {
            result.coordinate = secondary.coordinate
        }

        // Prefer Yelp ratings/ID
        if result.yelpID == nil, let yelpID = secondary.yelpID {
            result.yelpID = yelpID
            result.yelpURL = secondary.yelpURL
            result.yelpRating = secondary.yelpRating
            result.yelpReviewCount = secondary.yelpReviewCount
        }

        // Combine data source masks
        result.dataSourceMask = Bar.DataSourceMask(rawValue: preferred.dataSourceMask.rawValue | secondary.dataSourceMask.rawValue)

        // patio confirmed if either source confirms it
        result.hasPatioConfirmed = preferred.hasPatioConfirmed || secondary.hasPatioConfirmed

        return result
    }

    // MARK: - Geohash (base-32)

    private let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    func geohash(lat: Double, lon: Double, precision: Int) -> String {
        var minLat = -90.0, maxLat = 90.0
        var minLon = -180.0, maxLon = 180.0
        var isEven = true
        var bit = 0
        var charIndex = 0
        var result = ""

        while result.count < precision {
            if isEven {
                let mid = (minLon + maxLon) / 2
                if lon >= mid { charIndex = (charIndex << 1) | 1; minLon = mid }
                else          { charIndex = charIndex << 1;        maxLon = mid }
            } else {
                let mid = (minLat + maxLat) / 2
                if lat >= mid { charIndex = (charIndex << 1) | 1; minLat = mid }
                else          { charIndex = charIndex << 1;        maxLat = mid }
            }
            isEven = !isEven
            bit += 1
            if bit == 5 {
                result.append(base32[charIndex])
                bit = 0
                charIndex = 0
            }
        }
        return result
    }

    // MARK: - Jaro-Winkler Similarity

    /// Computes Jaro-Winkler string similarity (0.0–1.0).
    func jaroWinkler(_ s1: String, _ s2: String) -> Double {
        let a = s1.lowercased()
        let b = s2.lowercased()
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }

        let jaro = jaroDistance(a, b)
        // Common prefix (max 4 chars)
        var prefix = 0
        for (c1, c2) in zip(a, b) {
            if c1 == c2 { prefix += 1 } else { break }
            if prefix == 4 { break }
        }
        return jaro + Double(prefix) * 0.1 * (1.0 - jaro)
    }

    private func jaroDistance(_ s1: String, _ s2: String) -> Double {
        let a = Array(s1)
        let b = Array(s2)
        let matchDistance = max(a.count, b.count) / 2 - 1

        var aMatched = Array(repeating: false, count: a.count)
        var bMatched = Array(repeating: false, count: b.count)
        var matches = 0
        var transpositions = 0

        for i in 0..<a.count {
            let start = max(0, i - matchDistance)
            let end   = min(i + matchDistance, b.count - 1)
            for j in start...end {
                if bMatched[j] || a[i] != b[j] { continue }
                aMatched[i] = true
                bMatched[j] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0.0 }

        var k = 0
        for i in 0..<a.count where aMatched[i] {
            while !bMatched[k] { k += 1 }
            if a[i] != b[k] { transpositions += 1 }
            k += 1
        }

        let m = Double(matches)
        return (m / Double(a.count) + m / Double(b.count) + (m - Double(transpositions) / 2.0) / m) / 3.0
    }
}
