@preconcurrency import ApplicationServices
import Foundation
import Observation

@MainActor
@Observable
final class MacAppModel {
    private(set) var serverState = "Starting HTTP server…"
    private(set) var isServerListening = false
    private(set) var isWatchConnected = false
    private(set) var lastInputDescription = "No input received"
    private(set) var accessibilityGranted = AXIsProcessTrusted()
    let port = 8_787
    let localAddress = LocalNetworkAddress.preferredIPv4() ?? ProcessInfo.processInfo.hostName

    private let cursorController = CursorController()
    private var httpServer: MacHTTPServer!

    init() {
        httpServer = MacHTTPServer(port: port) { [weak self] input in
            Task { @MainActor [weak self] in
                self?.handle(input)
            }
        } stateHandler: { [weak self] state in
            Task { @MainActor [weak self] in
                self?.serverState = state.summary
                self?.isServerListening = state.isListening
                self?.isWatchConnected = state.isConnected
            }
        }
        httpServer.start()
    }

    var connectionSummary: String {
        if isWatchConnected { return "Apple Watch connected" }
        if isServerListening { return "Listening on \(localAddress):\(port)" }
        return serverState
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAccessibility()
    }

    func refreshAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func testMovement() {
        cursorController.moveBy(dx: 80, dy: 0)
        refreshAccessibility()
    }

    func testClick() {
        cursorController.leftClick()
        refreshAccessibility()
    }

    private func handle(_ input: ForceCursorInput) {
        switch input.action {
        case .hello:
            lastInputDescription = "Watch handshake"
        case .motion:
            cursorController.moveBy(dx: CGFloat(input.x), dy: CGFloat(input.y))
            lastInputDescription = String(format: "Motion %.1f, %.1f", input.x, input.y)
        case .leftClick:
            cursorController.leftClick()
            lastInputDescription = "Left click"
        case .rightClick:
            cursorController.rightClick()
            lastInputDescription = "Right click"
        case .mouseDown:
            cursorController.mouseDown()
            lastInputDescription = "Mouse down"
        case .mouseUp:
            cursorController.mouseUp()
            lastInputDescription = "Mouse up"
        case .scroll:
            cursorController.scroll(vertical: input.y, horizontal: input.x)
            lastInputDescription = String(format: "Scroll %.1f", input.y)
        case .stop:
            cursorController.mouseUp()
            lastInputDescription = "Cursor stopped"
        case .unspecified:
            break
        case .UNRECOGNIZED:
            lastInputDescription = "Unknown command"
        }
    }
}
