import SwiftUI

// Stateless exercise-card building blocks shared by the active workout screen
// and the saved-workout detail screen. Everything here takes plain values and
// closures, never a draft or a store, so both screens render the same design.

// MARK: - Copy and pure helpers

/// "82,5 kg × 8" — a set's weight and repetitions in the app language, shown
/// on every compact set row.
func gymSetWeightRepsSummary(weight: Double, reps: Int) -> String {
    "\(weight.formatted(.number.locale(gymAppLocale()))) \(gymLocalized("kg")) × \(reps)"
}

/// "Delete set" row action title (long-press menu and VoiceOver action).
func gymDeleteSetActionTitle(languageCode: String = gymCurrentLanguageCode()) -> String {
    gymText("Delete set", "Видалити підхід", "Удалить подход", languageCode: languageCode)
}

/// "Remove exercise" menu item title.
func gymRemoveExerciseActionTitle(languageCode: String = gymCurrentLanguageCode()) -> String {
    gymText("Remove exercise", "Видалити вправу", "Удалить упражнение", languageCode: languageCode)
}

/// Consequence line of the "Remove exercise?" alert: the exercise name plus how
/// many recorded sets disappear. With no recorded sets only planned ones are
/// affected.
func gymRemoveExerciseAlertMessage(
    name: String,
    recordedSetCount: Int,
    languageCode: String = gymCurrentLanguageCode()
) -> String {
    guard recordedSetCount > 0 else {
        return name + "\n" + gymText(
            "Its planned sets will be removed from this workout.",
            "Її заплановані підходи буде видалено з цього тренування.",
            "Его запланированные подходы будут удалены из этой тренировки.",
            languageCode: languageCode
        )
    }
    let body: String
    switch (languageCode, gymPluralCategory(recordedSetCount, languageCode: languageCode)) {
    case (AppLanguage.ukrainian.rawValue, .one):
        body = "\(recordedSetCount) записаний підхід буде видалено."
    case (AppLanguage.ukrainian.rawValue, .few):
        body = "\(recordedSetCount) записані підходи буде видалено."
    case (AppLanguage.ukrainian.rawValue, .many):
        body = "\(recordedSetCount) записаних підходів буде видалено."
    case (AppLanguage.russian.rawValue, .one):
        body = "\(recordedSetCount) записанный подход будет удалён."
    case (AppLanguage.russian.rawValue, .few):
        body = "\(recordedSetCount) записанных подхода будут удалены."
    case (AppLanguage.russian.rawValue, .many):
        body = "\(recordedSetCount) записанных подходов будут удалены."
    case (_, .one):
        body = "\(recordedSetCount) recorded set will be removed."
    default:
        body = "\(recordedSetCount) recorded sets will be removed."
    }
    return name + "\n" + body
}

/// "Remove exercise" is offered only while the saved workout keeps at least one
/// other exercise and no deletion is waiting on its undo window. Deleting the
/// whole workout stays a separate toolbar action.
func workoutDetailCanRemoveExercise(
    isEditing: Bool,
    exerciseCount: Int,
    hasPendingDeletion: Bool
) -> Bool {
    isEditing && exerciseCount > 1 && !hasPendingDeletion
}

/// A saved set can be saved from the inline editor only with a finite,
/// non-negative weight and at least one repetition.
func workoutDetailCanSaveSet(weight: Double, reps: Int) -> Bool {
    weight.isFinite && weight >= 0 && reps >= 1
}

// MARK: - Exercise card shell

/// Exercise panel shell: header (media, name + info, expand/collapse chevron,
/// optional overflow menu) followed by the caller's body and footer.
struct GymExerciseCard<Media: View, Info: View, Overflow: View, Content: View>: View {
    let name: String
    var highlighted = false
    let isCollapsed: Bool
    var accessibilityLabelText: String?
    var accessibilityValueText: String
    var accessibilityHintText: String?
    let onToggle: () -> Void
    @ViewBuilder let media: () -> Media
    @ViewBuilder let info: () -> Info
    @ViewBuilder let overflow: () -> Overflow
    @ViewBuilder let content: () -> Content

    var body: some View {
        GymPanel(highlighted: highlighted) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    media()
                    Button(action: onToggle) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(name)
                                    .font(.headline)
                                    .foregroundStyle(GymTheme.textPrimary)
                                info()
                            }
                            Spacer(minLength: 8)
                            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                                .foregroundStyle(GymTheme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabelText ?? name)
                    .accessibilityValue(accessibilityValueText)
                    .accessibilityHint(accessibilityHintText ?? "")

                    overflow()
                }
                content()
            }
        }
    }
}

/// Ellipsis menu in an exercise header whose only action is the destructive
/// "Remove exercise"; the caller decides whether to show it at all.
struct GymExerciseOverflowMenu: View {
    var disabled = false
    let onRemove: () -> Void

    var body: some View {
        Menu {
            Button(role: .destructive, action: onRemove) {
                Label(gymRemoveExerciseActionTitle(), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(GymTheme.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(disabled)
        .accessibilityLabel(
            gymText(
                "More exercise options", "Інші дії з вправою", "Другие действия с упражнением",
                languageCode: gymCurrentLanguageCode()
            )
        )
    }
}

/// Dashed-outline add action ("+ Set", "+ Add exercise").
struct GymDashedAddButton: View {
    let title: String
    let accessibilityLabelText: String
    var accessibilityHintText: String?
    var minHeight: CGFloat = 40
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GymTheme.primary)
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(GymTheme.primary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText ?? "")
        .disabled(disabled)
    }
}

// MARK: - Set rows

/// "Record" capsule on a set that beats an earlier best.
struct GymRecordBadge: View {
    var body: some View {
        Label(
            gymText("Record", "Рекорд", "Рекорд", languageCode: gymCurrentLanguageCode()),
            systemImage: "trophy.fill"
        )
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(GymTheme.brandFill))
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// Checkmark + "weight × reps" (+ record badge): the completed-set summary.
struct GymCompletedSetSummary: View {
    let summary: String
    var isPersonalRecord = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(GymTheme.secondary)
                .frame(width: 22, height: 22)
                .background(GymTheme.secondary.opacity(0.18), in: Circle())
            Text(summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GymTheme.textSecondary)
                .lineLimit(1)
            if isPersonalRecord {
                GymRecordBadge()
            }
        }
    }
}

/// A one-line completed set for read-only lists.
struct GymCompletedSetRow: View {
    let summary: String
    var isPersonalRecord = false
    let accessibilityLabelText: String

    var body: some View {
        HStack(spacing: 8) {
            GymCompletedSetSummary(summary: summary, isPersonalRecord: isPersonalRecord)
                .layoutPriority(1)
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }
}

/// A set row that expands into an inline editor: numbered circle, summary, an
/// optional record badge and trailing action, and a chevron toggle.
struct GymExpandableSetRow<Trailing: View, Editor: View>: View {
    let position: Int
    let summary: String
    var isPersonalRecord = false
    let isExpanded: Bool
    let accessibilityLabelText: String
    let accessibilityHintText: String
    let onToggle: () -> Void
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let editor: () -> Editor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: onToggle) {
                    HStack(spacing: 8) {
                        Text("\(position + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(GymTheme.textSecondary)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(GymTheme.outlineSoft, lineWidth: 1.5)
                            )
                        Text(summary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GymTheme.textSecondary)
                        if isPersonalRecord {
                            GymRecordBadge()
                        }
                        Spacer(minLength: 8)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabelText)
                .accessibilityHint(accessibilityHintText)
                trailing()
            }

            if isExpanded {
                editor()
            }
        }
        .padding(.vertical, 10)
    }
}

extension View {
    /// Long-press "Delete set" and the matching VoiceOver action. Attached only
    /// when `isEnabled`, so a set that cannot be deleted gets no menu at all.
    /// `accessibilityActionName` lets a screen give VoiceOver a more specific
    /// name than the visible menu title.
    @ViewBuilder
    func gymSetDeleteActions(
        isEnabled: Bool,
        accessibilityActionName: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        if isEnabled {
            let deleteName = gymDeleteSetActionTitle()
            self
                .accessibilityAction(named: accessibilityActionName ?? deleteName, action)
                .contextMenu {
                    Button(role: .destructive, action: action) {
                        Label(deleteName, systemImage: "trash")
                    }
                }
        } else {
            self
        }
    }
}

// MARK: - Steppers

/// One slim, equal-height pill shared by the weight and reps rows: a step
/// button at each end (44pt tap target via a larger button frame), a tiny
/// center label, and a 32–36pt-tall visual capsule centered within that larger
/// tap frame via `.background(alignment:)`.
struct GymStepCapsule: View {
    let minusLabel: String
    let minusDisabled: Bool
    let minusAction: () -> Void
    let centerLabel: String
    let plusLabel: String
    let plusDisabled: Bool
    let plusAction: () -> Void
    let accessibilityLabelText: String
    let accessibilityValueText: String
    var useSymbolGlyphs = false
    let adjustableAction: (AccessibilityAdjustmentDirection) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: minusAction) {
                Group {
                    if useSymbolGlyphs {
                        Image(systemName: minusLabel)
                    } else {
                        Text(minusLabel)
                    }
                }
                .font(useSymbolGlyphs ? .body.weight(.semibold) : .caption2.weight(.bold))
                .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(minusDisabled)

            Text(centerLabel)
                .font(.caption2)
                .foregroundStyle(GymTheme.textSecondary)
                .frame(maxWidth: .infinity)

            Button(action: plusAction) {
                Group {
                    if useSymbolGlyphs {
                        Image(systemName: plusLabel)
                    } else {
                        Text(plusLabel)
                    }
                }
                .font(useSymbolGlyphs ? .body.weight(.semibold) : .caption2.weight(.bold))
                .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(plusDisabled)
        }
        .buttonStyle(.plain)
        .foregroundStyle(GymTheme.primary)
        .background(alignment: .center) {
            Capsule().fill(GymTheme.surface).frame(height: 34)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            guard !(minusDisabled && plusDisabled) else { return }
            adjustableAction(direction)
        }
    }
}

/// "−2,5   вес   +2,5" capsule: honors a machine's allowed weights and shows
/// the nominal step even when that direction is blocked.
struct GymWeightStepCapsule: View {
    let weight: Double
    var allowedWeights: [Double] = []
    var disabled = false
    let onChange: (Double) -> Void

    var body: some View {
        // Nominal step shown even when that direction is blocked (e.g. at
        // 0 kg or at the machine's lowest stop): the default 2.5 kg
        // increment, or the smallest gap between the machine's allowed
        // weights when it has one.
        let nominalStep: Double = {
            guard allowedWeights.count >= 2 else { return 2.5 }
            let gaps = zip(allowedWeights, allowedWeights.dropFirst()).map { $1 - $0 }
            return gaps.min() ?? 2.5
        }()
        let minusWeight = TrainingTools.stepWeight(weight, direction: -1, allowed: allowedWeights)
        let minusCanMove = minusWeight != weight
        let minusDelta = minusCanMove ? abs(minusWeight - weight) : nominalStep
        let plusWeight = TrainingTools.stepWeight(weight, direction: 1, allowed: allowedWeights)
        let plusCanMove = plusWeight != weight
        let plusDelta = plusCanMove ? abs(plusWeight - weight) : nominalStep
        let minusText = minusDelta.formatted(.number.locale(gymAppLocale()))
        let plusText = plusDelta.formatted(.number.locale(gymAppLocale()))

        return GymStepCapsule(
            minusLabel: "−" + minusText,
            minusDisabled: disabled || !minusCanMove,
            minusAction: { onChange(minusWeight) },
            centerLabel: gymText("weight", "вага", "вес", languageCode: gymCurrentLanguageCode()),
            plusLabel: "+" + plusText,
            plusDisabled: disabled || !plusCanMove,
            plusAction: { onChange(plusWeight) },
            accessibilityLabelText: gymText("Weight", "Вага", "Вес", languageCode: gymCurrentLanguageCode()),
            accessibilityValueText: "\(weight.formatted(.number.locale(gymAppLocale()))) \(gymLocalized("kg"))",
            adjustableAction: { direction in
                switch direction {
                case .increment: if plusCanMove { onChange(plusWeight) }
                case .decrement: if minusCanMove { onChange(minusWeight) }
                @unknown default: break
                }
            }
        )
    }
}

/// "−   повт.   +" capsule for reps.
struct GymRepsStepCapsule: View {
    @Binding var reps: Int
    var disabled = false

    var body: some View {
        GymStepCapsule(
            minusLabel: "minus",
            minusDisabled: disabled || reps <= 1,
            minusAction: { reps = max(1, reps - 1) },
            centerLabel: gymText("reps", "повт.", "повт.", languageCode: gymCurrentLanguageCode()),
            plusLabel: "plus",
            plusDisabled: disabled,
            plusAction: { reps += 1 },
            accessibilityLabelText: gymText("Reps", "Повторення", "Повторы", languageCode: gymCurrentLanguageCode()),
            accessibilityValueText: reps.formatted(.number.locale(gymAppLocale())),
            useSymbolGlyphs: true,
            adjustableAction: { direction in
                switch direction {
                case .increment: reps += 1
                case .decrement: reps = max(1, reps - 1)
                @unknown default: break
                }
            }
        )
    }
}

/// Inline editor for one saved set: the big "weight kg × reps" line, the same
/// weight/reps step capsules the active workout uses, and a primary action
/// ("Save"). Holds the draft values locally and re-syncs when the stored set
/// changes underneath it.
struct GymSetStepperEditor: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var weight: Double
    @State private var reps: Int

    let position: Int
    let storedWeight: Double
    let storedReps: Int
    var allowedWeights: [Double] = []
    var disabled = false
    let actionTitle: String
    let actionAccessibilityLabel: String
    let onSave: (Double, Int) -> Void

    init(
        position: Int,
        storedWeight: Double,
        storedReps: Int,
        allowedWeights: [Double] = [],
        disabled: Bool = false,
        actionTitle: String,
        actionAccessibilityLabel: String,
        onSave: @escaping (Double, Int) -> Void
    ) {
        self.position = position
        self.storedWeight = storedWeight
        self.storedReps = storedReps
        self.allowedWeights = allowedWeights
        self.disabled = disabled
        self.actionTitle = actionTitle
        self.actionAccessibilityLabel = actionAccessibilityLabel
        self.onSave = onSave
        _weight = State(initialValue: storedWeight)
        _reps = State(initialValue: storedReps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Spacer(minLength: 0)
                TextField(
                    "0",
                    value: $weight,
                    format: .number.precision(.fractionLength(0 ... 2))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 30, weight: .semibold).monospacedDigit())
                .foregroundStyle(GymTheme.textPrimary)
                .fixedSize()
                .disabled(disabled)
                .accessibilityLabel(
                    gymText(
                        "Weight for set \(position + 1)",
                        "Вага для підходу \(position + 1)",
                        "Вес для подхода \(position + 1)",
                        languageCode: gymCurrentLanguageCode()
                    )
                )

                Text(gymLocalized("kg"))
                    .font(.system(size: 15))
                    .foregroundStyle(GymTheme.textSecondary)

                Text(verbatim: "×")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(GymTheme.textSecondary)
                    .accessibilityHidden(true)

                Text(reps.formatted(.number.locale(gymAppLocale())))
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .foregroundStyle(GymTheme.textPrimary)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { steppers }
            } else {
                HStack(spacing: 8) { steppers }
            }

            Button {
                onSave(weight, reps)
            } label: {
                Text(actionTitle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GymPrimaryButtonStyle())
            .disabled(disabled || !workoutDetailCanSaveSet(weight: weight, reps: reps))
            .accessibilityLabel(actionAccessibilityLabel)
        }
        .padding(10)
        .background(GymTheme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: storedWeight) { _, newValue in weight = newValue }
        .onChange(of: storedReps) { _, newValue in reps = newValue }
    }

    @ViewBuilder
    private var steppers: some View {
        GymWeightStepCapsule(
            weight: weight,
            allowedWeights: allowedWeights,
            disabled: disabled,
            onChange: { weight = $0 }
        )
        GymRepsStepCapsule(reps: $reps, disabled: disabled)
    }
}
