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
    /// False for a card that is always open (the plan editor): no chevron and
    /// no toggle, just the header and the body.
    var collapsible = true
    var isCollapsed = false
    var accessibilityLabelText: String?
    var accessibilityValueText = ""
    var accessibilityHintText: String?
    /// Gap between the header and the body.
    var contentSpacing: CGFloat = 14
    var onToggle: () -> Void = {}
    @ViewBuilder let media: () -> Media
    @ViewBuilder let info: () -> Info
    @ViewBuilder let overflow: () -> Overflow
    @ViewBuilder let content: () -> Content

    var body: some View {
        GymPanel(highlighted: highlighted) {
            VStack(alignment: .leading, spacing: contentSpacing) {
                HStack(spacing: 10) {
                    media()
                    if collapsible {
                        Button(action: onToggle) {
                            HStack(spacing: 8) {
                                titleBlock
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
                    } else {
                        titleBlock
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)
                    }

                    overflow()
                }
                content()
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.headline)
                .foregroundStyle(GymTheme.textPrimary)
            info()
        }
    }
}

/// Ellipsis menu in an exercise header: optional extra items (for example
/// "Replace with similar") above the destructive remove action; the caller
/// decides whether to show it at all.
struct GymExerciseOverflowMenu<Extra: View>: View {
    var disabled = false
    /// Title of the destructive item ("Remove exercise" by default).
    var removeTitle = gymRemoveExerciseActionTitle()
    var accessibilityLabelText: String?
    let onRemove: () -> Void
    @ViewBuilder let extraItems: () -> Extra

    var body: some View {
        Menu {
            extraItems()
            Button(role: .destructive, action: onRemove) {
                Label(removeTitle, systemImage: "trash")
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
            accessibilityLabelText ?? gymText(
                "More exercise options", "Інші дії з вправою", "Другие действия с упражнением",
                languageCode: gymCurrentLanguageCode()
            )
        )
    }
}

extension GymExerciseOverflowMenu where Extra == EmptyView {
    init(
        disabled: Bool = false,
        removeTitle: String = gymRemoveExerciseActionTitle(),
        accessibilityLabelText: String? = nil,
        onRemove: @escaping () -> Void
    ) {
        self.init(
            disabled: disabled,
            removeTitle: removeTitle,
            accessibilityLabelText: accessibilityLabelText,
            onRemove: onRemove,
            extraItems: { EmptyView() }
        )
    }
}

/// Dashed-outline add action ("+ Set", "+ Add exercise").
struct GymDashedAddButton: View {
    let title: String
    let accessibilityLabelText: String
    var accessibilityHintText: String?
    var minHeight: CGFloat = 48
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
        .frame(minHeight: 44)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }
}

/// Outlined 22pt set-number circle shared by the active, saved, and plan rows.
struct GymSetNumberBadge: View {
    let position: Int

    var body: some View {
        Text("\(position + 1)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(GymTheme.textSecondary)
            .frame(width: 22, height: 22)
            .overlay(
                Circle().strokeBorder(GymTheme.outlineSoft, lineWidth: 1.5)
            )
            .accessibilityHidden(true)
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
                        GymSetNumberBadge(position: position)
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

// MARK: - Shared set editor

/// Height of every capsule in the set editor; the trash target beside them is the
/// same 44pt.
let gymSetEditorCapsuleHeight: CGFloat = 44

/// Step targets for a weight capsule: honors a machine's allowed weights (empty
/// means the default 2.5 kg) and keeps the nominal step visible for a blocked
/// direction.
func gymWeightStepTargets(
    weight: Double,
    allowedWeights: [Double]
) -> (minus: Double, minusDelta: Double, plus: Double, plusDelta: Double) {
    let nominalStep: Double = {
        guard allowedWeights.count >= 2 else { return 2.5 }
        let gaps = zip(allowedWeights, allowedWeights.dropFirst()).map { $1 - $0 }
        return gaps.min() ?? 2.5
    }()
    let minus = TrainingTools.stepWeight(weight, direction: -1, allowed: allowedWeights)
    let plus = TrainingTools.stepWeight(weight, direction: 1, allowed: allowedWeights)
    return (
        minus,
        minus != weight ? abs(minus - weight) : nominalStep,
        plus,
        plus != weight ? abs(plus - weight) : nominalStep
    )
}

/// Trash button with a 44pt target and error tint, named for VoiceOver.
struct GymSetDeleteButton: View {
    let accessibilityLabelText: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(GymTheme.error.opacity(disabled ? 0.38 : 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabelText)
    }
}

/// The one set editor: a `− 12 kg +` weight capsule and a `− 4 +` reps capsule of
/// equal size and fill, side by side (stacked at accessibility text sizes), with
/// an optional trash button at the end. The weight value is tappable for keyboard
/// entry; stepping follows `allowedWeights` (empty = 2.5 kg). Used by the active
/// workout's upcoming sets and the saved workout's set editor.
struct GymSetEditorCapsules: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var weightFieldFocused: Bool

    let position: Int
    @Binding var weight: Double
    @Binding var reps: Int
    var allowedWeights: [Double] = []
    var disabled = false
    /// Parent-driven focus (the active screen's keyboard Done bar) and its report.
    var externalWeightFocus = false
    var onWeightFocusChange: ((Bool) -> Void)?
    var deleteAccessibilityLabel: String?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { weightCapsule; repsCapsule }
            } else {
                // The weight capsule carries "102.5 kg" next to the step buttons,
                // so it gets ~1.4x the reps capsule's width at the same height.
                GymWeightedRow(weights: [1.4, 1], spacing: 8) { weightCapsule; repsCapsule }
            }
            if let onDelete, let deleteAccessibilityLabel {
                GymSetDeleteButton(
                    accessibilityLabelText: deleteAccessibilityLabel,
                    disabled: disabled,
                    action: onDelete
                )
            }
        }
        .onChange(of: weightFieldFocused) { _, focused in onWeightFocusChange?(focused) }
        .onChange(of: externalWeightFocus) { _, focused in
            if weightFieldFocused != focused { weightFieldFocused = focused }
        }
    }

    /// Long values ("102.5") shrink a little instead of clipping in the
    /// narrower weight capsule on small phones.
    private var weightValueFontSize: CGFloat {
        let characters = weight.formatted(
            .number.locale(gymAppLocale()).precision(.fractionLength(0 ... 2))
        ).count
        switch characters {
        case ...4: return 17
        case 5: return 15
        default: return 13
        }
    }

    private var weightCapsule: some View {
        let targets = gymWeightStepTargets(weight: weight, allowedWeights: allowedWeights)
        let kg = gymLocalized("kg")
        let minusText = targets.minusDelta.formatted(.number.locale(gymAppLocale()))
        let plusText = targets.plusDelta.formatted(.number.locale(gymAppLocale()))
        let minusCanMove = targets.minus != weight
        let plusCanMove = targets.plus != weight
        return GymSetValueCapsule(
            minusSystemImage: "minus",
            minusDisabled: disabled || !minusCanMove,
            minusAction: { weight = targets.minus },
            minusAccessibilityLabel: gymText(
                "Decrease weight by \(minusText) \(kg)",
                "Зменшити вагу на \(minusText) \(kg)",
                "Уменьшить вес на \(minusText) \(kg)",
                languageCode: gymCurrentLanguageCode()
            ),
            plusSystemImage: "plus",
            plusDisabled: disabled || !plusCanMove,
            plusAction: { weight = targets.plus },
            plusAccessibilityLabel: gymText(
                "Increase weight by \(plusText) \(kg)",
                "Збільшити вагу на \(plusText) \(kg)",
                "Увеличить вес на \(plusText) \(kg)",
                languageCode: gymCurrentLanguageCode()
            ),
            stepButtonWidth: 34
        ) {
            HStack(spacing: 3) {
                TextField(
                    "0",
                    value: $weight,
                    format: .number.precision(.fractionLength(0 ... 2))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: weightValueFontSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(GymTheme.textPrimary)
                .focused($weightFieldFocused)
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
                Text(kg)
                    .font(weightValueFontSize < 17 ? .caption2 : .footnote)
                    .foregroundStyle(GymTheme.textSecondary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture { if !disabled { weightFieldFocused = true } }
        }
    }

    private var repsCapsule: some View {
        GymSetValueCapsule(
            minusSystemImage: "minus",
            minusDisabled: disabled || reps <= 1,
            minusAction: { reps = max(1, reps - 1) },
            minusAccessibilityLabel: gymText(
                "Decrease reps", "Зменшити повторення", "Уменьшить повторения",
                languageCode: gymCurrentLanguageCode()
            ),
            plusSystemImage: "plus",
            plusDisabled: disabled,
            plusAction: { reps += 1 },
            plusAccessibilityLabel: gymText(
                "Increase reps", "Збільшити повторення", "Увеличить повторения",
                languageCode: gymCurrentLanguageCode()
            )
        ) {
            Text(reps.formatted(.number.locale(gymAppLocale())))
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(GymTheme.textPrimary)
                .lineLimit(1)
                .accessibilityLabel(
                    gymText(
                        "Repetitions for set \(position + 1)",
                        "Повторення для підходу \(position + 1)",
                        "Повторения для подхода \(position + 1)",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                .accessibilityValue(reps.formatted(.number.locale(gymAppLocale())))
        }
    }
}

/// Horizontal stack that splits its width between subviews in fixed ratios
/// (every child proposed `weight / total` of the free width).
struct GymWeightedRow: Layout {
    let weights: [CGFloat]
    var spacing: CGFloat = 8

    init(weights: [CGFloat], spacing: CGFloat = 8) {
        self.weights = weights
        self.spacing = spacing
    }

    private func widths(for subviews: Subviews, total: CGFloat) -> [CGFloat] {
        let count = CGFloat(subviews.count)
        let free = max(0, total - spacing * max(0, count - 1))
        let weightSum = subviews.indices.reduce(CGFloat(0)) { $0 + (weights.indices.contains($1) ? weights[$1] : 1) }
        return subviews.indices.map { index in
            free * (weights.indices.contains(index) ? weights[index] : 1) / max(weightSum, 0.001)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width.map { $0.isFinite ? $0 : 320 } ?? 240
        let columnWidths = widths(for: subviews, total: total)
        let height = zip(subviews, columnWidths).map {
            $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height
        }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidths = widths(for: subviews, total: bounds.width)
        var x = bounds.minX
        for (subview, width) in zip(subviews, columnWidths) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }
}

/// One capsule of the set editor: step button, centered value content, step
/// button. 44pt tall, fully rounded, shared fill.
private struct GymSetValueCapsule<Center: View>: View {
    let minusSystemImage: String
    let minusDisabled: Bool
    let minusAction: () -> Void
    let minusAccessibilityLabel: String
    let plusSystemImage: String
    let plusDisabled: Bool
    let plusAction: () -> Void
    let plusAccessibilityLabel: String
    var stepButtonWidth: CGFloat = 38
    @ViewBuilder let center: () -> Center

    var body: some View {
        HStack(spacing: 0) {
            stepButton(
                systemImage: minusSystemImage,
                disabled: minusDisabled,
                label: minusAccessibilityLabel,
                action: minusAction
            )
            center()
                .frame(maxWidth: .infinity)
            stepButton(
                systemImage: plusSystemImage,
                disabled: plusDisabled,
                label: plusAccessibilityLabel,
                action: plusAction
            )
        }
        .frame(maxWidth: .infinity, minHeight: gymSetEditorCapsuleHeight)
        .background(
            Capsule()
                .fill(GymTheme.surfaceVariant)
                .overlay(Capsule().strokeBorder(GymTheme.outlineSoft, lineWidth: GymTheme.hairlineWidth))
        )
    }

    private func stepButton(
        systemImage: String,
        disabled: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(GymTheme.primary.opacity(disabled ? 0.38 : 1))
                .frame(width: stepButtonWidth, height: gymSetEditorCapsuleHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

/// Inline editor for one saved set: the shared capsule editor (with the trash
/// button when deletion is allowed) and a primary action ("Save") under it. Holds
/// the draft values locally and re-syncs when the stored set changes underneath it.
struct GymSetStepperEditor: View {
    @State private var weight: Double
    @State private var reps: Int

    let position: Int
    let storedWeight: Double
    let storedReps: Int
    var allowedWeights: [Double] = []
    var disabled = false
    let actionTitle: String
    let actionAccessibilityLabel: String
    var deleteAccessibilityLabel: String?
    var onDelete: (() -> Void)?
    let onSave: (Double, Int) -> Void

    init(
        position: Int,
        storedWeight: Double,
        storedReps: Int,
        allowedWeights: [Double] = [],
        disabled: Bool = false,
        actionTitle: String,
        actionAccessibilityLabel: String,
        deleteAccessibilityLabel: String? = nil,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (Double, Int) -> Void
    ) {
        self.position = position
        self.storedWeight = storedWeight
        self.storedReps = storedReps
        self.allowedWeights = allowedWeights
        self.disabled = disabled
        self.actionTitle = actionTitle
        self.actionAccessibilityLabel = actionAccessibilityLabel
        self.deleteAccessibilityLabel = deleteAccessibilityLabel
        self.onDelete = onDelete
        self.onSave = onSave
        _weight = State(initialValue: storedWeight)
        _reps = State(initialValue: storedReps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GymSetEditorCapsules(
                position: position,
                weight: $weight,
                reps: $reps,
                allowedWeights: allowedWeights,
                disabled: disabled,
                deleteAccessibilityLabel: deleteAccessibilityLabel,
                onDelete: onDelete
            )

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
        .onChange(of: storedWeight) { _, newValue in weight = newValue }
        .onChange(of: storedReps) { _, newValue in reps = newValue }
    }
}
