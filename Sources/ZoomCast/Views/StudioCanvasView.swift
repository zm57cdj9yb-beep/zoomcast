import SwiftUI
import ZoomCastCore

struct StudioCanvasView: View {
    @Bindable var store: StudioStore

    var body: some View {
        VStack(spacing: 14) {
            // Stage Canvas
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: NSColor(calibratedRed: 0.06, green: 0.065, blue: 0.085, alpha: 1.0)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                if let image = store.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(16)
                        .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)
                        Text(store.isLoadingDemo ? "Generating 1080p Studio Demo..." : "No Video Loaded")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Floating top-right HUD pills
                if let project = store.project {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 8) {
                                if store.activeCameraScale > 1.02 {
                                    Label(String(format: "%.2f× Zoom", store.activeCameraScale), systemImage: "plus.magnifyingglass")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .overlay(Capsule().stroke(Color.indigo.opacity(0.75), lineWidth: 1))
                                        .foregroundStyle(.white)
                                }

                                Text("\(String(Int(project.style.aspect.pixelSize.width)))×\(String(Int(project.style.aspect.pixelSize.height))) · \(project.style.aspect.shortLabel)")
                                    .font(.caption.monospacedDigit().weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .foregroundStyle(.white.opacity(0.88))
                            }
                        }
                        Spacer()
                    }
                    .padding(18)
                }

                // Export progress overlay
                if store.isExporting {
                    VStack(spacing: 12) {
                        ProgressView(value: store.exportProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 240)
                            .tint(.indigo)
                        Text("Rendering Studio Frames… \(Int(store.exportProgress * 100))%")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Playback Transport Bar
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Button {
                        store.seek(to: max(0, store.currentTime - 0.5))
                    } label: {
                        Image(systemName: "gobackward.5")
                            .frame(width: 28, height: 26)
                    }
                    .buttonStyle(.bordered)
                    .help("Step back 0.5s")

                    Button {
                        store.togglePlayback()
                    } label: {
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 34, height: 26)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .keyboardShortcut(.space, modifiers: [])

                    Button {
                        if let proj = store.project {
                            store.seek(to: min(proj.duration, store.currentTime + 0.5))
                        }
                    } label: {
                        Image(systemName: "goforward.5")
                            .frame(width: 28, height: 26)
                    }
                    .buttonStyle(.bordered)
                    .help("Step forward 0.5s")
                }

                if let project = store.project {
                    Text("\(store.formatTime(store.currentTime)) / \(store.formatTime(project.duration))")
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }

                Spacer()

                if let msg = store.statusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if store.lastExportURL != nil {
                    Button("Reveal Export") {
                        store.revealLastExport()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
