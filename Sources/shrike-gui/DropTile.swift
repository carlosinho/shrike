import SwiftUI
import ShrikeCore

/// One preset square: drop a file (or several) on it to shrink to `pixels`.
struct DropTile: View {
    static let side: CGFloat = 160

    let pixels: Int
    let dimension: ResizeDimension
    let makeCopy: Bool

    private enum Status {
        case idle
        case working
        case finished(message: String, failed: Bool)
    }

    @State private var status: Status = .idle
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34))
                .foregroundStyle(Theme.textSecondary)
            Text("\(pixels) px")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            statusLine
        }
        .frame(width: Self.side, height: Self.side)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Theme.tileTargetedOverlay : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Theme.tileBorderTargeted : Theme.tileBorder,
                    style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])
                )
        )
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            process(urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .idle:
            Text("Drop here")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        case .working:
            ProgressView()
                .controlSize(.small)
        case .finished(let message, let failed):
            Text(message)
                .font(.callout)
                .foregroundStyle(failed ? Theme.textError : Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .help(message)
        }
    }

    /// Runs the resizes off the main thread, one file at a time, then shows
    /// a per-file result (single drop) or a tally (multi-file drop).
    private func process(_ urls: [URL]) {
        status = .working
        let pixels = pixels
        let dimension = dimension
        let makeCopy = makeCopy
        Task.detached(priority: .userInitiated) {
            var messages: [String] = []
            var failures = 0
            for url in urls {
                let request = ResizeRequest(
                    sourceURL: url, pixels: pixels, dimension: dimension, makeCopy: makeCopy
                )
                do {
                    switch try ImageResizer.run(request) {
                    case .resized(_, let from, let to):
                        messages.append("\(from.width)×\(from.height) → \(to.width)×\(to.height)")
                    case .noResizeNeeded:
                        messages.append("Already \(pixels)px or smaller; not resized")
                    }
                } catch let error as ShrikeError {
                    failures += 1
                    messages.append(error.description)
                } catch {
                    failures += 1
                    messages.append(error.localizedDescription)
                }
            }
            let summary: String
            if urls.count == 1 {
                summary = messages[0]
            } else if failures == 0 {
                summary = "\(urls.count) images done"
            } else {
                summary = "\(urls.count - failures) done, \(failures) failed"
            }
            let failed = failures > 0
            await MainActor.run {
                status = .finished(message: summary, failed: failed)
            }
        }
    }
}
