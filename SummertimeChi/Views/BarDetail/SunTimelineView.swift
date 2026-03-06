import SwiftUI

/// Horizontal bar chart showing the sun/shade status at 15-minute resolution for a full day.
/// Displays 6 AM to 6 AM (24 hours). Optionally overlays open/close hour markers.
struct SunTimelineView: View {
    let timeline: SunTimeline
    var openHour: Int?
    var closeHour: Int?

    private let totalMinutes: Double = 24 * 60  // 6am to 6am = 1440 minutes

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            timelineBar
            hourLabels
        }
    }

    // MARK: - Timeline Bar

    private var timelineBar: some View {
        GeometryReader { proxy in
            let barWidth = proxy.size.width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.2))
                    .frame(height: 28)

                // Dim regions outside operating hours
                if let open = openHour {
                    let openFrac = fractionFrom6am(hour: open, minute: 0)
                    if openFrac > 0 {
                        Rectangle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: openFrac * barWidth, height: 28)
                    }
                }
                if let close = closeHour, close > 0 {
                    let closeFrac = fractionFrom6am(hour: close, minute: 0)
                    if closeFrac < 1 {
                        Rectangle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: (1 - closeFrac) * barWidth, height: 28)
                            .offset(x: closeFrac * barWidth)
                    }
                }

                // Status segments (ordered 6am → 6am)
                ForEach(Array(orderedEntries.enumerated()), id: \.offset) { index, entry in
                    let x = CGFloat(index) / 96.0 * barWidth
                    let w = barWidth / 96.0

                    Rectangle()
                        .fill(entry.status.color.opacity(0.85))
                        .frame(width: max(w, 1), height: 28)
                        .offset(x: x)
                }

                // Open marker
                if let open = openHour {
                    hourMarker(hour: open, minute: 0, color: .green, width: barWidth)
                }

                // Close marker (including overnight closes at 1am, 2am, etc.)
                if let close = closeHour, close > 0 {
                    hourMarker(hour: close, minute: 0, color: .red, width: barWidth)
                }

                // Current time indicator (drawn on top)
                currentTimeIndicator(width: barWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private func hourMarker(hour: Int, minute: Int, color: Color, width: CGFloat) -> some View {
        let frac = fractionFrom6am(hour: hour, minute: minute)
        if frac >= 0 && frac <= 1 {
            Rectangle()
                .fill(color)
                .frame(width: 2, height: 28)
                .offset(x: frac * width - 1)
        }
    }

    @ViewBuilder
    private func currentTimeIndicator(width: CGFloat) -> some View {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let fraction = fractionFrom6am(hour: hour, minute: minute)
        if fraction >= 0 && fraction <= 1 {
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 36)
                .offset(x: fraction * width - 1)
        }
    }

    // MARK: - Hour Labels

    private var hourLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(labelHours.enumerated()), id: \.offset) { index, hour in
                Text(hourLabel(hour))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: index == labelHours.count - 1 ? .trailing : .leading)
            }
        }
    }

    // MARK: - Helpers (6am–6am coordinate system)

    /// Fraction 0...1 for position in the 6am→6am day. Hour 6=0, hour 12=0.25, midnight=0.75, 6am next day=1.
    private func fractionFrom6am(hour: Int, minute: Int) -> CGFloat {
        let minutesFrom6am: Double
        if hour >= 6 {
            minutesFrom6am = Double((hour - 6) * 60 + minute)
        } else {
            minutesFrom6am = Double((18 + hour) * 60 + minute)  // midnight = 18 hours from 6am
        }
        return CGFloat(minutesFrom6am / totalMinutes)
    }

    /// Entries reordered so 6am is first, then 7am...11pm, then midnight...5:45am
    private var orderedEntries: [SunTimelineEntry] {
        let entries = timeline.entries  // 96 entries: index 0=midnight, 24=6am, 95=11:45pm
        return Array(entries[24..<96]) + Array(entries[0..<24])
    }

    private var labelHours: [Int] {
        [6, 9, 12, 15, 18, 21, 0, 3, 6]  // Every 3 hours from 6am, ending at 6a
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0  { return "12a" }
        if hour == 12 { return "12p" }
        return hour < 12 ? "\(hour)a" : "\(hour - 12)p"
    }
}

// MARK: - Legend

struct SunTimelineLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach([SunStatus.sunlit, .shaded, .cloudy, .belowHorizon], id: \.self) { status in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(status.color)
                        .frame(width: 12, height: 12)
                    Text(status.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Sun Timeline Preview")
            .font(.headline)
        SunTimelineLegend()
    }
    .padding()
}
