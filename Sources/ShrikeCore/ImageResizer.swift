import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ResizeDimension: String, Sendable {
    case width
    case height
}

public enum ImageFormat: Equatable, Sendable {
    case jpeg
    case png

    public var utTypeIdentifier: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        }
    }

    var validExtensions: [String] {
        switch self {
        case .jpeg: return ["jpg", "jpeg"]
        case .png: return ["png"]
        }
    }

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        }
    }
}

public struct PixelSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum ShrikeError: Error, Equatable, CustomStringConvertible {
    case fileNotFound(String)
    case notAnImage(String)
    case unsupportedFormat(String, actualType: String)
    case extensionMismatch(String, actualFormat: ImageFormat)
    case decodeFailed(String)
    case writeFailed(String, reason: String)

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "no such file: \(path)"
        case .notAnImage(let path):
            return "\(path) is not a readable image"
        case .unsupportedFormat(let path, let actualType):
            return "\(path) has unsupported type '\(actualType)' — shrike only handles JPEG and PNG"
        case .extensionMismatch(let path, let actualFormat):
            return "\(path) is actually a \(actualFormat.displayName); its file extension doesn't match the content"
        case .decodeFailed(let path):
            return "could not decode \(path)"
        case .writeFailed(let path, let reason):
            return "could not write \(path): \(reason)"
        }
    }
}

public struct ResizeRequest {
    public let sourceURL: URL
    public let pixels: Int
    public let dimension: ResizeDimension
    public let makeCopy: Bool

    public init(sourceURL: URL, pixels: Int, dimension: ResizeDimension, makeCopy: Bool) {
        self.sourceURL = sourceURL
        self.pixels = pixels
        self.dimension = dimension
        self.makeCopy = makeCopy
    }
}

public enum ResizeOutcome {
    case resized(URL, from: PixelSize, to: PixelSize)
    /// The image already fits within the requested size. `copyURL` points to
    /// the unchanged copy when one was requested, nil otherwise.
    case noResizeNeeded(copyURL: URL?, current: PixelSize)
}

public enum ImageResizer {

    public static let jpegQuality: Double = 0.85

    /// The size the image should be scaled to, or nil when the image already
    /// fits within `pixels` along `dimension` — shrike never upscales.
    public static func targetSize(current: PixelSize, pixels: Int, dimension: ResizeDimension) -> PixelSize? {
        switch dimension {
        case .width:
            guard pixels < current.width else { return nil }
            let height = max(1, Int((Double(current.height) * Double(pixels) / Double(current.width)).rounded()))
            return PixelSize(width: pixels, height: height)
        case .height:
            guard pixels < current.height else { return nil }
            let width = max(1, Int((Double(current.width) * Double(pixels) / Double(current.height)).rounded()))
            return PixelSize(width: width, height: pixels)
        }
    }

    /// photo.jpg resized to 800 wide → photo-800w.jpg in the same directory.
    public static func copyURL(for source: URL, pixels: Int, dimension: ResizeDimension) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        let suffix = dimension == .width ? "w" : "h"
        return source.deletingLastPathComponent()
            .appendingPathComponent("\(stem)-\(pixels)\(suffix)")
            .appendingPathExtension(source.pathExtension)
    }

    public static func run(_ request: ResizeRequest) throws -> ResizeOutcome {
        let fileManager = FileManager.default
        let source = request.sourceURL
        let displayPath = source.path

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw ShrikeError.fileNotFound(displayPath)
        }
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let utType = CGImageSourceGetType(imageSource) as String? else {
            throw ShrikeError.notAnImage(displayPath)
        }
        let format = try detectFormat(utType: utType, fileExtension: source.pathExtension, displayPath: displayPath)

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let storedWidth = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let storedHeight = properties[kCGImagePropertyPixelHeight as String] as? Int else {
            throw ShrikeError.decodeFailed(displayPath)
        }
        let orientation = (properties[kCGImagePropertyOrientation as String] as? UInt32) ?? 1
        // EXIF orientations 5–8 store the pixels rotated 90°, so the size as
        // displayed is the stored size swapped.
        let current = orientation >= 5
            ? PixelSize(width: storedHeight, height: storedWidth)
            : PixelSize(width: storedWidth, height: storedHeight)

        guard let target = targetSize(current: current, pixels: request.pixels, dimension: request.dimension) else {
            if request.makeCopy {
                let destination = copyURL(for: source, pixels: request.pixels, dimension: request.dimension)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
                return .noResizeNeeded(copyURL: destination, current: current)
            }
            return .noResizeNeeded(copyURL: nil, current: current)
        }

        // Decode at full size with the EXIF orientation baked into the pixels,
        // so the scaling below works on upright pixels and the output needs no
        // orientation flag.
        let uprightOptions: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: max(current.width, current.height),
        ]
        guard let upright = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, uprightOptions as CFDictionary),
              let scaled = scale(upright, to: target, format: format) else {
            throw ShrikeError.decodeFailed(displayPath)
        }

        let destination = request.makeCopy
            ? copyURL(for: source, pixels: request.pixels, dimension: request.dimension)
            : source
        let outputProps = outputProperties(from: properties, target: target, format: format)
        try write(scaled, format: format, properties: outputProps, to: destination)
        return .resized(destination, from: current, to: target)
    }

    static func detectFormat(utType: String, fileExtension: String, displayPath: String) throws -> ImageFormat {
        let format: ImageFormat
        switch utType {
        case UTType.jpeg.identifier: format = .jpeg
        case UTType.png.identifier: format = .png
        default: throw ShrikeError.unsupportedFormat(displayPath, actualType: utType)
        }
        guard format.validExtensions.contains(fileExtension.lowercased()) else {
            throw ShrikeError.extensionMismatch(displayPath, actualFormat: format)
        }
        return format
    }

    static func scale(_ image: CGImage, to size: PixelSize, format: ImageFormat) -> CGImage? {
        let colorSpace: CGColorSpace
        if let sourceSpace = image.colorSpace, sourceSpace.model == .rgb {
            colorSpace = sourceSpace
        } else {
            colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        }
        // JPEG cannot store alpha; PNG keeps its transparency.
        let alphaInfo: CGImageAlphaInfo = format == .png ? .premultipliedLast : .noneSkipLast
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: alphaInfo.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }

    static func outputProperties(from source: [String: Any], target: PixelSize, format: ImageFormat) -> [String: Any] {
        var output = source
        // The pixels are written upright, so every copy of the orientation flag
        // must be reset or viewers would rotate the image a second time.
        output[kCGImagePropertyOrientation as String] = 1
        if var tiff = output[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            output[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        if var exif = output[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = target.width
            exif[kCGImagePropertyExifPixelYDimension as String] = target.height
            output[kCGImagePropertyExifDictionary as String] = exif
        }
        output[kCGImagePropertyPixelWidth as String] = target.width
        output[kCGImagePropertyPixelHeight as String] = target.height
        if format == .jpeg {
            output[kCGImageDestinationLossyCompressionQuality as String] = jpegQuality
        }
        return output
    }

    static func write(_ image: CGImage, format: ImageFormat, properties: [String: Any], to destination: URL) throws {
        let fileManager = FileManager.default
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".shrike-\(UUID().uuidString).tmp")
        guard let imageDestination = CGImageDestinationCreateWithURL(
            temporary as CFURL, format.utTypeIdentifier as CFString, 1, nil
        ) else {
            throw ShrikeError.writeFailed(destination.path, reason: "could not create output file")
        }
        CGImageDestinationAddImage(imageDestination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else {
            try? fileManager.removeItem(at: temporary)
            throw ShrikeError.writeFailed(destination.path, reason: "encoding failed")
        }
        do {
            // The original is never truncated: the new file is written fully to
            // a temp path in the same directory, then swapped in atomically.
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw ShrikeError.writeFailed(destination.path, reason: error.localizedDescription)
        }
    }
}
