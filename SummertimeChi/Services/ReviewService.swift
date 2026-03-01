import Foundation
import CloudKit
import CoreData

/// Manages user reviews — stores locally first, then syncs to CloudKit public database.
final class ReviewService {
    static let shared = ReviewService()
    private init() {}

    private let publicDB = CKContainer(identifier: "iCloud.com.danielfurry.summertimechi").publicCloudDatabase

    // MARK: - Fetch Reviews

    /// Fetches reviews from both local CoreData and CloudKit public database.
    func fetchReviews(for barID: UUID) async -> [UserReview] {
        async let localReviews = fetchLocalReviews(for: barID)
        async let cloudReviews = fetchCloudReviews(for: barID)
        let (local, cloud) = await (localReviews, cloudReviews)

        // Deduplicate by cloudKitRecordID: prefer cloud version
        var reviewMap: [String: UserReview] = [:]
        for review in local {
            reviewMap[review.id.uuidString] = review
        }
        for review in cloud {
            if let ckID = review.cloudKitRecordID {
                reviewMap[ckID] = review
            }
        }
        return Array(reviewMap.values).sorted { $0.createdAt > $1.createdAt }
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

        // 1. Save locally immediately
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
        record["id"]                 = reviewID.uuidString as CKRecordValue
        record["barID"]              = barID.uuidString    as CKRecordValue
        record["sunRating"]          = sunRating           as CKRecordValue
        record["reviewText"]         = reviewText          as? CKRecordValue
        record["authorDisplayName"]  = authorDisplayName   as CKRecordValue
        record["createdAt"]          = now                 as CKRecordValue

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
    }

    // MARK: - Helpers

    private func cloudReviewToModel(_ record: CKRecord) -> UserReview? {
        guard let idStr   = record["id"]   as? String,
              let id      = UUID(uuidString: idStr),
              let barStr  = record["barID"] as? String,
              let barID   = UUID(uuidString: barStr),
              let rating  = record["sunRating"] as? Int else { return nil }

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
