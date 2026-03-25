import AppKit
import Combine

final class MouseTracker: ObservableObject {
    @Published var mouseLocation: CGPoint = NSEvent.mouseLocation

    private var timer: DispatchSourceTimer?

    func startTracking() {
        stopTracking()

        // Use a high-frequency timer polling NSEvent.mouseLocation.
        // This approach does not require Accessibility permission — it reads
        // the global mouse position via the public NSEvent API.
        // Polling at ~120Hz for smooth tracking.
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: .milliseconds(8))
        source.setEventHandler { [weak self] in
            let loc = NSEvent.mouseLocation
            self?.mouseLocation = loc
        }
        source.resume()
        timer = source
    }

    func stopTracking() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        stopTracking()
    }
}
