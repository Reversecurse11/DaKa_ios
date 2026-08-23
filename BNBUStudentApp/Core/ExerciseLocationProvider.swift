#if BNBU_FIXTURES && DEBUG
import CoreLocation
import Foundation

/// Debug-only permission-flow fixture. The 1.1 GPS contract is default-denied,
/// so this type does not exist in production or staging binaries.
@MainActor
final class ExerciseLocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = ExerciseLocationProvider()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<(latitude: Double, longitude: Double)?, Never>?
    private var timeoutTask: Task<Void, Never>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Resolves within `timeout` seconds with a single fix or nil.
    func requestCurrentLocation(timeout: TimeInterval = 10) async -> (latitude: Double, longitude: Double)? {
        // A fetch is already in flight; location is best-effort, so bail.
        guard continuation == nil else { return nil }

        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(with: nil)
            }
            if self.manager.authorizationStatus != .notDetermined {
                self.manager.requestLocation()
            }
            // For .notDetermined the request continues from the delegate's
            // authorization callback (or times out on dismissal).
        }
    }

    private func finish(with fix: (latitude: Double, longitude: Double)?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: fix)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.finish(with: nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            guard let coordinate else {
                self.finish(with: nil)
                return
            }
            self.finish(with: (coordinate.latitude, coordinate.longitude))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.finish(with: nil)
        }
    }
}
#endif
