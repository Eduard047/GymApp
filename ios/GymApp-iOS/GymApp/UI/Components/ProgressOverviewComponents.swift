import SwiftUI

// Building blocks of the Progress overview (Package E): inset-grouped rows like the
// Profile root and the workout summary, the three-number weekly hero, the strength
// progress rows and the small ⓘ explanation button.

/// One inset-grouped block: an optional quiet title over a rounded neutral surface.
struct ProgressGroup<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(GymTheme.textSecondary)
                    .padding(.leading, 16)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GymTheme.surface,
                in: RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius, style: .continuous)
            )
        }
    }
}

/// Hairline between two rows of a `ProgressGroup`.
struct ProgressRowDivider: View {
    var body: some View {
        Divider().overlay(GymTheme.outline.opacity(0.4))
    }
}

/// A group row: 17pt title, optional one-line subtitle, optional value on the right,
/// optional chevron.
struct ProgressRowLabel: View {
    let title: String
    var subtitle: String?
    var value: String?
    var valueColor: Color = GymTheme.textSecondary
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(GymTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if let value {
                Text(value)
                    .font(.body)
                    .foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GymTheme.textSecondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

/// Big tabular numeral with a small unit beside it, the label under it. Numbers on
/// the Progress overview always carry their unit.
struct ProgressHeroStat: View {
    let value: String
    var unit: String?
    let label: String

    var body: some View {
        let numeral = Text(value)
            .gymScaledFont(size: 30, weight: .semibold, design: .rounded, relativeTo: .largeTitle, monospacedDigit: true, maxScale: 1.6)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                numeral
                    .foregroundStyle(GymTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GymTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Text(label)
                .font(.footnote)
                .foregroundStyle(GymTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, value, unit].compactMap { $0 }.joined(separator: " "))
    }
}

/// The ⓘ button: a short explanation in a popover instead of always-visible text.
struct ProgressInfoButton: View {
    let accessibilityLabel: String
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(GymTheme.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $isPresented) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(GymTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .padding(16)
                .frame(width: 290, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Strength progress

struct ProgressStrengthRow: Identifiable, Equatable {
    let exerciseID: UUID
    let name: String
    let catalogKey: String?
    /// Heaviest set of the last 30 days.
    let bestWeight: Double
    let bestReps: Int
    /// Heaviest set of the last 30 days minus that of the 30 days before; nil without a baseline.
    let monthDelta: Double?

    var id: UUID { exerciseID }
}

enum ProgressStrengthTrend {
    /// The most-trained exercises of the last 30 days with their heaviest set and how it
    /// moved against the 30 days before. Empty until something was logged in the last month.
    static func rows(
        history: [ExerciseHistoryEntry],
        now: Date,
        calendar: Calendar,
        limit: Int = 3
    ) -> [ProgressStrengthRow] {
        guard let monthStart = calendar.date(byAdding: .day, value: -30, to: now),
              let previousStart = calendar.date(byAdding: .day, value: -60, to: now) else { return [] }
        struct Current {
            var best: ExerciseHistoryEntry
            var sets = 0
            var latest: ExerciseHistoryEntry
        }
        var current: [UUID: Current] = [:]
        var previousBest: [UUID: Double] = [:]
        for entry in history {
            guard entry.sessionDate <= now, entry.sessionDate > previousStart,
                  entry.weight.isFinite, entry.weight > 0, entry.weight <= 1_000_000,
                  (1 ... 10_000).contains(entry.reps) else { continue }
            if entry.sessionDate > monthStart {
                if var existing = current[entry.exerciseID] {
                    existing.sets += 1
                    if entry.weight > existing.best.weight
                        || (entry.weight == existing.best.weight && entry.reps > existing.best.reps) {
                        existing.best = entry
                    }
                    if entry.sessionDate > existing.latest.sessionDate { existing.latest = entry }
                    current[entry.exerciseID] = existing
                } else {
                    current[entry.exerciseID] = Current(best: entry, sets: 1, latest: entry)
                }
            } else {
                previousBest[entry.exerciseID] = max(previousBest[entry.exerciseID] ?? 0, entry.weight)
            }
        }
        let ranked = current.values.sorted { lhs, rhs in
            if lhs.sets != rhs.sets { return lhs.sets > rhs.sets }
            if lhs.best.weight != rhs.best.weight { return lhs.best.weight > rhs.best.weight }
            return lhs.best.exerciseID.uuidString < rhs.best.exerciseID.uuidString
        }
        return ranked.prefix(limit).map { item in
            ProgressStrengthRow(
                exerciseID: item.best.exerciseID,
                name: item.latest.exerciseName,
                catalogKey: item.latest.exerciseCatalogKey,
                bestWeight: item.best.weight,
                bestReps: item.best.reps,
                monthDelta: previousBest[item.best.exerciseID].map { item.best.weight - $0 }
            )
        }
    }
}

struct ProgressStrengthSection: View {
    let rows: [ProgressStrengthRow]
    let onOpenExercise: (UUID) -> Void

    private var languageCode: String { gymCurrentLanguageCode() }

    var body: some View {
        if !rows.isEmpty {
            ProgressGroup(title: gymText(
                "Strength progress", "Силовий прогрес", "Силовой прогресс", languageCode: languageCode
            )) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { ProgressRowDivider() }
                    Button { onOpenExercise(row.exerciseID) } label: {
                        ProgressRowLabel(
                            title: gymExerciseName(row.name, catalogKey: row.catalogKey, languageCode: languageCode),
                            subtitle: bestSetText(row),
                            value: trendText(row.monthDelta),
                            valueColor: trendColor(row.monthDelta)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.locale(gymAppLocale()).precision(.fractionLength(0 ... 1)))
    }

    private func bestSetText(_ row: ProgressStrengthRow) -> String {
        let kg = gymLocalized("kg", languageCode: languageCode)
        let set = "\(number(row.bestWeight))\u{00A0}\(kg) × \(row.bestReps)"
        return gymText("Best: \(set)", "Найкращий: \(set)", "Лучший: \(set)", languageCode: languageCode)
    }

    private func trendText(_ delta: Double?) -> String? {
        guard let delta else { return nil }
        let kg = gymLocalized("kg", languageCode: languageCode)
        let rounded = (delta * 10).rounded() / 10
        if rounded == 0 {
            return gymText("no change in a month", "без змін за місяць", "без изменений за месяц", languageCode: languageCode)
        }
        let signed = (rounded > 0 ? "+" : "−") + number(abs(rounded)) + "\u{00A0}" + kg
        return signed + " " + gymText("in a month", "за місяць", "за месяц", languageCode: languageCode)
    }

    private func trendColor(_ delta: Double?) -> Color {
        guard let delta, (delta * 10).rounded() > 0 else { return GymTheme.textSecondary }
        // Same rule as the workout summary: green for an improvement, grey otherwise.
        return GymTheme.secondary
    }
}
