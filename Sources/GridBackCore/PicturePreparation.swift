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

/// What to put behind the grid once a wallpaper attempt has finished.
/// A missing picture is not saved, so the next open tries again.
public enum WallpaperBackdrop: Equatable, Sendable {
    case picture
    case plainBlur
    case ignore
}

public enum WallpaperBackdropChoice {
    public static func choose(
        hasPicture: Bool,
        completedGeneration: Int,
        completedCacheKey: String,
        currentGeneration: Int,
        currentCacheKey: String,
        stillWanted: Bool
    ) -> WallpaperBackdrop {
        guard PictureApplyGate.shouldApply(
            completedGeneration: completedGeneration,
            completedCacheKey: completedCacheKey,
            currentGeneration: currentGeneration,
            currentCacheKey: currentCacheKey,
            stillWanted: stillWanted
        ) else { return .ignore }
        return hasPicture ? .picture : .plainBlur
    }
}

/// Pixel size of the blurred desktop picture, and the blur radius that matches it.
/// The picture is a quarter of the screen. The radius uses that same scale, so the
/// blur still reads the same when the picture is shown full screen.
public struct WallpaperRenderSize: Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// Longest side to request from the image decoder, in pixels.
    public var maxPixelSize: Int
    public var sigma: Double

    public static let downscale = 4
    /// On-screen blur radius, in points, before it is scaled to the bitmap.
    public static let pointRadius = 52.0

    public init(width: Int, height: Int, maxPixelSize: Int, sigma: Double) {
        self.width = width
        self.height = height
        self.maxPixelSize = maxPixelSize
        self.sigma = sigma
    }

    public static func make(pixelWidth: Int, pixelHeight: Int, pointHeight: Double) -> WallpaperRenderSize {
        let width = max(pixelWidth / downscale, 1)
        let height = max(pixelHeight / downscale, 1)
        let sigma = pointRadius * Double(height) / max(pointHeight, 1)
        return WallpaperRenderSize(
            width: width,
            height: height,
            maxPixelSize: max(width, height),
            sigma: sigma
        )
    }
}

/// Runs picture preparation off the main thread, then delivers the result on main.
/// The work stays at Default QoS, the same class ImageIO uses to decode, so this
/// thread does not wait on a lower one. The main thread does not wait either.
public enum OffMainWork {
    private static let queue = DispatchQueue(
        label: "com.jimmythefallony.GridBack.picture",
        qos: .default
    )

    public static func start<T>(
        work: @escaping () -> T,
        apply: @escaping (T) -> Void
    ) {
        // Keep Default even when the caller is the main thread.
        queue.async(qos: .default, flags: .enforceQoS) {
            let value = work()
            DispatchQueue.main.async {
                apply(value)
            }
        }
    }
}
