import SwiftUI

/// Saved-workout panel comparing sets, reps and volume with the previous workout that
/// trained the same exercises. Hidden by the caller when there is no such workout.
struct WorkoutComparisonCard: View {
    let comparison: WorkoutComparison

    private struct Tile: Identifiable {
        let id: String
        let label: String
        let value: String
        let previous: String
        let delta: String
        let isIncrease: Bool
        let accessibility: String
    }

    var body: some View {
        let languageCode = gymCurrentLanguageCode()
        let tiles = makeTiles(languageCode: languageCode)
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: gymText(
                        "Workout comparison",
                        "Порівняння тренувань",
                        "Сравнение тренировок",
                        languageCode: languageCode
                    ),
                    supporting: supportingText(languageCode: languageCode)
                )
                VStack(spacing: 8) {
                    ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { start in
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(tiles[start ..< min(start + 2, tiles.count)]) { tile in
                                tileView(tile, languageCode: languageCode)
                            }
                            if start + 1 >= tiles.count {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func tileView(_ tile: Tile, languageCode: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tile.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(GymTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(tile.value)
                .font(GymTheme.TypeScale.metric.monospacedDigit())
                .foregroundStyle(GymTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(gymText("Previous", "Раніше", "Раньше", languageCode: languageCode) + " " + tile.previous)
                .font(.caption.monospacedDigit())
                .foregroundStyle(GymTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(tile.delta)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(tile.isIncrease ? GymTheme.secondary : GymTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(GymTheme.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 74, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                .fill(GymTheme.surfaceVariant.opacity(0.58))
        )
        .overlay {
            RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius, style: .continuous)
                .strokeBorder(GymTheme.outlineSoft.opacity(0.62), lineWidth: GymTheme.hairlineWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibility)
    }

    private func supportingText(languageCode: String) -> String {
        let count = comparison.matchedExerciseCount
        let noun = gymPlural(
            count,
            en: (one: "matching exercise", many: "matching exercises"),
            uk: (one: "спільна вправа", few: "спільні вправи", many: "спільних вправ"),
            ru: (one: "совпадающее упражнение", few: "совпадающих упражнения", many: "совпадающих упражнений"),
            languageCode: languageCode
        )
        return "\(count) \(noun) · \(gymShortDate(comparison.previousDate, languageCode: languageCode))"
    }

    private func makeTiles(languageCode: String) -> [Tile] {
        let locale = gymAppLocale(languageCode: languageCode)
        let whole: (Double) -> String = { value in
            Int(value.rounded()).formatted(.number.locale(locale))
        }
        let volume: (Double) -> String = { gymVolumeText($0, languageCode: languageCode) }
        return [
            makeTile(
                id: "sets",
                label: gymText("Sets", "Підходи", "Подходы", languageCode: languageCode),
                metric: comparison.sets,
                format: whole,
                languageCode: languageCode
            ),
            makeTile(
                id: "reps",
                label: gymText("Reps", "Повторення", "Повторы", languageCode: languageCode),
                metric: comparison.reps,
                format: whole,
                languageCode: languageCode
            ),
            makeTile(
                id: "volume",
                label: gymText("Volume", "Обсяг", "Объём", languageCode: languageCode),
                metric: comparison.volume,
                format: volume,
                languageCode: languageCode
            )
        ]
    }

    private func makeTile(
        id: String,
        label: String,
        metric: WorkoutComparisonMetric,
        format: (Double) -> String,
        languageCode: String
    ) -> Tile {
        let value = format(metric.current)
        let previous = format(metric.previous)
        let magnitude = format(abs(metric.delta))
        let delta: String
        let spoken: String
        if metric.isUnchanged {
            delta = gymText("no change", "без змін", "без изменений", languageCode: languageCode)
            spoken = delta
        } else if metric.delta > 0 {
            delta = "+\(magnitude)"
            spoken = gymText("plus", "плюс", "плюс", languageCode: languageCode) + " " + magnitude
        } else {
            delta = "\u{2212}\(magnitude)"
            spoken = gymText("minus", "мінус", "минус", languageCode: languageCode) + " " + magnitude
        }
        let reference = gymText(
            "compared with previous",
            "порівняно з попереднім",
            "по сравнению с предыдущим",
            languageCode: languageCode
        )
        return Tile(
            id: id,
            label: label,
            value: value,
            previous: previous,
            delta: delta,
            isIncrease: !metric.isUnchanged && metric.delta > 0,
            accessibility: "\(label) \(value), \(spoken) \(reference) \(previous)"
        )
    }
}
