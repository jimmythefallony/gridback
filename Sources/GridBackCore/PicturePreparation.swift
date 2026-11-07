import Foundation

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
