import SwiftUI
import BackgroundTasks
import UserNotifications
import CoreData
import CoreLocation

@main
struct SummertimeChiApp: App {
    @StateObject private var appState = AppState()
    let persistenceController = PersistenceController.shared

    init() {
        registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appState)
                .task {
                    // Retry any reviews that failed to sync on a previous launch
                    await ReviewService.shared.retryPendingReviews()
                }
        }
    }

    // MARK: - Background Task Registration

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.danielfurry.summertimechi.suncheck",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleSunCheckTask(refreshTask)
        }
    }

    private func handleSunCheckTask(_ task: BGAppRefreshTask) {
        SummertimeChiApp.scheduleNextSunCheck()

        let operation = SunCheckOperation()
        task.expirationHandler = {
            operation.cancel()
        }
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }

        // Run on a dedicated background queue, not the main queue
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.addOperation(operation)
    }

    static func scheduleNextSunCheck() {
        let request = BGAppRefreshTaskRequest(
            identifier: "com.danielfurry.summertimechi.suncheck"
        )
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

// MARK: - Background Sun Check Operation

final class SunCheckOperation: Operation, @unchecked Sendable {
    override func main() {
        guard !isCancelled else { return }

        // Use a private background context — never use viewContext from a background thread
        let bgContext = PersistenceController.shared.container.newBackgroundContext()

        bgContext.performAndWait {
            let fetchRequest = BarEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "sunAlertsEnabled == YES")
            guard let bars = try? bgContext.fetch(fetchRequest) else { return }

            for bar in bars {
                guard !isCancelled else { return }
                let coordinate = CLLocationCoordinate2D(
                    latitude: bar.latitude,
                    longitude: bar.longitude
                )
                let solarPos = SolarCalculatorService.shared.solarPosition(
                    at: coordinate,
                    date: Date()
                )
                let previousStatus = SunStatus(rawValue: bar.cachedSunStatus ?? "") ?? .unknown
                // Building data not available in background; use solar position only
                let newStatus: SunStatus = solarPos.isAboveHorizon ? .sunlit : .belowHorizon

                if previousStatus == .shaded && newStatus == .sunlit {
                    NotificationService.shared.scheduleTransitionNotification(barName: bar.name ?? "Bar")
                }

                bar.cachedSunStatus    = newStatus.rawValue
                bar.cachedStatusTimestamp = Date()
            }

            try? bgContext.save()
        }
    }
}
