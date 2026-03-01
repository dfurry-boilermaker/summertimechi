import Foundation
import CoreData
import Combine

@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published var favoriteBars: [Bar] = []
    @Published var isLoading: Bool = false

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func loadFavorites() {
        let request = BarEntity.fetchRequest()
        request.predicate = NSPredicate(format: "isFavorite == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BarEntity.name, ascending: true)]
        guard let entities = try? context.fetch(request) else { return }
        favoriteBars = entities.map { Bar(entity: $0) }
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
