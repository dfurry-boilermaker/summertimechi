import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState
    @State private var splashPulse = false

    var body: some View {
        ZStack {
            TabView {
                MapView()
                    .tabItem {
                        Label("Map", systemImage: "map.fill")
                    }

                SearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                FavoritesView()
                    .tabItem {
                        Label("Favorites", systemImage: "heart.fill")
                    }
            }
            .tint(.yellow)

            if appState.showSplash {
                Color("LaunchBackground")
                    .ignoresSafeArea()
                    .overlay {
                        Image("LoadingIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .scaleEffect(splashPulse ? 1.04 : 1.0)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: splashPulse)
                    }
                    .onAppear { splashPulse = true }
                    .transition(.opacity.animation(.easeOut(duration: 0.4)))
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppState())
}
