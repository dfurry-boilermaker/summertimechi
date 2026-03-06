import Foundation
import CoreData
import CoreLocation

@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published var favoriteBars: [Bar] = []
    @Published var weather: WeatherService.WeatherConditions?
    @Published var weatherError: String?
    @Published var isLoadingWeather: Bool = false

    private let context: NSManagedObjectContext
    // Central Chicago coordinate — representative for all city bars
    private static let chicagoCoord = CLLocationCoordinate2D(latitude: 41.8827, longitude: -87.6233)

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func loadWeather(forceRefresh: Bool = false) async {
        guard forceRefresh || weather == nil else { return }
        weatherError = nil
        isLoadingWeather = true
        defer { isLoadingWeather = false }
        switch await WeatherService.shared.fetchConditionsWithResult(for: Self.chicagoCoord) {
        case .success(let conditions):
            weather = conditions
        case .failure(let message):
            weatherError = message
        }
    }

    func loadFavorites() {
        let request = BarEntity.fetchRequest()
        request.predicate = NSPredicate(format: "isFavorite == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BarEntity.name, ascending: true)]
        guard let entities = try? context.fetch(request) else { return }
        let curatedNames = SeedDataService.shared.curatedBarNames
        favoriteBars = entities
            .filter { curatedNames.isEmpty || curatedNames.contains($0.name ?? "") }
            .map { entity in
            var bar = Bar(entity: entity)
            if let h = SeedDataService.shared.hours(forBarNamed: bar.name, neighborhood: bar.neighborhood) {
                bar.openHour = h.open
                bar.closeHour = h.close
            }
            return bar
        }
    }

    func removeFavorite(_ bar: Bar) {
        let request = BarEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", bar.id as CVarArg)
        if let entity = try? context.fetch(request).first {
            entity.isFavorite = false
            try? context.save()
        }
        favoriteBars.removeAll { $0.id == bar.id }
    }

    func toggleSunAlert(for bar: Bar) {
        let request = BarEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", bar.id as CVarArg)
        if let entity = try? context.fetch(request).first {
            entity.sunAlertsEnabled.toggle()
            if entity.sunAlertsEnabled {
                Task { await NotificationService.shared.requestAuthorization() }
            }
            try? context.save()
            loadFavorites()
        }
    }
}
