import SwiftUI

/// Fixed palette matching the shrike-ui.png template: one blue throughout
/// (window, title bar, tiles), tiles drawn as dashed outlines on it. The
/// window keeps this look in both system appearances (the root view forces
/// dark controls).
enum Theme {
    /// The one blue everything sits on; dark mode swaps it for a classic
    /// dark-grey appearance instead.
    static func background(dark: Bool) -> Color {
        dark
            ? Color(red: 0.13, green: 0.13, blue: 0.14)
            : Color(red: 0.18, green: 0.38, blue: 0.64)
    }

    static let tileBorder = Color.white.opacity(0.5)
    static let tileBorderTargeted = Color.white.opacity(0.95)
    static let tileTargetedOverlay = Color.white.opacity(0.12)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textError = Color(red: 1.0, green: 0.6, blue: 0.55)
}
