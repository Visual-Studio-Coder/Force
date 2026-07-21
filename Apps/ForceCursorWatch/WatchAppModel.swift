import CoreMotion
import Foundation
import Observation

@MainActor
@Observable
final class WatchAppModel {
    private(set) var connectionState = "Enter your Mac address"
    private(set) var isConnected = false
    private(set) var isConnecting = false
    private(set) var isCursorActive = false
    private(set) var lastMotion = "Idle"
    var sensitivity: Double = 6.0
    var host: String {
        didSet { UserDefaults.standard.set(host, forKey: Self.hostDefaultsKey) }
    }

    private static let hostDefaultsKey = "ForceCursor.macHost"
    private let port = 8_787
    private let motionManager = CMMotionManager()
    private var httpClient: WatchHTTPClient!
    private var sequence: UInt64 = 0
    private var lastMotionTimestamp: TimeInterval?

    init() {
        host = UserDefaults.standard.string(forKey: Self.hostDefaultsKey) ?? ""
        httpClient = WatchHTTPClient { [weak self] state in
            Task { @MainActor [weak self] in
                self?.connectionState = state.summary
                self?.isConnected = state.isConnected
                self?.isConnecting = state.isConnecting
                if !state.isConnected {
                    self?.stopCursor()
                }
            }
        }
    }

    func toggleConnection() {
        if isConnected || isConnecting {
            httpClient.disconnect()
            return
        }

        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            connectionState = "Enter your Mac address"
            return
        }

        host = address
        httpClient.connect(host: address, port: port)
    }

    func toggleCursor() {
        isCursorActive ? stopCursor() : startCursor()
    }

    func leftClick() {
        send(action: .leftClick)
    }

    func rightClick() {
        send(action: .rightClick)
    }

    func stopCursor() {
        guard isCursorActive else { return }
        isCursorActive = false
        motionManager.stopDeviceMotionUpdates()
        lastMotionTimestamp = nil
        send(action: .stop)
        lastMotion = "Idle"
    }

    private func startCursor() {
        guard isConnected, motionManager.isDeviceMotionAvailable else {
            connectionState = isConnected ? "Motion unavailable" : "Connect to Mac first"
            return
        }

        isCursorActive = true
        lastMotionTimestamp = nil
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion, error == nil, self.isCursorActive else { return }

            let elapsed = self.elapsedTime(for: motion.timestamp)
            let dx = self.pointerDelta(angularVelocity: motion.rotationRate.y, elapsed: elapsed)
            let dy = self.pointerDelta(angularVelocity: motion.rotationRate.x, elapsed: elapsed)
            if dx != 0 || dy != 0 {
                self.send(action: .motion, x: dx, y: dy)
            }
            self.lastMotion = String(format: "%.1f, %.1f", dx, dy)
        }
    }

    private func elapsedTime(for timestamp: TimeInterval) -> TimeInterval {
        defer { lastMotionTimestamp = timestamp }
        guard let lastMotionTimestamp else { return 1.0 / 50.0 }
        return min(max(timestamp - lastMotionTimestamp, 1.0 / 120.0), 1.0 / 20.0)
    }

    private func pointerDelta(angularVelocity: Double, elapsed: TimeInterval) -> Float {
        let deadZone = 0.06
        let speed = abs(angularVelocity)
        guard speed > deadZone else { return 0 }

        let effectiveSpeed = speed - deadZone
        let acceleration = 1.0 + min(effectiveSpeed * 0.8, 2.0)
        let pixelsPerRadian = sensitivity * 100.0
        let direction = angularVelocity.sign == .minus ? -1.0 : 1.0
        return Float(direction * effectiveSpeed * acceleration * pixelsPerRadian * elapsed)
    }

    private func send(action: ForceCursorAction, x: Float = 0, y: Float = 0) {
        guard isConnected else { return }
        sequence &+= 1

        var input = ForceCursorInput()
        input.sequence = sequence
        input.timestampNanoseconds = DispatchTime.now().uptimeNanoseconds
        input.action = action
        input.x = x
        input.y = y
        httpClient.send(input)
    }
}
