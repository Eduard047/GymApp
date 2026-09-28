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
            }
            .padding(16)
            .frame(minWidth: 220, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}
