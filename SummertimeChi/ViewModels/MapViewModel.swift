import Foundation
import MapKit
import CoreData
import Combine

@MainActor
final class MapViewModel: ObservableObject {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.8827, longitude: -87.6233), // Chicago
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
    @Published var bars: [Bar] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let context: NSManagedObjectContext
    private let shadow = ShadowCalculatorService.shared
    private let weather = WeatherService.shared

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Data Loading

    func loadBars() {
        let request = BarEntity.fetchRequest()
        request.predicate = NSPredicate(format: "hasPatioConfirmed == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BarEntity.name, ascending: true)]
        guard let entities = try? context.fetch(request) else { return }
        bars = entities.map { Bar(entity: $0) }
    }

    func refreshData() async {
        isLoading = true
        defer { isLoading = false }

        // Fetch each source independently — a single failure shouldn't block the others
        async let permitsTask = ChicagoCityDataService.shared.fetchPermits()
        async let osmTask     = OSMService.shared.fetchBars()

        let permits = (try? await permitsTask) ?? []
        let osmBars = (try? await osmTask) ?? []

        let osmBarsAll = osmBars + SeedDataService.shared.curatedBars

        await DataMergeService.shared.mergeAndPersist(
            permits: permits,
            osmBars: osmBarsAll,
            yelpBars: [],
            context: context
        )
        loadBars()
    }

    // MARK: - Sun Status Updates

    /// Updates sun status for all currently visible bars (lazy, called on map region change).
    func updateSunStatus(for visibleBars: [Bar]) async {
        let date = Date()
        let weatherConditions = await weather.fetchConditions(for: region.center)
        let cloudCover = weatherConditions?.cloudCoverFraction ?? 0

        // Iterate by value — bars array may be replaced by loadBars() at any await point,
        // so we re-look up the live index after each suspension rather than using a stale i.
        for bar in visibleBars {
            // Skip if status was updated within the last 30 minutes
            if let ts = bar.cachedStatusTimestamp, date.timeIntervalSince(ts) < 1800 { continue }

            let buildings = (try? await OSMService.shared.fetchBuildings(near: bar.coordinate, context: context)) ?? []
            let status = shadow.sunStatus(forPatio: bar.coordinate, buildings: buildings, date: date, cloudCover: cloudCover)

            // Re-look up live index after the await — array may have been replaced
            guard let idx = bars.firstIndex(where: { $0.id == bar.id }) else { continue }
            bars[idx].cachedSunStatus = status
            bars[idx].cachedStatusTimestamp = date

            // Persist status update
            let fetchRequest = BarEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", bar.id as CVarArg)
            if let entity = try? context.fetch(fetchRequest).first {
                entity.cachedSunStatus = status.rawValue
                entity.cachedStatusTimestamp = date
                try? context.save()
            }
        }
    }

    func visibleBars(in region: MKCoordinateRegion) -> [Bar] {
        bars.filter { bar in
            let latRange = (region.center.latitude - region.span.latitudeDelta / 2)...(region.center.latitude + region.span.latitudeDelta / 2)
            let lonRange = (region.center.longitude - region.span.longitudeDelta / 2)...(region.center.longitude + region.span.longitudeDelta / 2)
            return latRange.contains(bar.coordinate.latitude) && lonRange.contains(bar.coordinate.longitude)
        }
    }
}
