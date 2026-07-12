import CoreGraphics
import Foundation
import ImageIO
import ShrikeCore
import UniformTypeIdentifiers

// MARK: - Minimal test harness
// The Command Line Tools toolchain ships neither XCTest nor Swift Testing,
// so this target is a plain executable: `swift run shrike-tests`.

var failureCount = 0
var testCount = 0

struct TestAbort: Error {}

func expect(_ condition: Bool, _ message: String, line: UInt = #line) {
    if !condition {
        failureCount += 1
        print("    FAIL (line \(line)): \(message)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: UInt = #line) {
    expect(actual == expected, "\(label): expected \(expected), got \(actual)", line: line)
}

func require<T>(_ value: T?, _ message: String, line: UInt = #line) throws -> T {
    guard let value else {
        expect(false, "required value was nil: \(message)", line: line)
        throw TestAbort()
    }
    return value
}

func test(_ name: String, _ body: (URL) throws -> Void) {
    testCount += 1
    let before = failureCount
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("shrike-tests-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    } catch is TestAbort {
        // failure already recorded
    } catch {
        expect(false, "unexpected error: \(error)")
    }
    print("\(before == failureCount ? "PASS" : "FAIL")  \(name)")
}

// MARK: - Fixture and inspection helpers

/// Writes a blue image whose top-left quadrant is red (so rotation is
/// detectable). With `transparentLeftHalf`, the left half is fully cleared.
@discardableResult
func writeFixture(
    in directory: URL,
    name: String,
    width: Int,
    height: Int,
    format: ImageFormat,
    orientation: Int? = nil,
    exif: [String: Any]? = nil,
    transparentLeftHalf: Bool = false
) throws -> URL {
    let context = try require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), "fixture bitmap context")
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // CG origin is bottom-left, so the visual top half is the upper y range.
    context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height - height / 2))
    if transparentLeftHalf {
        context.clear(CGRect(x: 0, y: 0, width: width / 2, height: height))
    }
    let image = try require(context.makeImage(), "fixture image")

    let url = directory.appendingPathComponent(name)
    let destination = try require(CGImageDestinationCreateWithURL(
        url as CFURL, format.utTypeIdentifier as CFString, 1, nil
    ), "fixture image destination")
    var properties: [String: Any] = [:]
    if let orientation {
        properties[kCGImagePropertyOrientation as String] = orientation
    }
    if let exif {
        properties[kCGImagePropertyExifDictionary as String] = exif
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    expect(CGImageDestinationFinalize(destination), "fixture finalize")
    return url
}

func loadImage(_ url: URL) throws -> CGImage {
    let source = try require(CGImageSourceCreateWithURL(url as CFURL, nil), "image source for \(url.lastPathComponent)")
    return try require(CGImageSourceCreateImageAtIndex(source, 0, nil), "decode \(url.lastPathComponent)")
}

func imageType(_ url: URL) -> String? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceGetType(source) as String?
}

func imageProperties(_ url: URL) throws -> [String: Any] {
    let source = try require(CGImageSourceCreateWithURL(url as CFURL, nil), "image source for \(url.lastPathComponent)")
    return try require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any], "properties of \(url.lastPathComponent)")
}

func pixel(in image: CGImage, x: Int, y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    let context = try require(CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), "pixel-read context")
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = try require(context.data, "pixel-read data").assumingMemoryBound(to: UInt8.self)
    let offset = y * context.bytesPerRow + x * 4
    return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
}

func request(
    _ url: URL, pixels: Int, dimension: ResizeDimension = .width, copy: Bool = false
) -> ResizeRequest {
    ResizeRequest(sourceURL: url, pixels: pixels, dimension: dimension, makeCopy: copy)
}

// MARK: - Dimension math

test("width resize preserves aspect ratio") { _ in
    expectEqual(
        ImageResizer.targetSize(current: PixelSize(width: 4032, height: 3024), pixels: 800, dimension: .width),
        PixelSize(width: 800, height: 600), "target size"
    )
}

test("height resize preserves aspect ratio") { _ in
    expectEqual(
        ImageResizer.targetSize(current: PixelSize(width: 4032, height: 3024), pixels: 600, dimension: .height),
        PixelSize(width: 800, height: 600), "target size"
    )
}

test("rounds to nearest pixel") { _ in
    expectEqual(
        ImageResizer.targetSize(current: PixelSize(width: 1000, height: 333), pixels: 500, dimension: .width),
        PixelSize(width: 500, height: 167), "target size"
    )
}

test("never upscales width") { _ in
    let current = PixelSize(width: 400, height: 200)
    expectEqual(ImageResizer.targetSize(current: current, pixels: 400, dimension: .width), nil, "equal width")
    expectEqual(ImageResizer.targetSize(current: current, pixels: 800, dimension: .width), nil, "larger width")
}

test("never upscales height") { _ in
    let current = PixelSize(width: 400, height: 200)
    expectEqual(ImageResizer.targetSize(current: current, pixels: 200, dimension: .height), nil, "equal height")
    expectEqual(ImageResizer.targetSize(current: current, pixels: 500, dimension: .height), nil, "larger height")
}

test("extreme aspect ratio clamps to one pixel") { _ in
    expectEqual(
        ImageResizer.targetSize(current: PixelSize(width: 10000, height: 10), pixels: 100, dimension: .width),
        PixelSize(width: 100, height: 1), "target size"
    )
}

test("copy URL for width") { _ in
    let url = URL(fileURLWithPath: "/tmp/photos/photo.jpg")
    expectEqual(
        ImageResizer.copyURL(for: url, pixels: 800, dimension: .width).path,
        "/tmp/photos/photo-800w.jpg", "copy path"
    )
}

test("copy URL for height keeps extension case") { _ in
    let url = URL(fileURLWithPath: "/tmp/Pic.PNG")
    expectEqual(
        ImageResizer.copyURL(for: url, pixels: 600, dimension: .height).path,
        "/tmp/Pic-600h.PNG", "copy path"
    )
}

// MARK: - Resizing

test("resize by width in place, JPEG") { directory in
    let url = try writeFixture(in: directory, name: "photo.jpg", width: 400, height: 200, format: .jpeg)
    let outcome = try ImageResizer.run(request(url, pixels: 100))

    guard case .resized(let output, let from, let to) = outcome else {
        expect(false, "expected .resized, got \(outcome)")
        return
    }
    expectEqual(output, url, "output URL")
    expectEqual(from, PixelSize(width: 400, height: 200), "original size")
    expectEqual(to, PixelSize(width: 100, height: 50), "new size")
    expectEqual(imageType(url), UTType.jpeg.identifier, "output format")
    let image = try loadImage(url)
    expectEqual(image.width, 100, "decoded width")
    expectEqual(image.height, 50, "decoded height")
}

test("resize by height to copy, PNG") { directory in
    let url = try writeFixture(in: directory, name: "img.png", width: 400, height: 200, format: .png)
    let originalData = try Data(contentsOf: url)

    let outcome = try ImageResizer.run(request(url, pixels: 50, dimension: .height, copy: true))

    guard case .resized(let output, _, let to) = outcome else {
        expect(false, "expected .resized, got \(outcome)")
        return
    }
    expectEqual(output.lastPathComponent, "img-50h.png", "copy name")
    expectEqual(to, PixelSize(width: 100, height: 50), "new size")
    expectEqual(imageType(output), UTType.png.identifier, "output format")
    let copyImage = try loadImage(output)
    expectEqual(copyImage.width, 100, "copy width")
    expectEqual(copyImage.height, 50, "copy height")
    expect(try Data(contentsOf: url) == originalData, "original must be untouched")
}

test("repeated copy overwrites the same copy") { directory in
    let url = try writeFixture(in: directory, name: "photo.jpg", width: 400, height: 200, format: .jpeg)
    _ = try ImageResizer.run(request(url, pixels: 100, copy: true))
    _ = try ImageResizer.run(request(url, pixels: 100, copy: true))

    let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    expectEqual(contents.sorted(), ["photo-100w.jpg", "photo.jpg"], "directory contents")
}

// MARK: - No-upscale behavior

test("no upscale leaves the file untouched") { directory in
    let url = try writeFixture(in: directory, name: "small.jpg", width: 400, height: 200, format: .jpeg)
    let originalData = try Data(contentsOf: url)

    for pixels in [400, 500] {
        let outcome = try ImageResizer.run(request(url, pixels: pixels))
        guard case .noResizeNeeded(let copyURL, let current) = outcome else {
            expect(false, "expected .noResizeNeeded for \(pixels)px, got \(outcome)")
            return
        }
        expect(copyURL == nil, "no copy expected for \(pixels)px")
        expectEqual(current, PixelSize(width: 400, height: 200), "reported current size")
    }
    expect(try Data(contentsOf: url) == originalData, "file bytes must be unchanged")
}

test("no upscale with -c writes an unchanged copy") { directory in
    let url = try writeFixture(in: directory, name: "small.png", width: 400, height: 200, format: .png)
    let originalData = try Data(contentsOf: url)

    let outcome = try ImageResizer.run(request(url, pixels: 999, copy: true))
    guard case .noResizeNeeded(let copyURL, _) = outcome else {
        expect(false, "expected .noResizeNeeded, got \(outcome)")
        return
    }
    let copy = try require(copyURL, "copy URL")
    expectEqual(copy.lastPathComponent, "small-999w.png", "copy name")
    expect(try Data(contentsOf: copy) == originalData, "copy must be byte-identical")
}

// MARK: - EXIF orientation

test("oriented image is resized upright") { directory in
    // Orientation 6: stored 400×200, displayed as 200×400 (rotated 90° CW).
    // The stored top-left red quadrant lands in the displayed top-right.
    let url = try writeFixture(in: directory, name: "rotated.jpg", width: 400, height: 200, format: .jpeg, orientation: 6)

    let outcome = try ImageResizer.run(request(url, pixels: 100))
    guard case .resized(_, let from, let to) = outcome else {
        expect(false, "expected .resized, got \(outcome)")
        return
    }
    expectEqual(from, PixelSize(width: 200, height: 400), "displayed original size")
    expectEqual(to, PixelSize(width: 100, height: 200), "new size")

    let properties = try imageProperties(url)
    let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
    expectEqual(orientation, 1, "orientation flag must be reset once pixels are upright")

    let image = try loadImage(url)
    expectEqual(image.width, 100, "stored width")
    expectEqual(image.height, 200, "stored height")
    let topRight = try pixel(in: image, x: 75, y: 50)
    expect(topRight.r > 200 && topRight.b < 60, "top-right should be red after rotation, got \(topRight)")
    let topLeft = try pixel(in: image, x: 25, y: 50)
    expect(topLeft.b > 200, "top-left should be blue after rotation, got \(topLeft)")
    let bottomRight = try pixel(in: image, x: 75, y: 150)
    expect(bottomRight.b > 200, "bottom-right should be blue after rotation, got \(bottomRight)")
}

// MARK: - Metadata

test("EXIF is preserved and pixel dimensions updated") { directory in
    let date = "2020:01:02 03:04:05"
    let url = try writeFixture(
        in: directory, name: "meta.jpg", width: 400, height: 200, format: .jpeg,
        exif: [kCGImagePropertyExifDateTimeOriginal as String: date]
    )

    _ = try ImageResizer.run(request(url, pixels: 100))

    let properties = try imageProperties(url)
    let exif = try require(properties[kCGImagePropertyExifDictionary as String] as? [String: Any], "EXIF dictionary")
    expectEqual(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String, date, "DateTimeOriginal")
    expectEqual(exif[kCGImagePropertyExifPixelXDimension as String] as? Int, 100, "PixelXDimension")
    expectEqual(exif[kCGImagePropertyExifPixelYDimension as String] as? Int, 50, "PixelYDimension")
}

// MARK: - Transparency

test("PNG transparency is preserved") { directory in
    let url = try writeFixture(
        in: directory, name: "alpha.png", width: 400, height: 200, format: .png, transparentLeftHalf: true
    )

    _ = try ImageResizer.run(request(url, pixels: 100))

    let image = try loadImage(url)
    let transparent = try pixel(in: image, x: 25, y: 25)
    expectEqual(transparent.a, 0, "left half should stay transparent")
    let opaque = try pixel(in: image, x: 75, y: 25)
    expect(opaque.a == 255 && opaque.b > 200, "right half should stay opaque blue, got \(opaque)")
}

// MARK: - Validation errors

test("missing file is rejected") { directory in
    let url = directory.appendingPathComponent("nope.jpg")
    do {
        _ = try ImageResizer.run(request(url, pixels: 100))
        expect(false, "expected fileNotFound error")
    } catch let error as ShrikeError {
        expectEqual(error, .fileNotFound(url.path), "error")
    }
}

test("extension mismatch is rejected") { directory in
    let png = try writeFixture(in: directory, name: "real.png", width: 40, height: 20, format: .png)
    let fake = directory.appendingPathComponent("fake.jpg")
    try FileManager.default.copyItem(at: png, to: fake)

    do {
        _ = try ImageResizer.run(request(fake, pixels: 10))
        expect(false, "expected extensionMismatch error")
    } catch let error as ShrikeError {
        expectEqual(error, .extensionMismatch(fake.path, actualFormat: .png), "error")
    }
}

test("non-image file is rejected") { directory in
    let url = directory.appendingPathComponent("junk.jpg")
    try Data("definitely not an image".utf8).write(to: url)

    do {
        _ = try ImageResizer.run(request(url, pixels: 10))
        expect(false, "expected an error for a non-image file")
    } catch is ShrikeError {
        // expected
    }
}

// MARK: - Summary

print("\n\(testCount) tests, \(failureCount) failure\(failureCount == 1 ? "" : "s")")
exit(failureCount == 0 ? 0 : 1)
