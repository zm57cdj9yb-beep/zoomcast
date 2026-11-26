import SwiftUI
import ZoomCastCore

struct TimelineView: View {
    @Bindable var store: StudioStore

    var body: some View {
        VStack(spacing: 10) {
            // Timeline header
            HStack {
                Label("Timeline", systemImage: "timeline.selection")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let project = store.project {
                    Text("\(project.zoomSegments.count) zooms · \(project.clickEvents.count) clicks")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    store.addZoomAtPlayhead()
                } label: {
                    Label("Add Zoom", systemImage: "plus.magnifyingglass")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    store.autoGenerateZooms()
                } label: {
                    Label("Auto-Zoom", systemImage: "wand.and.stars")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let project = store.project {
                GeometryReader { geo in
                    let trackWidth = max(120, geo.size.width - 78)
                    let duration = max(0.1, project.duration)
                    let playheadX = CGFloat(store.currentTime / duration) * trackWidth

                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 8) {
                            // 1. Time ruler
                            HStack(spacing: 10) {
                                Text("Time")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 68, alignment: .trailing)

                                ZStack(alignment: .leading) {
                                    let tickCount = max(2, Int(ceil(duration)))
                                    ForEach(0...tickCount, id: \.self) { sec in
                                        let frac = min(1.0, Double(sec) / duration)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(sec)s")
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                            Rectangle()
                                                .fill(Color.white.opacity(0.15))
                                                .frame(width: 1, height: 6)
                                        }
                                        .offset(x: CGFloat(frac) * max(1, trackWidth - 18))
                                    }
                                }
                                .frame(width: trackWidth, height: 22, alignment: .leading)
                            }

                            // 2. Video Clip Track
                            HStack(spacing: 10) {
                                Text("Screen")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 68, alignment: .trailing)

                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.16, green: 0.21, blue: 0.32), Color(red: 0.12, green: 0.15, blue: 0.24)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                                    )
                                    .overlay(alignment: .leading) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "film")
                                                .font(.caption)
                                                .foregroundStyle(.blue)
                                            Text(project.title)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.white.opacity(0.92))
                                                .lineLimit(1)
                                            Spacer()
                                            Text("\(String(project.sourceWidth))×\(String(project.sourceHeight)) · \(Int(project.fps))fps")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.white.opacity(0.60))
                                        }
                                        .padding(.horizontal, 10)
                                    }
                                    .frame(width: trackWidth, height: 34)
                            }

                            // 3. Zoom Segments Track
                            HStack(spacing: 10) {
                                Text("Zoom")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 68, alignment: .trailing)

                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.035))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                        )

                                    ForEach(project.zoomSegments) { seg in
                                        let segX = CGFloat(seg.startTime / duration) * trackWidth
                                        let segW = max(54, CGFloat(seg.duration / duration) * trackWidth)
                                        let isSelected = store.selectedZoomID == seg.id

                                        Button {
                                            store.selectedZoomID = seg.id
                                            store.seek(to: seg.startTime + seg.duration * 0.45)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "magnifyingglass")
                                                    .font(.system(size: 10, weight: .bold))
                                                Text(String(format: "%.1f×", seg.scale))
                                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                    .fixedSize()
                                            }
                                            .foregroundStyle(.white)
                                            .frame(width: segW, height: 28)
                                            .background(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .fill(
                                                        LinearGradient(
                                                            colors: isSelected
                                                                ? [Color.indigo, Color.purple]
                                                                : [Color.indigo.opacity(0.70), Color.indigo.opacity(0.48)],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.22), lineWidth: isSelected ? 1.5 : 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .offset(x: min(segX, max(0, trackWidth - segW)))
                                    }
                                }
                                .frame(width: trackWidth, height: 34)
                            }

                            // 4. Click Markers Track
                            HStack(spacing: 10) {
                                Text("Clicks")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 68, alignment: .trailing)

                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.white.opacity(0.025))

                                    ForEach(Array(project.clickEvents.enumerated()), id: \.offset) { _, click in
                                        let cx = CGFloat(click.time / duration) * trackWidth
                                        Button {
                                            store.seek(to: click.time)
                                        } label: {
                                            Image(systemName: "diamond.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.orange)
                                        }
                                        .buttonStyle(.plain)
                                        .help(String(format: "Click at %.2fs", click.time))
                                        .offset(x: max(2, min(cx - 5, trackWidth - 12)))
                                    }
                                }
                                .frame(width: trackWidth, height: 20)
                            }
                        }

                        // Interactive Scrubbing Layer + Red Playhead
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: trackWidth, height: 26)
                            .offset(x: 78, y: 0)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let ratio = min(max(value.location.x / max(1, trackWidth), 0.0), 1.0)
                                        store.seek(to: ratio * duration)
                                    }
                            )

                        // Playhead needle
                        VStack(spacing: 0) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 2, height: 120)
                        }
                        .offset(x: 78 + playheadX - 5, y: 12)
                        .allowsHitTesting(false)
                    }
                }
                .frame(height: 138)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedRed: 0.085, green: 0.09, blue: 0.115, alpha: 1.0)))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
