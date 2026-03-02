import Foundation
import CoreLocation
import CoreData

/// Merges bar data from three sources (City permits, OSM, Yelp) by deduplicating
/// using geohash proximity + Jaro-Winkler name similarity.
///
/// **Atomic diff-based merge:** Instead of deleting all records and re-inserting,
/// the merge matches incoming bars against existing `BarEntity` records by
/// coordinate proximity + name similarity. Matched entities are updated in-place —
/// preserving the user's `isFavorite` and `sunAlertsEnabled` flags. Unmatched
/// stale entities are deleted only if the user hasn't personalised them.
///
/// **Background execution:** CoreData work runs on a private background context
/// so the main thread is never blocked.
final class DataMergeService: @unchecked Sendable {
    static let shared = DataMergeService()
    private init() {}

    @MainActor private var isMerging = false

    // MARK: - Public API

    @MainActor
    func mergeAndPersist(
        permits: [Bar],
        osmBars: [Bar],
        yelpBars: [Bar]
    ) async {
        guard !isMerging else { return }
        isMerging = true
        defer { isMerging = false }

        let blocked = SeedDataService.shared.permanentlyClosedNames
        let allBars = (permits + osmBars + yelpBars).filter { !blocked.contains($0.name) }
        let deduplicated = deduplicate(allBars)

        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        await bgContext.perform {
            let request = BarEntity.fetchRequest()
            let existing = (try? bgContext.fetch(request)) ?? []

            var matchedIDs = Set<NSManagedObjectID>()

            for bar in deduplicated {
                if let entity = self.findMatchingEntity(for: bar, in: existing) {
                    // Update metadata while preserving user-controlled fields
                    let savedFavorite  = entity.isFavorite
                    let savedAlerts    = entity.sunAlertsEnabled
                    let savedStatus    = entity.cachedSunStatus
                    let savedTimestamp = entity.cachedStatusTimestamp

                    bar.apply(to: entity)

                    entity.isFavorite         = savedFavorite
                    entity.sunAlertsEnabled   = savedAlerts
                    entity.cachedSunStatus    = savedStatus
                    entity.cachedStatusTimestamp = savedTimestamp

                    matchedIDs.insert(entity.objectID)
                } else {
                    let entity = BarEntity(context: bgContext)
                    bar.apply(to: entity)
                    matchedIDs.insert(entity.objectID)
                }
            }

            // Delete stale bars that the user hasn't personalised
            for entity in existing where !matchedIDs.contains(entity.objectID) {
                if !entity.isFavorite && !entity.sunAlertsEnabled {
                    bgContext.delete(entity)
                }
            }

            // Hard-delete permanently closed bars regardless of personalisation
            for entity in existing where blocked.contains(entity.name ?? "") {
                bgContext.delete(entity)
            }

            try? bgContext.save()
        }
    }

    // MARK: - Entity Matching

    /// Finds an existing `BarEntity` within ~200 m of `bar` with a similar name (Jaro-Winkler > 0.80).
    private func findMatchingEntity(for bar: Bar, in entities: [BarEntity]) -> BarEntity? {
        let coordThreshold = 0.002  // ~200 m in degrees
        return entities.first { entity in
            abs(entity.latitude  - bar.coordinate.latitude)  < coordThreshold &&
            abs(entity.longitude - bar.coordinate.longitude) < coordThreshold &&
            jaroWinkler(entity.name ?? "", bar.name) > 0.80
        }
    }

    // MARK: - Deduplication

    func deduplicate(_ bars: [Bar]) -> [Bar] {
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

    private func combinedBar(preferred: Bar, secondary: Bar) -> Bar {
        var result = preferred

        if preferred.dataSourceMask.contains(.cityPermit) {
            // keep preferred.address
        } else if secondary.dataSourceMask.contains(.cityPermit), let addr = secondary.address {
            result.address = addr
        }

        if preferred.dataSourceMask.contains(.osm) {
            // keep preferred.coordinate
        } else if secondary.dataSourceMask.contains(.osm) {
            result.coordinate = secondary.coordinate
        }

        if result.yelpID == nil, let yelpID = secondary.yelpID {
            result.yelpID = yelpID
            result.yelpURL = secondary.yelpURL
            result.yelpRating = secondary.yelpRating
            result.yelpReviewCount = secondary.yelpReviewCount
        }

        result.dataSourceMask = Bar.DataSourceMask(
            rawValue: preferred.dataSourceMask.rawValue | secondary.dataSourceMask.rawValue
        )
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

    func jaroWinkler(_ s1: String, _ s2: String) -> Double {
        let a = s1.lowercased()
        let b = s2.lowercased()
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }

        let jaro = jaroDistance(a, b)
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
        let matchDistance = max(max(a.count, b.count) / 2 - 1, 0)

        var aMatched = Array(repeating: false, count: a.count)
        var bMatched = Array(repeating: false, count: b.count)
        var matches = 0
        var transpositions = 0

        for i in 0..<a.count {
            let start = max(0, i - matchDistance)
            let end   = min(i + matchDistance, b.count - 1)
            guard start <= end else { continue }
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
            while k < b.count && !bMatched[k] { k += 1 }
            guard k < b.count else { break }
            if a[i] != b[k] { transpositions += 1 }
            k += 1
        }

        let m = Double(matches)
        return (m / Double(a.count) + m / Double(b.count) + (m - Double(transpositions) / 2.0) / m) / 3.0
    }
}
