import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes an animated GIF from a sequence of frames. Frames are buffered and
/// written on `finalize()` because CGImageDestination wants the frame count
/// up front.
public final class GIFWriter {
    public enum GIFError: Error {
        case cannotCreateDestination
        case noFrames
        case finalizeFailed
    }

    private let url: URL
    private let frameDelay: TimeInterval
    private let loopForever: Bool
    private var frames: [CGImage] = []

    public var frameCount: Int { frames.count }

    public init(url: URL, frameDelay: TimeInterval, loopForever: Bool = true) {
        self.url = url
        self.frameDelay = frameDelay
        self.loopForever = loopForever
    }

    public func add(frame: CGImage) {
        frames.append(frame)
    }

    public func finalize() throws {
        guard !frames.isEmpty else { throw GIFError.noFrames }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil
        ) else {
            throw GIFError.cannotCreateDestination
        }
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: loopForever ? 0 : 1
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
            ]
        ]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw GIFError.finalizeFailed
        }
    }
}
