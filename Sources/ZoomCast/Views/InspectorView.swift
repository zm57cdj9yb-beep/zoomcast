import SwiftUI
import ZoomCastCore

struct InspectorView: View {
    @Bindable var store: StudioStore

    private let swatchColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let project = store.project {
                    // 1. Studio Background Presets
                    sectionHeader("Background", icon: "paintpalette")
                    LazyVGrid(columns: swatchColumns, spacing: 8) {
                        ForEach(BackgroundPreset.allPresets) { preset in
                            let selected = project.style.backgroundID == preset.id
                            Button {
                                store.updateStyle { $0.backgroundID = preset.id }
                            } label: {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: preset.topLeading.r, green: preset.topLeading.g, blue: preset.topLeading.b),
                                                Color(red: preset.bottomTrailing.r, green: preset.bottomTrailing.g, blue: preset.bottomTrailing.b)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(height: 36)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .stroke(selected ? Color.white : Color.white.opacity(0.14), lineWidth: selected ? 2.2 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
                        }
                    }

                    Divider().opacity(0.25)

                    // 2. Canvas & Frame Controls
                    sectionHeader("Canvas & Frame", icon: "aspectratio")

                    HStack(spacing: 6) {
                        ForEach(AspectPreset.allCases) { preset in
                            let active = project.style.aspect == preset
                            Button {
                                store.updateStyle { $0.aspect = preset }
                            } label: {
                                Text(preset.shortLabel)
                                    .font(.caption.weight(.semibold))
                                    .fixedSize()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(active ? Color.indigo : Color.white.opacity(0.06))
                                    )
                                    .foregroundStyle(active ? .white : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    sliderRow(
                        title: "Padding",
                        valueText: "\(Int(project.style.padding)) px",
                        value: Binding(
                            get: { project.style.padding },
                            set: { v in store.updateStyle { $0.padding = v } }
                        ),
                        range: 0...140
                    )

                    sliderRow(
                        title: "Corner Radius",
                        valueText: "\(Int(project.style.cornerRadius)) px",
                        value: Binding(
                            get: { project.style.cornerRadius },
                            set: { v in store.updateStyle { $0.cornerRadius = v } }
                        ),
                        range: 0...36
                    )

                    sliderRow(
                        title: "Shadow",
                        valueText: "\(Int(project.style.shadowIntensity * 100))%",
                        value: Binding(
                            get: { project.style.shadowIntensity },
                            set: { v in store.updateStyle { $0.shadowIntensity = v } }
                        ),
                        range: 0...1
                    )

                    Divider().opacity(0.25)

                    // 3. Camera Motion & Selected Zoom
                    sectionHeader("Motion & Cursor", icon: "cursorarrow.motionlines")

                    Picker("Easing", selection: Binding(
                        get: { project.style.easing },
                        set: { v in store.updateStyle { $0.easing = v } }
                    )) {
                        ForEach(ZoomEasing.allCases) { e in
                            Text(e.rawValue).tag(e)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Cursor Highlight", isOn: Binding(
                        get: { project.style.showCursorHighlight },
                        set: { v in store.updateStyle { $0.showCursorHighlight = v } }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Toggle("Click Ripples", isOn: Binding(
                        get: { project.style.showClickRipples },
                        set: { v in store.updateStyle { $0.showClickRipples = v } }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if let seg = store.selectedZoom {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(seg.label, systemImage: "plus.magnifyingglass")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Button(role: .destructive) {
                                    store.deleteSelectedZoom()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .help("Delete selected zoom segment")
                            }

                            sliderRow(
                                title: "Zoom Scale",
                                valueText: String(format: "%.2f×", seg.scale),
                                value: Binding(
                                    get: { seg.scale },
                                    set: { v in store.updateSelectedZoom { $0.scale = v } }
                                ),
                                range: 1.2...3.0
                            )

                            sliderRow(
                                title: "Focus X",
                                valueText: "\(Int(seg.focus.x * 100))%",
                                value: Binding(
                                    get: { seg.focus.x },
                                    set: { v in store.updateSelectedZoom { $0.focus = NormalizedPoint(x: v, y: $0.focus.y) } }
                                ),
                                range: 0.05...0.95
                            )

                            sliderRow(
                                title: "Focus Y",
                                valueText: "\(Int(seg.focus.y * 100))%",
                                value: Binding(
                                    get: { seg.focus.y },
                                    set: { v in store.updateSelectedZoom { $0.focus = NormalizedPoint(x: $0.focus.x, y: v) } }
                                ),
                                range: 0.05...0.95
                            )
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.indigo.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.indigo.opacity(0.35), lineWidth: 1)
                                )
                        )
                    }

                    Divider().opacity(0.25)

                    // 4. Quick Export
                    sectionHeader("Export", icon: "square.and.arrow.up")
                    HStack(spacing: 8) {
                        Button {
                            store.export(format: .mp4H264)
                        } label: {
                            Label("MP4", systemImage: "film")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .disabled(store.isExporting)

                        Button {
                            store.export(format: .gif)
                        } label: {
                            Label("GIF", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isExporting)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 296)
        .background(
            Color(nsColor: NSColor(calibratedRed: 0.085, green: 0.09, blue: 0.115, alpha: 1.0))
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.primary)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
                .tint(.indigo)
        }
    }
}
