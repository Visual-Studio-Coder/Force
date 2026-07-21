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
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ForceCursor.Motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    private var grpcClient: WatchGRPCClient!
    private var sequence: UInt64 = 0

    init() {
        host = UserDefaults.standard.string(forKey: Self.hostDefaultsKey) ?? ""
        grpcClient = WatchGRPCClient { [weak self] state in
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
            grpcClient.disconnect()
            return
        }

        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            connectionState = "Enter your Mac address"
            return
        }

        host = address
        grpcClient.connect(host: address, port: port)
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
        send(action: .stop)
        lastMotion = "Idle"
    }

    private func startCursor() {
        guard isConnected, motionManager.isDeviceMotionAvailable else {
            connectionState = isConnected ? "Motion unavailable" : "Connect to Mac first"
            return
        }

        isCursorActive = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0

        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }

            Task { @MainActor [weak self] in
                guard let self, self.isCursorActive else { return }

                // Rotation rate is relative motion intent. It returns to zero when the wrist stops.
                let dx = Float(motion.rotationRate.y * self.sensitivity)
                let dy = Float(motion.rotationRate.x * self.sensitivity)
                self.send(action: .motion, x: dx, y: dy)
                self.lastMotion = String(format: "%.1f, %.1f", dx, dy)
            }
        }
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
        grpcClient.send(input)
    }
}
