import SwiftUI
import MapKit
import CoreData

/// Main map tab.
///
/// Uses the iOS 17 SwiftUI `Map` API with `MapCamera` for 3D tilted perspective and
/// `MapPolygon` for real-time building shadow overlays — no UIViewRepresentable needed.
struct MapView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: MapViewModel
    @State private var selectedBar: Bar?
    @State private var cameraPosition: MapCameraPosition
    @State private var currentCamera: MapCamera?

    private static let chicagoCoord = CLLocationCoordinate2D(latitude: 41.8827, longitude: -87.6233)

    init() {
        let vm = MapViewModel(context: PersistenceController.shared.container.viewContext)
        _viewModel = StateObject(wrappedValue: vm)
        _cameraPosition = State(initialValue: .camera(MapCamera(
            centerCoordinate: MapView.chicagoCoord,
            distance: 1_500,
            heading: 0,
            pitch: 60
        )))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                mapLayer

                if viewModel.isLoading {
                    ProgressView("Loading bars…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                VStack {
                    Spacer()
                    locationButton
                        .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("SummertimeChi")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 28)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refreshViewport() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Update current view")
                    .disabled(viewModel.isLoading)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.is3DMode.toggle()
                    } label: {
                        Image(systemName: viewModel.is3DMode ? "map" : "cube")
                    }
                }
            }
            .sheet(item: $selectedBar) { (bar: Bar) in
                BarDetailView(bar: bar)
                    .presentationDetents([.fraction(0.55), .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.error != nil },
                set: { _ in viewModel.error = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.error ?? "")
            }
        }
        .onAppear {
            appState.requestLocationPermission()
            viewModel.loadBars()
            if viewModel.bars.isEmpty {
                Task {
                    await viewModel.refreshData()
                    withAnimation(.easeOut(duration: 0.4)) { appState.showSplash = false }
                }
            } else {
                viewModel.triggerShadowRecomputation()
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    withAnimation(.easeOut(duration: 0.4)) { appState.showSplash = false }
                }
            }
        }
        .onChange(of: viewModel.is3DMode) { _, is3D in
            let center   = currentCamera?.centerCoordinate ?? Self.chicagoCoord
            let distance = currentCamera?.distance ?? 1_500
            let heading  = currentCamera?.heading  ?? 0
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .camera(MapCamera(
                    centerCoordinate: center,
                    distance: distance,
                    heading: heading,
                    pitch: is3D ? 60 : 0
                ))
            }
        }
    }

    // MARK: - Map Content

    @ViewBuilder
    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            // User location blue dot
            UserAnnotation()
            // Bar annotation pins
            ForEach(viewModel.bars) { bar in
                Annotation(bar.name, coordinate: bar.coordinate) {
                    BarAnnotationView(bar: bar) {
                        selectedBar = bar
                    }
                }
            }
            // Shadow polygons (semi-transparent dark fill, no stroke).
            // enumerated() snapshots the array so stale indices never subscript a shorter array.
            ForEach(Array(viewModel.shadowOverlays.enumerated()), id: \.offset) { _, overlay in
                MapPolygon(coordinates: overlay.coordinates)
                    .foregroundStyle(.black.opacity(0.35))
                    .stroke(.clear, lineWidth: 0)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {}
        .ignoresSafeArea(edges: .top)
        .onMapCameraChange(frequency: .onEnd) { context in
            currentCamera = context.camera
            viewModel.region = context.region
            viewModel.triggerShadowRecomputation()
        }
    }

    // MARK: - Subviews

    private var locationButton: some View {
        Button {
            guard let coord = appState.userLocation else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .camera(MapCamera(
                    centerCoordinate: coord,
                    distance: 1_500,
                    heading: currentCamera?.heading ?? 0,
                    pitch: viewModel.is3DMode ? 60 : 0
                ))
            }
        } label: {
            Label("My Location", systemImage: appState.userLocation != nil ? "location.fill" : "location")
                .font(.subheadline.bold())
        }
        .buttonStyle(.borderedProminent)
        .tint(.yellow)
        .foregroundStyle(.black)
    }
}

#Preview {
    MapView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
