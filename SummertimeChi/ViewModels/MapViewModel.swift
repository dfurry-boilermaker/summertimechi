import Foundation
import MapKit
import CoreData

@MainActor
final class MapViewModel: ObservableObject {
    // Not @Published — region is only read by shadow computation, never observed in the UI.
    // Publishing it caused objectWillChange to fire on every camera move, forcing a full
    // MapView re-render on each pan/zoom gesture.
    var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.8827, longitude: -87.6233),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
    @Published var bars: [Bar] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    // MARK: - 3D / Shadow

    @Published var is3DMode: Bool = true
    @Published var shadowOverlays: [(coordinates: [CLLocationCoordinate2D], isShaded: Bool)] = []

    private let context: NSManagedObjectContext
    private let shadow = ShadowCalculatorService.shared
    private(set) var shadowTask: Task<Void, Never>?

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func triggerShadowRecomputation() {
        shadowTask?.cancel()
        shadowTask = Task { await recomputeShadowOverlays() }
    }

    // MARK: - Data Loading

    func loadBars() {
        let request = BarEntity.fetchRequest()
        request.predicate = NSPredicate(format: "hasPatioConfirmed == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BarEntity.name, ascending: true)]
        guard let entities = try? context.fetch(request) else { return }
        bars = entities.map { Bar(entity: $0) }

        // Immediately correct stale cached statuses without waiting for network.
        // If the sun is below the horizon right now, every bar must show the moon — no
        // cached "sunlit" value from earlier in the day should survive into the night.
        let solar = SolarCalculatorService.shared.solarPosition(at: region.center, date: Date())
        if !solar.isAboveHorizon {
            for idx in bars.indices {
                bars[idx].cachedSunStatus = .belowHorizon
            }
        }
    }

    func refreshData() async {
        // Prevent concurrent refreshes — a second tap while loading is silently ignored
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        let osmBars = (try? await OSMService.shared.fetchBars()) ?? []

        if osmBars.isEmpty {
            error = "Could not load bar data. Check your connection and try again."
            return
        }

        let allBars = osmBars + SeedDataService.shared.curatedBars

        await DataMergeService.shared.mergeAndPersist(
            permits: [],
            osmBars: allBars,
            yelpBars: []
        )

        loadBars()

        // Kick off shadow computation now that bars are refreshed
        triggerShadowRecomputation()
    }

    func visibleBars(in region: MKCoordinateRegion) -> [Bar] {
        bars.filter { bar in
            let latRange = (region.center.latitude  - region.span.latitudeDelta  / 2)...(region.center.latitude  + region.span.latitudeDelta  / 2)
            let lonRange = (region.center.longitude - region.span.longitudeDelta / 2)...(region.center.longitude + region.span.longitudeDelta / 2)
            return latRange.contains(bar.coordinate.latitude) && lonRange.contains(bar.coordinate.longitude)
        }
    }

    // MARK: - Shadow Overlay Computation

    func recomputeShadowOverlays() async {
        // Cap at 8 nearest bars to prevent runaway network calls and computation
        let visible = Array(visibleBars(in: region).prefix(8))
        let solar = SolarCalculatorService.shared.solarPosition(at: region.center, date: Date())

        guard solar.isAboveHorizon else {
            shadowOverlays = []
            for bar in visible {
                if let idx = bars.firstIndex(where: { $0.id == bar.id }) {
                    bars[idx].cachedSunStatus = .belowHorizon
                }
            }
            return
        }

        var overlays: [(coordinates: [CLLocationCoordinate2D], isShaded: Bool)] = []
        var processedBuildingIDs = Set<Int64>()
        var barStatuses: [UUID: SunStatus] = [:]

        for bar in visible {
            if Task.isCancelled { return }
            // Yield to the main actor between bars so gesture input stays responsive
            await Task.yield()

            let bbox = boundingBox(near: bar.coordinate, radiusMeters: 250)
            let arcgisBuildings = await ArcGISBuildingService.shared.fetchBuildings(in: bbox, context: context)
            let buildings: [OSMBuilding]
            if arcgisBuildings.isEmpty {
                buildings = (try? await OSMService.shared.fetchBuildings(near: bar.coordinate, context: context)) ?? []
            } else {
                buildings = arcgisBuildings
            }

            var barInShadow = false

            for building in buildings {
                if Task.isCancelled { return }

                if processedBuildingIDs.contains(building.id) {
                    if shadow.isPoint(bar.coordinate, inShadowOf: building, solarPosition: solar) {
                        barInShadow = true
                    }
                    continue
                }

                processedBuildingIDs.insert(building.id)

                guard let polygon = shadow.shadowPolygon(for: building, solarPosition: solar) else { continue }

                let isShading = shadow.isPoint(bar.coordinate, inShadowOf: building, solarPosition: solar)
                if isShading { barInShadow = true }

                var coords = [CLLocationCoordinate2D](
                    repeating: kCLLocationCoordinate2DInvalid,
                    count: polygon.pointCount
                )
                polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
                guard coords.count >= 3 else { continue }
                overlays.append((coordinates: coords, isShaded: isShading))
            }

            barStatuses[bar.id] = barInShadow ? .shaded : .sunlit
        }

        guard !Task.isCancelled else { return }

        shadowOverlays = overlays
        for (barID, status) in barStatuses {
            if let idx = bars.firstIndex(where: { $0.id == barID }) {
                bars[idx].cachedSunStatus = status
            }
        }
    }

    // MARK: - Helpers

    func boundingBox(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Double
    ) -> (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        let deltaLat = radiusMeters / 111_320.0
        let deltaLon = radiusMeters / (111_320.0 * cos(coordinate.latitude * .pi / 180.0))
        return (
            minLat: coordinate.latitude  - deltaLat,
            minLon: coordinate.longitude - deltaLon,
            maxLat: coordinate.latitude  + deltaLat,
            maxLon: coordinate.longitude + deltaLon
        )
    }
}
