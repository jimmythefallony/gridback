import Foundation

/// Live page position while a swipe is in progress, and where it should settle.
public enum PageSnap {
    /// How far ahead a flick looks, in seconds, when choosing the landing page.
    public static let flickLookahead: Double = 0.25

    /// Page index after the fingers lift.
    ///
    /// `translationX` and `velocityX` are positive when the fingers move right,
    /// which moves toward the previous page.
    public static func destination(
        currentPage: Int,
        pageCount: Int,
        translationX: Double,
        velocityX: Double,
        pageWidth: Double
    ) -> Int {
        guard pageCount > 0, pageWidth > 0 else { return 0 }
        let projected = translationX + velocityX * flickLookahead
        let raw = Double(currentPage) - projected / pageWidth
        let nearest = Int(raw.rounded())
        return min(max(nearest, 0), pageCount - 1)
    }

    /// Fractional page while the fingers are down. Pulling past the first or
    /// last page rubber-bands instead of moving one point per point.
    public static func visualPage(
        currentPage: Int,
        pageCount: Int,
        translationX: Double,
        pageWidth: Double
    ) -> Double {
        guard pageCount > 0, pageWidth > 0 else { return 0 }
        let last = pageCount - 1
        let proposed = Double(currentPage) - translationX / pageWidth
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
        samples.append((time, translationX))
        if samples.count > 6 {
            samples.removeFirst(samples.count - 6)
        }
    }

    public var isMostlyHorizontal: Bool {
        abs(translationX) > abs(translationY)
    }

    /// Points per second. Positive when the fingers are moving right.
    public func velocityX() -> Double {
        guard let first = samples.first, let last = samples.last, last.time > first.time else {
            return 0
        }
        return (last.x - first.x) / (last.time - first.time)
    }
}
