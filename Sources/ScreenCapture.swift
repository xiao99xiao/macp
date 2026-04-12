import AppKit
import CoreGraphics

/// Captures screenshots of windows or the entire screen, returning base64 PNG data.
/// Images are automatically downscaled to keep base64 output within MCP transport limits.
final class ScreenCapture {

    static let shared = ScreenCapture()

    /// Max dimension (width or height) for output images.
    /// 1280px keeps most screenshots under 1-2MB base64, readable by Claude without context bloat.
    private let maxDimension: CGFloat = 1280

    /// Capture the entire main screen
    func captureScreen() -> String? {
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else {
            return nil
        }
        return pngBase64(from: cgImage)
    }

    /// Capture a specific window by its owning PID, optionally by window index
    func captureWindow(pid: pid_t, windowIndex: Int = 0) -> String? {
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []

        var matchCount = 0
        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID] as? pid_t,
                  windowPID == pid,
                  let windowID = windowInfo[kCGWindowNumber] as? CGWindowID,
                  let layer = windowInfo[kCGWindowLayer] as? Int,
                  layer == 0
            else { continue }

            if matchCount == windowIndex {
                if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution]) {
                    return pngBase64(from: cgImage)
                }
                return nil
            }
            matchCount += 1
        }
        return nil
    }

    /// Capture a region of the screen
    func captureRegion(x: Int, y: Int, width: Int, height: Int) -> String? {
        let rect = CGRect(x: x, y: y, width: width, height: height)
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID(), rect: rect) else {
            return nil
        }
        return pngBase64(from: cgImage)
    }

    // MARK: - Helpers

    private func pngBase64(from cgImage: CGImage) -> String? {
        let scaled = downscaleIfNeeded(cgImage)
        let bitmapRep = NSBitmapImageRep(cgImage: scaled)
        guard let pngData = bitmapRep.representation(using: .png, properties: [.interlaced: false]) else {
            return nil
        }
        return pngData.base64EncodedString()
    }

    private func downscaleIfNeeded(_ cgImage: CGImage) -> CGImage {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let longerSide = max(w, h)

        guard longerSide > maxDimension else { return cgImage }

        let scale = maxDimension / longerSide
        let newW = Int(w * scale)
        let newH = Int(h * scale)

        guard let context = CGContext(
            data: nil,
            width: newW, height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cgImage }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return context.makeImage() ?? cgImage
    }
}
