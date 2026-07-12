import ArgumentParser
import Foundation
import ShrikeCore

@main
struct Shrike: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shrike",
        abstract: "Shrink a JPEG or PNG image to a target width or height.",
        discussion: """
            Scales images down, preserving the aspect ratio and the original \
            format (JPEG stays JPEG, PNG stays PNG). Never upscales: if the \
            image already fits within the requested size, nothing changes.

            By default the original file is overwritten in place. The write is \
            atomic, so a failure never corrupts the original. Pass -c to write \
            a new file next to it instead, named after the target size \
            (photo.jpg → photo-800w.jpg, or photo-600h.jpg with --height).
            """,
        version: "0.1.0"
    )

    @Argument(help: "Path to the JPEG or PNG image.")
    var path: String

    @Argument(help: "Target size in pixels.")
    var pixels: Int

    @Flag(help: "Resize by height instead of width.")
    var height = false

    @Flag(
        name: [.customShort("c"), .customLong("copy")],
        help: "Write the result to a new file (e.g. photo-800w.jpg) instead of overwriting."
    )
    var copy = false

    func validate() throws {
        guard pixels > 0 else {
            throw ValidationError("<pixels> must be a positive number; got \(pixels).")
        }
    }

    func run() throws {
        let request = ResizeRequest(
            sourceURL: URL(fileURLWithPath: path),
            pixels: pixels,
            dimension: height ? .height : .width,
            makeCopy: copy
        )
        let outcome: ResizeOutcome
        do {
            outcome = try ImageResizer.run(request)
        } catch let error as ShrikeError {
            FileHandle.standardError.write(Data("shrike: \(error.description)\n".utf8))
            throw ExitCode(2)
        }

        switch outcome {
        case .resized(let output, let from, let to):
            print("\(output.path): \(from.width)×\(from.height) → \(to.width)×\(to.height)")
        case .noResizeNeeded(let copyURL, let current):
            let axis = height ? "tall" : "wide"
            let currentPixels = height ? current.height : current.width
            var message = "\(path) is already \(currentPixels)px \(axis) (≤ \(pixels)); not resized."
            if let copyURL {
                message += " Unchanged copy written to \(copyURL.path)."
            }
            print(message)
        }
    }
}
