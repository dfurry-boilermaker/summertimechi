import Foundation
import CoreData

@MainActor
final class BarDetailViewModel: ObservableObject {
    @Published var bar: Bar
    @Published var sunTimeline: SunTimeline?
    @Published var currentStatus: SunStatus = .unknown
    @Published var weatherConditions: WeatherService.WeatherConditions?
    @Published var nearbyCamera: ChicagoCamera?
    @Published var cameraSnapshot: Data?
    @Published var communityReviews: [UserReview] = []
    @Published var isLoadingTimeline: Bool = false
    @Published var isFavorite: Bool = false
    @Published var sunAlertsEnabled: Bool = false

    private let context: NSManagedObjectContext
    private let shadow = ShadowCalculatorService.shared
    private let weather = WeatherService.shared
    private let camera = CameraFeedService.shared

    init(bar: Bar, context: NSManagedObjectContext) {
        self.bar = bar
        self.isFavorite = bar.isFavorite
        self.sunAlertsEnabled = bar.sunAlertsEnabled
        self.context = context
    }

    // MARK: - Load

    func loadAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadSunTimeline() }
            group.addTask { await self.loadWeather() }
            group.addTask { await self.loadCameraFeed() }
            group.addTask { await self.loadCommunityReviews() }
        }
    }

    func loadSunTimeline() async {
        isLoadingTimeline = true
        defer { isLoadingTimeline = false }

        let buildings = (try? await OSMService.shared.fetchBuildings(near: bar.coordinate, context: context)) ?? []
        let cloudCover = weatherConditions?.cloudCoverFraction ?? 0

        let timeline = shadow.generateTimeline(
            forBar: bar,
            buildings: buildings,
            date: Date(),
            cloudCover: cloudCover
        )
        sunTimeline = timeline
        currentStatus = shadow.sunStatus(
            forPatio: bar.coordinate,
            buildings: buildings,
            date: Date(),
            cloudCover: cloudCover
        )
    }

    func loadWeather() async {
        weatherConditions = await weather.fetchConditions(for: bar.coordinate)
    }

    func loadCameraFeed() async {
        nearbyCamera = camera.nearestCamera(to: bar.coordinate)
        if let cam = nearbyCamera {
            cameraSnapshot = await camera.fetchSnapshot(for: cam)
        }
    }

    func loadCommunityReviews() async {
        communityReviews = await ReviewService.shared.fetchReviews(for: bar.id)
    }

    // MARK: - Favorites & Alerts

    func toggleFavorite() {
        isFavorite.toggle()
        updateBarEntity { entity in
            entity.isFavorite = self.isFavorite
        }
    }

    func toggleSunAlerts() {
        sunAlertsEnabled.toggle()
        if sunAlertsEnabled {
            Task { await NotificationService.shared.requestAuthorization() }
        }
        updateBarEntity { entity in
            entity.sunAlertsEnabled = self.sunAlertsEnabled
        }
    }

    // MARK: - Next Transition

    var nextTransitionDescription: String? {
        guard let timeline = sunTimeline,
              let (nextStatus, nextTime) = timeline.nextTransition(from: Date()) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: nextTime)
        switch nextStatus {
        case .sunlit: return "Enters sun at \(timeStr)"
        case .shaded: return "Enters shade at \(timeStr)"
        default:      return "Changes at \(timeStr)"
        }
    }

    // MARK: - Helpers

    private func updateBarEntity(update: @escaping (BarEntity) -> Void) {
        let fetchRequest = BarEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", bar.id as CVarArg)
        if let entity = try? context.fetch(fetchRequest).first {
            update(entity)
            try? context.save()
        }
    }
}

// MARK: - User Review Model

struct UserReview: Identifiable {
    let id: UUID
    let barID: UUID
    let sunRating: Int       // 1-5
    let reviewText: String?
    let authorDisplayName: String
    let createdAt: Date
    let cloudKitRecordID: String?
}

extension UserReview {
    init(entity: UserReviewEntity) {
        self.id                 = entity.id ?? UUID()
        self.barID              = entity.barID ?? UUID()
        self.sunRating          = Int(entity.sunRating)
        self.reviewText         = entity.reviewText
        self.authorDisplayName  = entity.authorDisplayName ?? "Anonymous"
        self.createdAt          = entity.createdAt ?? Date()
        self.cloudKitRecordID   = entity.cloudKitRecordID
    }
}
