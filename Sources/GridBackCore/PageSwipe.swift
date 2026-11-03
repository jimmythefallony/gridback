import Foundation

public enum PageTurn: Equatable, Sendable {
    /// Fingers moved right, so the previous page comes into view.
    case previous
    /// Fingers moved left, so the next page comes into view.
    case next
}

public enum PageSwipePhase: Equatable, Sendable {
    case began
    case changed
    case ended
    case cancelled
}

/// One two-finger swipe. A mostly horizontal swipe turns exactly one page.
public struct PageSwipeTracker: Equatable, Sendable {
    public var minimumDistance: Double
    private var accumulatedX: Double
    private var accumulatedY: Double
    private var armed: Bool
    private var hasFired: Bool

    public init(minimumDistance: Double = 56) {
        self.minimumDistance = minimumDistance
        accumulatedX = 0
        accumulatedY = 0
        armed = false
        hasFired = false
    }

    public mutating func reset() {
        accumulatedX = 0
        accumulatedY = 0
        armed = false
        hasFired = false
    }

    /// `deltaX` is positive when the fingers move right.
    public mutating func update(deltaX: Double, deltaY: Double, phase: PageSwipePhase) -> PageTurn? {
        switch phase {
        case .began:
            accumulatedX = deltaX
            accumulatedY = deltaY
            armed = true
            hasFired = false
            return fireIfReady()
        case .changed:
            if !armed {
                accumulatedX = 0
                accumulatedY = 0
                armed = true
                hasFired = false
            }
            guard !hasFired else { return nil }
            accumulatedX += deltaX
            accumulatedY += deltaY
            return fireIfReady()
        case .ended:
            defer { reset() }
            guard armed, !hasFired else { return nil }
            accumulatedX += deltaX
            accumulatedY += deltaY
            return fireIfReady()
        case .cancelled:
            reset()
            return nil
        }
    }

    private mutating func fireIfReady() -> PageTurn? {
        guard armed, !hasFired else { return nil }
        guard abs(accumulatedX) >= minimumDistance, abs(accumulatedX) > abs(accumulatedY) else {
            return nil
        }
        hasFired = true
        return accumulatedX > 0 ? .previous : .next
    }
}
