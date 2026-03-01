import SwiftUI

/// Horizontal bar chart showing the sun/shade status at 15-minute resolution for a full day.
struct SunTimelineView: View {
    let timeline: SunTimeline

    private let hourRange = 6...23  // Display 6 AM to 11 PM

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            timelineBar
            hourLabels
        }
    }

    // MARK: - Timeline Bar

    private var timelineBar: some View {
        GeometryReader { proxy in
            let totalHours = Double(hourRange.upperBound - hourRange.lowerBound)
            let barWidth = proxy.size.width

            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.2))
                    .frame(height: 28)

                // Status segments
                ForEach(filteredEntries.indices, id: \.self) { index in
                    let entry = filteredEntries[index]
                    let x = xPosition(for: entry.date, totalHours: totalHours, width: barWidth)
                    let segmentWidth = segmentWidth(at: index, totalHours: totalHours, width: barWidth)

                    Rectangle()
                        .fill(entry.status.color.opacity(0.85))
                        .frame(width: max(segmentWidth, 1), height: 28)
                        .offset(x: x)
                }

                // Current time indicator
                currentTimeIndicator(totalHours: totalHours, width: barWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 28)
    }

    private func currentTimeIndicator(totalHours: Double, width: CGFloat) -> some View {
        let now = Date()
        let cal = Calendar.current
        let hour = Double(cal.component(.hour, from: now))
        let minute = Double(cal.component(.minute, from: now))
        let totalMinutes = hour * 60 + minute
        let startMinutes = Double(hourRange.lowerBound) * 60
        let rangeMinutes = totalHours * 60
        let fraction = (totalMinutes - startMinutes) / rangeMinutes
        guard fraction >= 0 && fraction <= 1 else { return AnyView(EmptyView()) }
        return AnyView(
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 36)
                .offset(x: fraction * width - 1)
        )
    }

    // MARK: - Hour Labels

    private var hourLabels: some View {
        HStack(spacing: 0) {
            ForEach(labelHours, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Helpers

    private var filteredEntries: [SunTimelineEntry] {
        timeline.entries.filter { entry in
            let hour = Calendar.current.component(.hour, from: entry.date)
            return hourRange.contains(hour)
        }
    }

    private var labelHours: [Int] {
        stride(from: hourRange.lowerBound, through: hourRange.upperBound, by: 3).map { $0 }
    }

    private func xPosition(for date: Date, totalHours: Double, width: CGFloat) -> CGFloat {
        let cal = Calendar.current
        let hour = Double(cal.component(.hour, from: date))
        let minute = Double(cal.component(.minute, from: date))
        let offset = hour + minute / 60.0 - Double(hourRange.lowerBound)
        return (offset / totalHours) * width
    }

    private func segmentWidth(at index: Int, totalHours: Double, width: CGFloat) -> CGFloat {
        // 15-minute segment width
        return (15.0 / (totalHours * 60.0)) * width
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
            ForEach([SunStatus.sunlit, .partialSun, .shaded, .cloudy, .belowHorizon], id: \.self) { status in
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
