import CoreGraphics

@MainActor
final class CursorController {
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    func moveBy(dx: CGFloat, dy: CGFloat) {
        guard let current = CGEvent(source: eventSource)?.location else { return }
        let destination = CGPoint(x: current.x + dx, y: current.y + dy)
        postMouse(type: .mouseMoved, at: destination, button: .left)
    }

    func leftClick() {
        guard let location = CGEvent(source: eventSource)?.location else { return }
        postMouse(type: .leftMouseDown, at: location, button: .left)
        postMouse(type: .leftMouseUp, at: location, button: .left)
    }

    func rightClick() {
        guard let location = CGEvent(source: eventSource)?.location else { return }
        postMouse(type: .rightMouseDown, at: location, button: .right)
        postMouse(type: .rightMouseUp, at: location, button: .right)
    }

    func mouseDown() {
        guard let location = CGEvent(source: eventSource)?.location else { return }
        postMouse(type: .leftMouseDown, at: location, button: .left)
    }

    func mouseUp() {
        guard let location = CGEvent(source: eventSource)?.location else { return }
        postMouse(type: .leftMouseUp, at: location, button: .left)
    }

    func scroll(vertical: Float, horizontal: Float) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(vertical.rounded()),
            wheel2: Int32(horizontal.rounded()),
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postMouse(type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        )?.post(tap: .cghidEventTap)
    }
}
