import SwiftUI

/// Heart rate row: heart in the zone colour, white bpm, black digit badge; elapsed on the right.
struct HeartRateRow: View {
    @EnvironmentObject private var model: WatchAppModel
    @ObservedObject var health: WorkoutSessionManager
    let elapsed: String

    var body: some View {
        HStack(spacing: 4) {
            heart
            Spacer(minLength: 4)
            Text(elapsed)
                .monospacedDigit()
        }
        .font(.body.weight(.medium))
    }

    @ViewBuilder private var heart: some View {
        if model.workout?.heartRateEnabled != true {
            HStack(spacing: 4) {
                Image(systemName: "heart.slash")
                Text(verbatim: "—")
            }
            .foregroundStyle(WatchTheme.textSecondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.text(.a11yHeartRateOff))
        } else if let bpm = health.heartRate.map({ Int($0.rounded()) }), bpm > 0,
                  let zone = WatchHeartRateZone.zone(bpm: bpm) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(WatchTheme.zoneColor(zone))
                Text(String(bpm))
                    .monospacedDigit()
                    .foregroundStyle(WatchTheme.text)
                Text(String(zone))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 20, height: 20)
                    .background(WatchTheme.zoneColor(zone), in: RoundedRectangle(cornerRadius: 6))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.format(.a11yHeartRate, bpm, zone))
        } else {
            HStack(spacing: 4) {
                Image(systemName: "heart")
                Text(verbatim: "--")
            }
            .foregroundStyle(WatchTheme.textSecondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.text(.a11yHeartRateWaiting))
        }
    }
}
