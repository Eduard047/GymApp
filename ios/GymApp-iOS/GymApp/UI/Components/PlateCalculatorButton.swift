import SwiftUI

/// Small button next to a barbell weight field that shows the plates to load
/// on each side of the bar for the current weight.
struct PlateCalculatorButton: View {
    let weight: Double
    @State private var showsPlates = false

    var body: some View {
        Button {
            showsPlates = true
        } label: {
            Image(systemName: "circle.grid.cross")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GymTheme.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
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
