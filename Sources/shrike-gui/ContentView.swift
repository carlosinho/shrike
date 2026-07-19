import SwiftUI
import ShrikeCore

struct ContentView: View {
    // The four tile sizes, persisted in UserDefaults (defaults per shrike-ui.png).
    // The GUI's one piece of state; core and CLI remain stateless.
    @AppStorage("presetSize1") private var preset1 = 800
    @AppStorage("presetSize2") private var preset2 = 1000
    @AppStorage("presetSize3") private var preset3 = 1200
    @AppStorage("presetSize4") private var preset4 = 1800

    @AppStorage("darkMode") private var darkMode = false

    @State private var dimension: ResizeDimension = .width
    // Copy is on by default in the GUI: a mis-drop should produce a -800w
    // copy, not silently overwrite the original (the CLI defaults to in-place).
    @State private var makeCopy = true
    @State private var showingPresetSettings = false

    private static let appIcon: NSImage? = Bundle.module
        .url(forResource: "Shrike", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    private let columns = [
        GridItem(.fixed(DropTile.side), spacing: 12),
        GridItem(.fixed(DropTile.side), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 12) {
            // Stands in for the hidden title bar; sits in the top strip that
            // stays draggable, so the window can still be moved by it.
            HStack(spacing: 6) {
                if let icon = Self.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: 14)
                }
                Text("Shrike")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach([preset1, preset2, preset3, preset4].indices, id: \.self) { index in
                    DropTile(
                        pixels: [preset1, preset2, preset3, preset4][index],
                        dimension: dimension,
                        makeCopy: makeCopy
                    )
                }
            }

            HStack(spacing: 12) {
                Picker("Dimension", selection: $dimension) {
                    Text("Width").tag(ResizeDimension.width)
                    Text("Height").tag(ResizeDimension.height)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                Toggle("Copy mode", isOn: $makeCopy)
                    .toggleStyle(.checkbox)
                    .help("Write the result to a new file (e.g. photo-800w.jpg) instead of overwriting the original.")

                Button {
                    showingPresetSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .help("Change the four preset sizes.")
                .popover(isPresented: $showingPresetSettings, arrowEdge: .bottom) {
                    PresetSettingsView(
                        preset1: $preset1, preset2: $preset2,
                        preset3: $preset3, preset4: $preset4,
                        darkMode: $darkMode
                    )
                }
            }
        }
        .padding([.horizontal, .bottom], 16)
        .padding(.top, 8)
        .fixedSize()
        .background(Theme.background(dark: darkMode).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

/// Popover for the preset sizes (clamped to ≥ 1; the core's shrink-only rule
/// handles everything else) and the dark-mode switch.
struct PresetSettingsView: View {
    @Binding var preset1: Int
    @Binding var preset2: Int
    @Binding var preset3: Int
    @Binding var preset4: Int
    @Binding var darkMode: Bool

    var body: some View {
        Form {
            Text("Preset sizes (px)")
                .font(.headline)
            presetField("Tile 1", $preset1)
            presetField("Tile 2", $preset2)
            presetField("Tile 3", $preset3)
            presetField("Tile 4", $preset4)
            Divider()
            Toggle("Dark mode", isOn: $darkMode)
        }
        .padding(16)
        .frame(width: 180)
    }

    private func presetField(_ label: String, _ value: Binding<Int>) -> some View {
        TextField(label, value: Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = max(1, $0) }
        ), format: .number)
        .textFieldStyle(.roundedBorder)
    }
}
