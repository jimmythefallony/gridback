import Foundation

/// Live page position while a swipe is in progress, and where it should settle.
public enum PageSnap {
    /// How much of the page a drag must cross before it turns, with no flick.
    public static let commitDistanceFraction: Double = 0.20

    /// Release speed, in points per second, that can turn the page on its own.
    public static let flickSpeed: Double = 350

    /// Shortest drag, in points, that a flick is allowed to finish.
    public static let flickMinimumDistance: Double = 16

    /// Settle spring length, in seconds. The spring has no bounce.
    public static let settleSpringDuration: Double = 0.38

    /// Settle used while Reduce Motion is on, in seconds. It does not inherit speed.
    public static let reduceMotionSettleDuration: Double = 0.15

    /// Remaining distance, in points, that is close enough to set in place.
    public static let settleSnapDistance: Double = 1

    /// Fastest inherited settle, as multiples of the remaining distance per second.
    public static let settleVelocityCap: Double = 8

    /// Page index after the fingers lift. At most one page away.
    ///
    /// `translationX` and `velocityX` are positive when the fingers move right,
    /// which moves toward the previous page. A drag of `commitDistanceFraction`
    /// of the page turns. A shorter drag turns only when it is released at
    /// `flickSpeed` or faster, after moving at least `flickMinimumDistance`,
    /// and the release still points the same way. A flick back toward the start
    /// cancels. The ends stay put.
    public static func destination(
        currentPage: Int,
        pageCount: Int,
        translationX: Double,
        velocityX: Double,
        pageWidth: Double
    ) -> Int {
        guard pageCount > 0, pageWidth > 0 else { return 0 }
        let page = min(max(currentPage, 0), pageCount - 1)
        let travel = abs(translationX)
        guard travel > 0 else { return page }

        let towardPrevious = translationX > 0
        let speed = abs(velocityX)
        let velocityOpposes = velocityX != 0 && (velocityX > 0) != towardPrevious
        if velocityOpposes && speed >= flickSpeed {
            return page
        }

        let draggedFarEnough = travel >= commitDistanceFraction * pageWidth
        let flicked = speed >= flickSpeed && travel >= flickMinimumDistance
        guard draggedFarEnough || flicked else { return page }

        let turned = page + (towardPrevious ? -1 : 1)
        return min(max(turned, 0), pageCount - 1)
    }

    /// `initialVelocity` for the settle spring.
    ///
    /// `pagesPerSecond` is positive when the page moves toward later pages.
    /// `remainingPages` is the signed distance still left. The result is that
    /// speed divided by the remaining distance when both point at the landing
    /// page, capped at `settleVelocityCap`. A finger moving the other way
    /// contributes nothing, and a gap under `settleSnapDistance` does too.
    /// Positive means "toward the landing page", which is what the spring expects.
    public static func settleInitialVelocity(
        pagesPerSecond: Double,
        remainingPages: Double,
        pageWidth: Double
    ) -> Double {
        guard pageWidth > 0, pagesPerSecond.isFinite, remainingPages.isFinite else { return 0 }
        let remainingPoints = remainingPages * pageWidth
        guard abs(remainingPoints) >= settleSnapDistance else { return 0 }
        let along = pagesPerSecond * (remainingPages > 0 ? 1 : -1)
        guard along > 0 else { return 0 }
        let normalized = along / abs(remainingPages)
        guard normalized.isFinite else { return 0 }
        return min(normalized, settleVelocityCap)
    }

    /// Fractional page while the fingers are down. `currentPage` may sit between
    /// pages when a new swipe starts during a settle. Pulling past the first or
    /// last page rubber-bands instead of moving one point per point.
    public static func visualPage(
        currentPage: Double,
        pageCount: Int,
        translationX: Double,
        pageWidth: Double
    ) -> Double {
        guard pageCount > 0, pageWidth > 0 else { return 0 }
        let last = pageCount - 1
        let proposed = currentPage - translationX / pageWidth
        if proposed < 0 {
            let overscroll = -proposed * pageWidth
            return -rubberBand(overscroll, dimension: pageWidth) / pageWidth
        }
        if proposed > Double(last) {
            let overscroll = (proposed - Double(last)) * pageWidth
            return Double(last) + rubberBand(overscroll, dimension: pageWidth) / pageWidth
        }
        return proposed
    }

    /// Resisted distance. The result is never farther than `offset`.
    public static func rubberBand(_ offset: Double, dimension: Double) -> Double {
        let dim = max(abs(dimension), 1)
        let distance = abs(offset)
        let banded = (1.0 - (1.0 / ((distance * 0.55 / dim) + 1.0))) * dim
        let limited = min(banded, distance)
        return offset < 0 ? -limited : limited
    }
}

/// Accumulates one trackpad swipe so the grid can follow the fingers.
public struct PageDragTracker: Sendable {
    /// How much recent movement counts toward release speed, in seconds.
    public static let velocityWindow: Double = 0.07

    public private(set) var translationX: Double
    public private(set) var translationY: Double
    private var samples: [(time: Double, x: Double)]
    private var armed: Bool

    public init() {
        translationX = 0
        translationY = 0
        samples = []
        armed = false
    }

    public mutating func reset() {
        translationX = 0
        translationY = 0
        samples = []
        armed = false
    }

    public mutating func add(deltaX: Double, deltaY: Double, time: Double) {
        if !armed {
            reset()
            armed = true
        }
        translationX += deltaX
        translationY += deltaY
        // A stationary sample has no movement. Keeping it would stretch the
        // slope across a pause and report a speed that is too low.
        if deltaX != 0 || deltaY != 0 {
            samples.append((time, translationX))
        }
        let cutoff = time - Self.velocityWindow
        samples.removeAll { $0.time < cutoff }
    }

    public var isMostlyHorizontal: Bool {
        abs(translationX) > abs(translationY)
    }

    /// Points per second over the last `velocityWindow`, ending at the latest
    /// event. Positive when the fingers are moving right. Stationary samples
    /// and anything older than the window are left out. The newest moving
    /// sample is the end of the slope.
    public func velocityX() -> Double {
        guard let first = samples.first, let last = samples.last, last.time > first.time else {
            return 0
        }
        return (last.x - first.x) / (last.time - first.time)
    }
}
