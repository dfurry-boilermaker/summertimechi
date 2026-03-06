import Foundation
import CoreData

@MainActor
final class BarDetailViewModel: ObservableObject {
    private let weather = WeatherService.shared
    @Published var bar: Bar
    @Published var sunTimeline: SunTimeline?
    @Published var currentStatus: SunStatus = .unknown
    @Published var communityReviews: [UserReview] = []
    @Published var isLoadingTimeline: Bool = false
    @Published var isFavorite: Bool = false
    @Published var sunAlertsEnabled: Bool = false

    /// Today's daylight hours during the bar's operating window.
    @Published var sunlightHoursToday: Double?
    /// Fraction of operating hours in daylight (0.0–1.0).
    @Published var sunlightFraction: Double?
    /// Display-ready string, e.g. "6.5 hrs of sun".
    @Published var formattedSunlight: String?

    private let context: NSManagedObjectContext
    private let shadow = ShadowCalculatorService.shared

    init(bar: Bar, context: NSManagedObjectContext) {
        var enriched = bar
        let seed = SeedDataService.shared
        if enriched.openHour == nil, let h = seed.hours(forBarNamed: bar.name, neighborhood: bar.neighborhood) {
            enriched.openHour = h.open
            enriched.closeHour = h.close
        }
        if enriched.address == nil, let addr = seed.address(forBarNamed: bar.name, neighborhood: bar.neighborhood) {
            enriched.address = addr
        }
        self.bar = enriched
        self.isFavorite = enriched.isFavorite
        self.sunAlertsEnabled = enriched.sunAlertsEnabled
        self.context = context
    }

    // MARK: - Load

    func loadAll() async {
        computeSunlightHours()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadSunTimeline() }
            group.addTask { await self.loadCommunityReviews() }
        }
    }

    private func computeSunlightHours() {
        let today = Date()
        sunlightHoursToday = bar.sunlightHours(on: today)
        sunlightFraction = bar.sunlightFraction(on: today)
        formattedSunlight = bar.formattedSunlightHours(on: today)
    }

    func loadSunTimeline() async {
        isLoadingTimeline = true
        defer { isLoadingTimeline = false }

        let today = Date()
        let buildings = (try? await OSMService.shared.fetchBuildings(near: bar.coordinate)) ?? []
        let hourlyCloudCover = await weather.fetchHourlyCloudCover(for: bar.coordinate, date: today)

        let timeline = shadow.generateTimeline(
            forBar: bar,
            buildings: buildings,
            date: today,
            cloudCover: 0,
            cloudCoverByHour: hourlyCloudCover
        )
        sunTimeline = timeline

        let hour = Calendar.current.component(.hour, from: today)
        let currentCloudCover = hourlyCloudCover?[hour] ?? 0
        currentStatus = shadow.sunStatus(
            forPatio: bar.coordinate,
            buildings: buildings,
            date: today,
            cloudCover: currentCloudCover
        )
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

    private static let transitionTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    /// Subtext shown below the status. When below horizon, shows sunrise time; otherwise shows next transition.
    var statusSubtext: String? {
        if currentStatus == .belowHorizon {
            return nextSunriseDescription
        }
        return nextTransitionDescription
    }

    private var nextSunriseDescription: String? {
        let now = Date()
        let solar = SolarCalculatorService.shared
        let (sunrise, sunset) = solar.sunriseSunset(at: bar.coordinate, date: now)

        let nextSunrise: Date?
        if let sr = sunrise, let ss = sunset {
            if now < sr {
                nextSunrise = sr
            } else if now > ss {
                let calendar = Calendar.current
                if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                    nextSunrise = solar.sunriseSunset(at: bar.coordinate, date: tomorrow).sunrise
                } else {
                    nextSunrise = nil
                }
            } else {
                nextSunrise = nil  // daytime, shouldn't reach here when belowHorizon
            }
        } else {
            nextSunrise = nil
        }

        guard let sr = nextSunrise else { return nil }
        return "Sunrise at \(Self.transitionTimeFormatter.string(from: sr))"
    }

    private var nextTransitionDescription: String? {
        guard let timeline = sunTimeline,
              let (nextStatus, nextTime) = timeline.nextTransition(from: Date()) else {
            return nil
        }
        let timeStr = Self.transitionTimeFormatter.string(from: nextTime)
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
