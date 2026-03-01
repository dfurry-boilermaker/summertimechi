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
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BarEntity.name, ascending: true)]
        guard let entities = try? context.fetch(request) else { return }
        bars = entities.map { Bar(entity: $0) }
    }

    func refreshData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let permitsTask = ChicagoCityDataService.shared.fetchPermits()
            async let osmTask     = OSMService.shared.fetchBars()
            async let yelpTask    = YelpService.shared.fetchBars()

            let (permits, osmBars, yelpBars) = try await (permitsTask, osmTask, yelpTask)
            await DataMergeService.shared.mergeAndPersist(
                permits: permits,
                osmBars: osmBars,
                yelpBars: yelpBars,
                context: context
            )
            loadBars()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Sun Status Updates

    /// Updates sun status for all currently visible bars (lazy, called on map region change).
    func updateSunStatus(for visibleBars: [Bar]) async {
        let date = Date()
        let weatherConditions = await weather.fetchConditions(for: region.center)
        let cloudCover = weatherConditions?.cloudCoverFraction ?? 0

        for i in bars.indices {
            guard visibleBars.contains(where: { $0.id == bars[i].id }) else { continue }
            let bar = bars[i]

            // Fetch or use cached buildings
            let buildings = (try? await OSMService.shared.fetchBuildings(near: bar.coordinate, context: context)) ?? []
            let status = shadow.sunStatus(forPatio: bar.coordinate, buildings: buildings, date: date, cloudCover: cloudCover)

            bars[i].cachedSunStatus = status
            bars[i].cachedStatusTimestamp = date

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
