import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        TabView {
            LaserSettingsTab()
                .environmentObject(settings)
                .tabItem {
                    Label("Laser", systemImage: "light.max")
                }

            ArrowSettingsTab()
                .environmentObject(settings)
                .tabItem {
                    Label("Arrow", systemImage: "arrow.right")
                }

            ShortcutsSettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            PermissionsSettingsTab()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
        }
        .frame(width: 460, height: 380)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Laser Settings Tab

struct LaserSettingsTab: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var selectedColor: Color = .red

    var body: some View {
        Form {
            Section("Laser Type") {
                Picker("Type", selection: $settings.laserType) {
                    ForEach(LaserType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Appearance") {
                HStack {
                    Text("Color")
                    Spacer()
                    ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: selectedColor) { _, newValue in
                            settings.laserColor = newValue
                        }
                }

                LabeledSlider(label: "Size", value: $settings.laserSize, range: 10...200, format: "%.0f pt")
                LabeledSlider(label: "Opacity", value: $settings.laserOpacity, range: 0.1...1.0, format: "%.0f%%", multiplier: 100)

                if settings.laserType == .ring {
                    LabeledSlider(label: "Border Width", value: $settings.laserBorderWidth, range: 1...20, format: "%.1f pt")
                }
            }

            Section("Animation") {
                Toggle("Enable pulse animation", isOn: $settings.laserAnimationEnabled)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectedColor = settings.laserColor
        }
    }
}

// MARK: - Arrow Settings Tab

struct ArrowSettingsTab: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var selectedColor: Color = .orange

    var body: some View {
        Form {
            Section("Arrow Appearance") {
                HStack {
                    Text("Color")
                    Spacer()
                    ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: selectedColor) { _, newValue in
                            settings.arrowColor = newValue
                        }
                }

                LabeledSlider(label: "Line Width", value: $settings.arrowLineWidth, range: 1...20, format: "%.1f pt")
                LabeledSlider(label: "Head Size", value: $settings.arrowHeadSize, range: 8...60, format: "%.0f pt")
            }

            Section("Usage") {
                Text("Hold the arrow shortcut while the laser is active to draw a temporary arrow from the starting mouse position to the current position.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectedColor = settings.arrowColor
        }
    }
}

// MARK: - Shortcuts Settings Tab

struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section("Global Shortcuts") {
                HStack {
                    Text("Toggle Laser")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .toggleLaser)
                }

                HStack {
                    Text("Draw Arrow (hold)")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .drawArrow)
                }
            }

            Section("Info") {
                Text("The \"Toggle Laser\" shortcut turns the laser overlay on/off.\n\nThe \"Draw Arrow\" shortcut draws a temporary arrow while held down. It only works when the laser is active.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions Settings Tab

struct PermissionsSettingsTab: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("Required Permissions") {
                HStack {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .red)
                    VStack(alignment: .leading) {
                        Text("Accessibility")
                            .fontWeight(.medium)
                        Text("Required for global keyboard shortcut monitoring.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !accessibilityGranted {
                        Button("Open Settings") {
                            openAccessibilitySettings()
                        }
                    }
                }

                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text("Input Monitoring")
                            .fontWeight(.medium)
                        Text("May be required on macOS 14+ for global key event listening.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        openInputMonitoringSettings()
                    }
                }
            }

            Section {
                Button("Refresh Permission Status") {
                    accessibilityGranted = AXIsProcessTrusted()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Reusable Slider

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.1f"
    var multiplier: Double = 1

    var body: some View {
        HStack {
            Text(label)
            Slider(value: $value, in: range)
            Text(String(format: format, value * multiplier))
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore.shared)
}
