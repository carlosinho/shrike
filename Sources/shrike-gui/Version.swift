/// The GUI app's version — the single source of truth for Shrike.app,
/// independent of the CLI's version (`CommandConfiguration(version:)` in
/// Sources/shrike/Shrike.swift). The two front-ends ship on their own
/// schedules and their numbers are unrelated.
///
/// scripts/make-app.sh extracts this value for the bundle's
/// CFBundleShortVersionString, so keep the line's exact shape:
///     static let current = "X.Y.Z"
enum GUIVersion {
    static let current = "0.1.0"
}
