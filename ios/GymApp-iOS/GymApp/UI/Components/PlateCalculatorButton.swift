import SwiftUI

/// Compact "Блины" capsule in the current set's header that shows the plates
/// to load on each side of the bar for the current weight.
struct PlateCalculatorButton: View {
    let weight: Double
    @State private var showsPlates = false

    var body: some View {
        Button {
            showsPlates = true
        } label: {
            Text(gymText("Plates", "Диски", "Блины", languageCode: gymCurrentLanguageCode()))
                .font(.caption.weight(.semibold))
                .foregroundStyle(GymTheme.primary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(GymTheme.primary.opacity(0.12)))
                .fixedSize()
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
#if DEBUG
        .onAppear {
            // `-uiAuditRoute plate-calculator`: the first visible button opens its popover once.
            guard UIAuditRouter.shared.consume(.plateCalculator) else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                showsPlates = true
            }
        }
#endif
        .accessibilityLabel(
            gymText("Plates per side", "Диски на сторону", "Блины на сторону", languageCode: gymCurrentLanguageCode())
        )
        .popover(isPresented: $showsPlates) {
            let languageCode = gymCurrentLanguageCode()
            VStack(alignment: .leading, spacing: 6) {
                Text(gymWeightText(weight, languageCode: languageCode))
                    .font(.headline.monospacedDigit())
                ForEach(
                    PlateCalculator.summaryLines(
                        for: PlateCalculator.load(total: weight),
                        languageCode: languageCode
                    ),
                    id: \.self
                ) { line in
                    Text(line)
                        .font(.subheadline.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                }
                warmupSection(languageCode: languageCode)
            }
            .padding(16)
            .frame(minWidth: 220, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }

    /// Read-only "Warm-up" list: weight x reps and the plates per side for each step.
    @ViewBuilder
    private func warmupSection(languageCode: String) -> some View {
        let steps = PlateCalculator.warmup(workingWeight: weight)
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(gymText("Warm-up", "Розминка", "Разминка", languageCode: languageCode))
                    .font(.headline)
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(gymWeightText(step.weight, languageCode: languageCode)) × \(step.reps)")
                            .font(.subheadline.monospacedDigit())
                        // The bar step reads "Bar only (20 kg)"; loaded steps read "Per side: 25 + 5".
                        ForEach(
                            PlateCalculator.summaryLines(
                                for: step.load.platesPerSide.isEmpty
                                    ? PlateCalculator.load(total: step.weight)
                                    : step.load,
                                languageCode: languageCode
                            ),
                            id: \.self
                        ) { line in
                            Text(line)
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(GymTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}
