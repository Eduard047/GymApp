import SwiftUI

/// The single editor for every `TrainingProfile` field: goal, calorie mode,
/// split, and workouts per week. Every screen that used to let people change
/// one of these fields inline now shows a read-only one-line summary
/// (`TrainingSettingsSummaryRow`) with an "edit" link that opens this view.
///
/// Callers own how the change reaches storage: `profile` is a live binding
/// (edits apply immediately), and `onChange` is called with the updated
/// profile on every edit so a caller can persist it via `TrainingProfileStore`
/// (or rely on its own `onChange(of:)` if `profile` is already the state that
/// autosaves, as in `AddWorkoutView`).
struct TrainingSettingsView: View {
    @Binding var profile: TrainingProfile
    var presentedAsSheet: Bool = false
    var onChange: (TrainingProfile) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue

    private static let workoutsPerWeekOptions = Array(2 ... 6)

    var body: some View {
        GymBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: GymTheme.contentSpacing) {
                    optionSection(
                        gymText("Goal", "Ціль", "Цель", languageCode: languageCode)
                    ) {
                        ForEach(Array(TrainingGoal.allCases.enumerated()), id: \.element) { index, goal in
                            if index > 0 { sectionDivider }
                            optionRow(goal.gymDisplayName, isSelected: profile.goal == goal) {
                                profile.goal = goal
                            }
                        }
                    }
                    optionSection(
                        gymText("Calories", "Калорії", "Калории", languageCode: languageCode)
                    ) {
                        ForEach(Array(CalorieMode.allCases.enumerated()), id: \.element) { index, mode in
                            if index > 0 { sectionDivider }
                            optionRow(mode.gymDisplayName, isSelected: profile.calorieMode == mode) {
                                profile.calorieMode = mode
                            }
                        }
                    }
                    optionSection(
                        gymText("Split", "Спліт", "Сплит", languageCode: languageCode)
                    ) {
                        ForEach(Array(TrainingSplit.allCases.enumerated()), id: \.element) { index, split in
                            if index > 0 { sectionDivider }
                            optionRow(split.gymDisplayName, isSelected: profile.split == split) {
                                profile.split = split
                            }
                        }
                    }
                    optionSection(
                        gymText(
                            "Workouts per week", "Тренувань на тиждень", "Тренировок в неделю",
                            languageCode: languageCode
                        )
                    ) {
                        HStack(spacing: 8) {
                            ForEach(Self.workoutsPerWeekOptions, id: \.self) { option in
                                let isSelected = profile.workoutsPerWeek == option
                                Button {
                                    profile.workoutsPerWeek = option
                                } label: {
                                    Text(option.formatted(.number.locale(gymAppLocale())))
                                        .font(.headline.weight(isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? Color.white : GymTheme.textPrimary)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(
                                            Capsule().fill(isSelected ? GymTheme.brandFill : GymTheme.surfaceVariant)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(gymText(
                            "Workouts per week", "Тренувань на тиждень", "Тренировок в неделю",
                            languageCode: languageCode
                        ))
                    }
                }
                .padding(.horizontal, GymTheme.screenHorizontalInset)
                .padding(.top, GymTheme.screenVerticalInset)
                .padding(.bottom, GymTheme.screenBottomInset)
            }
        }
        .navigationTitle(gymText(
            "Training settings", "Налаштування тренувань", "Настройки тренировок",
            languageCode: languageCode
        ))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button(gymText("Done", "Готово", "Готово", languageCode: languageCode)) {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: profile) { _, newValue in
            onChange(newValue)
        }
    }

    @ViewBuilder
    private func optionSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GymTheme.textSecondary)
                .padding(.horizontal, 4)
            GymPanel(contentPadding: EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16)) {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
    }

    private var sectionDivider: some View {
        Divider().overlay(GymTheme.outlineSoft)
    }

    private func optionRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(GymTheme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(GymTheme.primary)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A sheet wrapper around `TrainingSettingsView` for callers that present it
/// modally (rather than pushing it in an existing `NavigationStack`).
struct TrainingSettingsSheet: View {
    @Binding var profile: TrainingProfile
    var onChange: (TrainingProfile) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            TrainingSettingsView(profile: $profile, presentedAsSheet: true, onChange: onChange)
        }
        .presentationDetents([.large])
    }
}

/// Read-only "Goal · Calories · N a week · edit" line shown wherever a
/// training-profile field used to be an inline editor.
struct TrainingSettingsSummaryRow: View {
    let profile: TrainingProfile
    let languageCode: String
    var textColor: Color = GymTheme.textSecondary
    var linkColor: Color = GymTheme.brandFill
    let action: () -> Void

    private var summaryText: String {
        [
            profile.goal.gymDisplayName,
            profile.calorieMode.gymDisplayName,
            gymCount(
                profile.workoutsPerWeek,
                englishOne: "workout",
                englishMany: "workouts",
                ukrainianOne: "тренування",
                ukrainianFew: "тренування",
                ukrainianMany: "тренувань",
                languageCode: languageCode
            ) + " " + gymText("a week", "на тиждень", "в неделю", languageCode: languageCode)
        ].joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(summaryText)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button(action: action) {
                Text(gymText("edit", "змінити", "изменить", languageCode: languageCode))
                    .foregroundStyle(linkColor)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .font(.subheadline)
    }
}
