import Foundation
import CloudKit
import CoreData

/// Manages user reviews — stores locally first, then syncs to CloudKit public database.
///
/// **Caching:** Review lists are cached in memory for 5 minutes per bar to avoid
/// redundant CloudKit queries when the user navigates back to a bar detail.
///
/// **Offline resilience:** Reviews that fail to sync are stored locally with
/// `syncPending = true`. Call `retryPendingReviews()` on launch to re-attempt sync.
final class ReviewService {
    static let shared = ReviewService()
    private init() {}

    private let publicDB = CKContainer(identifier: "iCloud.com.danielfurry.summertimechi").publicCloudDatabase

    // MARK: - In-Memory Review Cache

    private actor ReviewCache {
        struct Entry { let reviews: [UserReview]; let fetchedAt: Date }
        private var store: [UUID: Entry] = [:]
        private static let ttl: TimeInterval = 5 * 60  // 5 minutes

        func get(_ barID: UUID) -> [UserReview]? {
            guard let entry = store[barID],
                  Date().timeIntervalSince(entry.fetchedAt) < Self.ttl else { return nil }
            return entry.reviews
        }

        func set(_ reviews: [UserReview], for barID: UUID) {
            store[barID] = Entry(reviews: reviews, fetchedAt: Date())
        }

        func invalidate(_ barID: UUID) {
            store.removeValue(forKey: barID)
        }
    }

    private let reviewCache = ReviewCache()

    // MARK: - Fetch Reviews

    /// Fetches reviews from both local CoreData and CloudKit, with a 5-minute in-memory cache.
    func fetchReviews(for barID: UUID) async -> [UserReview] {
        if let cached = await reviewCache.get(barID) {
            return cached
        }

        async let localReviews = fetchLocalReviews(for: barID)
        async let cloudReviews = fetchCloudReviews(for: barID)
        let (local, cloud) = await (localReviews, cloudReviews)

        var reviewMap: [String: UserReview] = [:]
        for review in local  { reviewMap[review.id.uuidString] = review }
        for review in cloud  { if let ckID = review.cloudKitRecordID { reviewMap[ckID] = review } }
        let merged = Array(reviewMap.values).sorted { $0.createdAt > $1.createdAt }

        await reviewCache.set(merged, for: barID)
        return merged
    }

    private func fetchLocalReviews(for barID: UUID) async -> [UserReview] {
        let context = PersistenceController.shared.container.viewContext
        let request = UserReviewEntity.fetchRequest()
        request.predicate = NSPredicate(format: "barID == %@", barID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \UserReviewEntity.createdAt, ascending: false)]
        let entities = (try? context.fetch(request)) ?? []
        return entities.map { UserReview(entity: $0) }
    }

    private func fetchCloudReviews(for barID: UUID) async -> [UserReview] {
        let predicate = NSPredicate(format: "barID == %@", barID.uuidString)
        let query = CKQuery(recordType: "UserReview", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let (results, _) = try await publicDB.records(matching: query)
            return results.compactMap { (_, result) in
                guard case .success(let record) = result else { return nil }
                return cloudReviewToModel(record)
            }
        } catch {
            return []
        }
    }

    // MARK: - Submit Review

    func submitReview(
        barID: UUID,
        sunRating: Int,
        reviewText: String?,
        authorDisplayName: String
    ) async throws {
        let reviewID = UUID()
        let now = Date()

        // 1. Save locally with syncPending = true
        await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            let entity = UserReviewEntity(context: context)
            entity.id = reviewID
            entity.barID = barID
            entity.sunRating = Int16(sunRating)
            entity.reviewText = reviewText
            entity.authorDisplayName = authorDisplayName
            entity.createdAt = now
            entity.syncPending = true
            try? context.save()
        }

        // 2. Sync to CloudKit
        let record = CKRecord(recordType: "UserReview")
        record["id"]                = reviewID.uuidString as CKRecordValue
        record["barID"]             = barID.uuidString    as CKRecordValue
        record["sunRating"]         = sunRating           as CKRecordValue
        record["reviewText"]        = reviewText          as? CKRecordValue
        record["authorDisplayName"] = authorDisplayName   as CKRecordValue
        record["createdAt"]         = now                 as CKRecordValue

        let savedRecord = try await publicDB.save(record)

        // 3. Mark as synced
        await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            let request = UserReviewEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", reviewID as CVarArg)
            if let entity = try? context.fetch(request).first {
                entity.syncPending = false
                entity.cloudKitRecordID = savedRecord.recordID.recordName
                try? context.save()
            }
        }

        // 4. Invalidate cache so the new review appears immediately
        await reviewCache.invalidate(barID)
    }

    // MARK: - Pending Sync Retry

    /// Retries any locally-saved reviews that failed to sync to CloudKit.
    /// Call this on app launch (after network is available).
    func retryPendingReviews() async {
        let context = PersistenceController.shared.container.viewContext
        let request = UserReviewEntity.fetchRequest()
        request.predicate = NSPredicate(format: "syncPending == YES")
        let pending = (try? context.fetch(request)) ?? []

        for entity in pending {
            guard let reviewID = entity.id,
                  let barID    = entity.barID else { continue }

            let entityID      = entity.objectID
            let sunRating     = Int(entity.sunRating)
            let reviewText    = entity.reviewText
            let displayName   = entity.authorDisplayName ?? "Anonymous"
            let createdAt     = entity.createdAt ?? Date()

            let record = CKRecord(recordType: "UserReview")
            record["id"]                = reviewID.uuidString as CKRecordValue
            record["barID"]             = barID.uuidString    as CKRecordValue
            record["sunRating"]         = sunRating           as CKRecordValue
            record["reviewText"]        = reviewText          as? CKRecordValue
            record["authorDisplayName"] = displayName         as CKRecordValue
            record["createdAt"]         = createdAt           as CKRecordValue

            do {
                let savedRecord = try await publicDB.save(record)
                await MainActor.run {
                    if let saved = try? context.existingObject(with: entityID) as? UserReviewEntity {
                        saved.syncPending = false
                        saved.cloudKitRecordID = savedRecord.recordID.recordName
                        try? context.save()
                    }
                }
            } catch {
                // Leave syncPending = true; will retry on next launch
            }
        }
    }

    // MARK: - Helpers

    private func cloudReviewToModel(_ record: CKRecord) -> UserReview? {
        guard let idStr  = record["id"]    as? String, let id    = UUID(uuidString: idStr),
              let barStr = record["barID"] as? String, let barID = UUID(uuidString: barStr),
              let rating = record["sunRating"] as? Int else { return nil }

        return UserReview(
            id: id,
            barID: barID,
            sunRating: rating,
            reviewText: record["reviewText"] as? String,
            authorDisplayName: record["authorDisplayName"] as? String ?? "Anonymous",
            createdAt: record["createdAt"] as? Date ?? Date(),
            cloudKitRecordID: record.recordID.recordName
        )
    }
}
