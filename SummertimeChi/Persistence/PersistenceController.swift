import CoreData
import CloudKit

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "SummertimeChi")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            setupStoreDescriptions()
        }

        container.loadPersistentStores { [weak self] description, error in
            guard error != nil else { return }
            // Attempt recovery: destroy the corrupted store and re-add it empty.
            // Seed data will be reloaded on next fetch.
            if let url = description.url {
                _ = try? self?.container.persistentStoreCoordinator.destroyPersistentStore(
                    at: url, type: .sqlite, options: nil
                )
                _ = try? self?.container.persistentStoreCoordinator.addPersistentStore(
                    ofType: NSSQLiteStoreType,
                    configurationName: description.configuration,
                    at: url,
                    options: nil
                )
            }
        }

        // Seed curated bars on first launch
        let ctx = container.viewContext
        let req = BarEntity.fetchRequest()
        req.fetchLimit = 1
        if ((try? ctx.fetch(req)) ?? []).isEmpty {
            for bar in SeedDataService.shared.curatedBars {
                let entity = BarEntity(context: ctx)
                bar.apply(to: entity)
            }
            try? ctx.save()
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Store Descriptions

    private func setupStoreDescriptions() {
        guard let localDesc = container.persistentStoreDescriptions.first else { return }

        // Local store for buildings cache (no CloudKit sync needed)
        let localURL = localDesc.url?.deletingLastPathComponent()
            .appendingPathComponent("SummertimeChi-Local.sqlite")
        let buildingDesc = NSPersistentStoreDescription(url: localURL ?? localDesc.url!)
        buildingDesc.configuration = "Local"
        buildingDesc.cloudKitContainerOptions = nil

        // CloudKit store for bars and reviews
        localDesc.configuration = "Cloud"
        localDesc.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.danielfurry.summertimechi"
        )

        container.persistentStoreDescriptions = [localDesc, buildingDesc]
    }

    // MARK: - Preview Support

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        // Insert sample bars for SwiftUI previews
        let bar = BarEntity(context: context)
        bar.id = UUID()
        bar.name = "Gman Tavern"
        bar.latitude = 41.9472
        bar.longitude = -87.6539
        bar.neighborhood = "Wrigleyville"
        bar.hasPatioConfirmed = true
        bar.isFavorite = false
        bar.sunAlertsEnabled = false
        bar.yelpRating = 4.5
        bar.yelpReviewCount = 312

        try? context.save()
        return controller
    }()

    // MARK: - Save Helper

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        try? context.save()
    }
}
