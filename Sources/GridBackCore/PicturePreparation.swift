import Foundation

/// Odd box widths whose repeated passes approximate a Gaussian of `sigma` pixels.
/// The blur itself runs on the calling thread; these sizes are only the kernel choice.
public enum GaussianBoxKernel {
    public static func sizes(sigma: Double, passes: Int = 3) -> [Int] {
        let count = max(passes, 1)
        let s = max(sigma, 0)
        let ideal = (12 * s * s / Double(count) + 1).squareRoot()
        var narrow = Int(ideal.rounded(.down))
        if narrow % 2 == 0 { narrow -= 1 }
        if narrow < 1 { narrow = 1 }
        let wide = narrow + 2
        let denominator = -4 * Double(narrow) - 4
        let numerator = 12 * s * s - Double(count * narrow * narrow) - 4 * Double(count * narrow) - 3 * Double(count)
        let idealNarrowPasses = denominator == 0 ? 0 : numerator / denominator
        let narrowPasses = min(max(Int(idealNarrowPasses.rounded()), 0), count)
        return (0..<count).map { $0 < narrowPasses ? narrow : wide }
    }
}


/// Whether a wallpaper render that finished in the background may still be shown.
/// A close, a newer open, or a different screen or wallpaper makes it stale.
public enum PictureApplyGate {
    public static func shouldApply(
        completedGeneration: Int,
        completedCacheKey: String,
        currentGeneration: Int,
        currentCacheKey: String,
        stillWanted: Bool
    ) -> Bool {
        stillWanted
            && completedGeneration == currentGeneration
            && completedCacheKey == currentCacheKey
    }
}

/// Runs picture preparation off the main thread, then delivers the result on main.
/// The main thread does not wait, so it cannot block on lower-priority work.
public enum OffMainWork {
    private static let queue = DispatchQueue(
        label: "com.jimmythefallony.GridBack.picture",
        qos: .userInitiated
    )

    public static func start<T>(
        work: @escaping () -> T,
        apply: @escaping (T) -> Void
    ) {
        queue.async {
            let value = work()
            DispatchQueue.main.async {
                apply(value)
            }
        }
    }
}
