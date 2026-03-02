import Foundation
import CoreLocation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var showSplash: Bool = true
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLoadingBars: Bool = false
    @Published var barLoadError: String?
    @Published var selectedBar: Bar?
    @Published var visibleBars: [Bar] = []

    private let locationManager = CLLocationManager()
    private var locationDelegate: LocationDelegate?

    init() {
        let delegate = LocationDelegate(appState: self)
        self.locationDelegate = delegate
        locationManager.delegate = delegate
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startLocationUpdates() {
        locationManager.startUpdatingLocation()
    }

    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }
}

// MARK: - Location Delegate

private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            appState?.locationAuthorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            appState?.userLocation = location.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently fail — user location is optional
    }
}
