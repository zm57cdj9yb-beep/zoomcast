import AppKit
import SwiftUI
import ZoomCastCore

struct MainStudioView: View {
    @Bindable var store: StudioStore

    var body: some View {
        HStack(spacing: 0) {
            // Left + Center: Stage & Timeline
            VStack(spacing: 14) {
                StudioCanvasView(store: store)
                TimelineView(store: store)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.078, alpha: 1.0)))

            // Right Studio Inspector
            InspectorView(store: store)
        }
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    store.toggleRecording()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(store.isRecording ? Color.red : Color.red.opacity(0.9))
                            .frame(width: 8, height: 8)
                        Text(store.isRecording ? "Stop (\(store.formatTime(store.recordingElapsed)))" : "Record Screen")
                            .font(.callout.weight(.semibold))
                            .fixedSize()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(store.isRecording ? .red : Color(red: 0.86, green: 0.22, blue: 0.24))

                Button {
                    store.importVideo()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

                Button {
                    store.loadDemoProject()
                } label: {
                    Label("Demo", systemImage: "sparkles")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.export(format: .gif)
                } label: {
                    Label("Export GIF", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(store.project == nil || store.isExporting)

                Button {
                    store.export(format: .mp4H264)
                } label: {
                    Label("Export MP4", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(store.project == nil || store.isExporting)
            }
        }
        .onAppear {
            store.bootstrapOnLaunch()
        }
    }
}

@main
struct ZoomCastApp: App {
    @State private var store = StudioStore()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("ZoomCast Studio") {
            MainStudioView(store: store)
                .frame(minWidth: 1120, minHeight: 740)
        }
        .defaultSize(width: 1360, height: 840)
        .windowToolbarStyle(.unified(showsTitle: true))
    }
}
