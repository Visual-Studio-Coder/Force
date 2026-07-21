import CoreGraphics

@MainActor
final class CursorController {
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private var pendingMovement = CGVector.zero
    private var movementTask: Task<Void, Never>?

    func moveBy(dx: CGFloat, dy: CGFloat) {
        pendingMovement.dx += dx
        pendingMovement.dy += dy
        startMovementLoopIfNeeded()
    }

    func leftClick() {
        flushPendingMovement()
        guard let location = CGEvent(source: eventSource)?.location else { return }
        postMouse(type: .leftMouseDown, at: location, button: .left)
        postMouse(type: .leftMouseUp, at: location, button: .left)
    }

    func rightClick() {
        flushPendingMovement()
        guard let location = CGEvent(source: eventSource)?.location else { return }
        postMouse(type: .rightMouseDown, at: location, button: .right)
        postMouse(type: .rightMouseUp, at: location, button: .right)
    }

    func mouseDown() {
        flushPendingMovement()
        guard let location = CGEvent(source: eventSource)?.location else { return }
        postMouse(type: .leftMouseDown, at: location, button: .left)
    }

    func mouseUp() {
        flushPendingMovement()
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

    private func startMovementLoopIfNeeded() {
        guard movementTask == nil else { return }

        movementTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let remainingDistance = hypot(pendingMovement.dx, pendingMovement.dy)
                guard remainingDistance >= 0.1 else {
                    pendingMovement = .zero
                    movementTask = nil
                    return
                }

                let step = CGVector(
                    dx: pendingMovement.dx * 0.65,
                    dy: pendingMovement.dy * 0.65
                )
                pendingMovement.dx -= step.dx
                pendingMovement.dy -= step.dy
                postMovement(step)

                try? await Task.sleep(for: .milliseconds(16))
            }

            movementTask = nil
        }
    }

    private func flushPendingMovement() {
        guard pendingMovement != .zero else { return }
        let remaining = pendingMovement
        pendingMovement = .zero
        postMovement(remaining)
    }

    private func postMovement(_ movement: CGVector) {
        guard let current = CGEvent(source: eventSource)?.location else { return }
        let destination = CGPoint(
            x: current.x + movement.dx,
            y: current.y + movement.dy
        )
        postMouse(type: .mouseMoved, at: destination, button: .left)
    }
}
