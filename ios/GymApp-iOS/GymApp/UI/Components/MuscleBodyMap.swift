import SwiftUI

struct MuscleBodyMap: View {
    let intensityByMuscle: [String: Double]
    let selectedMuscleID: String?
    let selectedMuscleLabel: String?
    let onMuscleSelected: (String) -> Void

    private static let frontRegions = OpenSourceMuscleRegions.front.map(RenderedMuscleRegion.init)
    private static let backRegions = OpenSourceMuscleRegions.back.map(RenderedMuscleRegion.init)

    var body: some View {
        GeometryReader { proxy in
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, size in
                let layout = BodyMapLayout(size: size)
                drawFigure(
                    context: &context,
                    regions: Self.frontRegions,
                    transform: layout.frontTransform,
                    scale: layout.scale
                )
                drawFigure(
                    context: &context,
                    regions: Self.backRegions,
                    transform: layout.backTransform,
                    scale: layout.scale
                )
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if let muscleID = muscleID(at: value.location, size: proxy.size) {
                            onMuscleSelected(muscleID)
                        }
                    }
            )
        }
        .frame(height: 360)
        .padding(.horizontal, 6)
        .background(
            GymTheme.surface.opacity(0.32),
            in: RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius, style: .continuous)
                .strokeBorder(GymTheme.outlineSoft.opacity(0.46), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gymLocalized("Interactive muscle map"))
        .accessibilityValue(selectedMuscleLabel ?? gymLocalized("No muscle selected"))
        .accessibilityHint(gymLocalized("Tap a highlighted body region to select that muscle group."))
    }

    private func drawFigure(
        context: inout GraphicsContext,
        regions: [RenderedMuscleRegion],
        transform: CGAffineTransform,
        scale: CGFloat
    ) {
        for region in regions {
            let muscleID = MuscleBodyRegionMapping.muscleID(for: region.source.id)
            let intensity = muscleID.flatMap { intensityByMuscle[$0] } ?? 0
            let fill = intensity > 0
                ? MuscleHeatPalette.color(intensity: intensity)
                : GymTheme.surfaceVariant.opacity(0.52)
            let path = region.path.applying(transform)

            context.fill(path, with: .color(fill))
            context.stroke(
                path,
                with: .color(GymTheme.outline.opacity(0.5)),
                lineWidth: max(0.55, 0.12 * scale)
            )

            if muscleID == selectedMuscleID {
                context.stroke(
                    path,
                    with: .color(GymTheme.primary),
                    lineWidth: max(1.6, 0.42 * scale)
                )
            }
        }
    }

    private func muscleID(at location: CGPoint, size: CGSize) -> String? {
        let layout = BodyMapLayout(size: size)
        let figures = [
            (Self.frontRegions, layout.frontTransform),
            (Self.backRegions, layout.backTransform)
        ]

        for (regions, transform) in figures {
            for region in regions.reversed() {
                guard let muscleID = MuscleBodyRegionMapping.muscleID(for: region.source.id) else {
                    continue
                }
                let path = region.path.applying(transform)
                if path.contains(location) {
                    return muscleID
                }
            }
        }

        // Small anatomical regions are difficult to hit precisely on a phone.
        // Match Android's forgiving bounds-based selection as a fallback.
        for (regions, transform) in figures {
            for region in regions.reversed() {
                guard let muscleID = MuscleBodyRegionMapping.muscleID(for: region.source.id) else {
                    continue
                }
                let bounds = region.path.applying(transform).boundingRect.insetBy(dx: -3, dy: -3)
                if bounds.contains(location) {
                    return muscleID
                }
            }
        }
        return nil
    }
}

struct MuscleBodyMapLegend: View {
    private let intensities = [0.0, 0.25, 0.5, 0.75, 1.0]

    var body: some View {
        HStack(spacing: 8) {
            Text("Less")
            ForEach(Array(intensities.enumerated()), id: \.offset) { _, intensity in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        intensity == 0
                            ? GymTheme.surfaceVariant.opacity(0.56)
                            : MuscleHeatPalette.color(intensity: intensity)
                    )
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            }
            Text("More")
        }
        .font(.caption)
        .foregroundStyle(GymTheme.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(gymLocalized("Muscle load scale, less activity to more activity"))
    }
}

enum MuscleBodyRegionMapping {
    static func muscleID(for regionID: String) -> String? {
        switch regionID {
        case let id where id.contains("chest"):
            "chest"
        case let id where id.contains("shoulder") || id.contains("deltoid"):
            "shoulders"
        case let id where id.contains("biceps"):
            "biceps"
        case let id where id.contains("triceps"):
            "triceps"
        case let id where id.contains("forearm"):
            "forearms"
        case let id where id.contains("obliques") || id.contains("serratus"):
            "obliques"
        case let id where id.contains("abs"):
            "abs"
        case let id where id.contains("traps"):
            "upperBack"
        case let id where id.contains("lats"):
            "lats"
        case "spine":
            "lowerBack"
        case let id where id.contains("lower-back"):
            "lowerBack"
        case let id where id.contains("gluteus"):
            "glutes"
        case let id where id.contains("quads"):
            "quads"
        case let id where id.contains("adductors") || id.contains("hip-flexor"):
            "adductors"
        case let id where id.contains("hamstrings"):
            "hamstrings"
        case let id where id.contains("calves") || id.contains("tibialis"):
            "calves"
        default:
            nil
        }
    }
}

enum SVGPathParser {
    static func path(from data: String) -> Path {
        let tokens = tokenize(data)
        var index = 0
        var command: Character?
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        while index < tokens.count {
            if case let .command(nextCommand) = tokens[index] {
                command = nextCommand
                index += 1
                if nextCommand == "z" || nextCommand == "Z" {
                    path.closeSubpath()
                    current = subpathStart
                    command = nil
                    continue
                }
            }

            guard let activeCommand = command else {
                index += 1
                continue
            }
            let startIndex = index

            switch activeCommand {
            case "M", "m":
                let relative = activeCommand == "m"
                var firstPoint = true
                while hasNumbers(2, tokens: tokens, at: index),
                      let x = readNumber(tokens, index: &index),
                      let y = readNumber(tokens, index: &index) {
                    let point = relative
                        ? CGPoint(x: current.x + x, y: current.y + y)
                        : CGPoint(x: x, y: y)
                    if firstPoint {
                        path.move(to: point)
                        subpathStart = point
                        firstPoint = false
                    } else {
                        path.addLine(to: point)
                    }
                    current = point
                }

            case "L", "l":
                let relative = activeCommand == "l"
                while hasNumbers(2, tokens: tokens, at: index),
                      let x = readNumber(tokens, index: &index),
                      let y = readNumber(tokens, index: &index) {
                    let point = relative
                        ? CGPoint(x: current.x + x, y: current.y + y)
                        : CGPoint(x: x, y: y)
                    path.addLine(to: point)
                    current = point
                }

            case "H", "h":
                let relative = activeCommand == "h"
                while let x = readNumber(tokens, index: &index) {
                    current.x = relative ? current.x + x : x
                    path.addLine(to: current)
                }

            case "V", "v":
                let relative = activeCommand == "v"
                while let y = readNumber(tokens, index: &index) {
                    current.y = relative ? current.y + y : y
                    path.addLine(to: current)
                }

            case "C", "c":
                let relative = activeCommand == "c"
                while hasNumbers(6, tokens: tokens, at: index),
                      let x1 = readNumber(tokens, index: &index),
                      let y1 = readNumber(tokens, index: &index),
                      let x2 = readNumber(tokens, index: &index),
                      let y2 = readNumber(tokens, index: &index),
                      let x = readNumber(tokens, index: &index),
                      let y = readNumber(tokens, index: &index) {
                    let control1 = relative
                        ? CGPoint(x: current.x + x1, y: current.y + y1)
                        : CGPoint(x: x1, y: y1)
                    let control2 = relative
                        ? CGPoint(x: current.x + x2, y: current.y + y2)
                        : CGPoint(x: x2, y: y2)
                    let point = relative
                        ? CGPoint(x: current.x + x, y: current.y + y)
                        : CGPoint(x: x, y: y)
                    path.addCurve(to: point, control1: control1, control2: control2)
                    current = point
                }

            default:
                command = nil
            }

            if index == startIndex, index < tokens.count,
               case .number = tokens[index] {
                index += 1
            }
        }
        return path
    }

    private static func hasNumbers(_ count: Int, tokens: [SVGPathToken], at index: Int) -> Bool {
        guard index + count <= tokens.count else { return false }
        return tokens[index ..< index + count].allSatisfy {
            if case .number = $0 { return true }
            return false
        }
    }

    private static func readNumber(_ tokens: [SVGPathToken], index: inout Int) -> CGFloat? {
        guard index < tokens.count, case let .number(value) = tokens[index] else { return nil }
        index += 1
        return value
    }

    private static func tokenize(_ data: String) -> [SVGPathToken] {
        let characters = Array(data)
        let commands = Set("MmLlHhVvCcZz")
        var result: [SVGPathToken] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if commands.contains(character) {
                result.append(.command(character))
                index += 1
                continue
            }
            if character == " " || character == "," || character == "\n" || character == "\t" {
                index += 1
                continue
            }

            let start = index
            if characters[index] == "+" || characters[index] == "-" {
                index += 1
            }
            while index < characters.count, characters[index].isNumber {
                index += 1
            }
            if index < characters.count, characters[index] == "." {
                index += 1
                while index < characters.count, characters[index].isNumber {
                    index += 1
                }
            }
            if index < characters.count,
               (characters[index] == "e" || characters[index] == "E") {
                let exponentStart = index
                index += 1
                if index < characters.count,
                   (characters[index] == "+" || characters[index] == "-") {
                    index += 1
                }
                let digitStart = index
                while index < characters.count, characters[index].isNumber {
                    index += 1
                }
                if digitStart == index {
                    index = exponentStart
                }
            }

            if start < index,
               let value = Double(String(characters[start ..< index])) {
                result.append(.number(CGFloat(value)))
            } else {
                index = start + 1
            }
        }
        return result
    }
}

private enum SVGPathToken {
    case command(Character)
    case number(CGFloat)
}

private struct RenderedMuscleRegion: @unchecked Sendable {
    let source: SourceMuscleRegion
    let path: Path

    init(_ source: SourceMuscleRegion) {
        self.source = source
        self.path = SVGPathParser.path(from: source.pathData)
    }
}

private struct BodyMapLayout {
    let scale: CGFloat
    let frontTransform: CGAffineTransform
    let backTransform: CGAffineTransform

    init(size: CGSize) {
        let horizontalGap = min(28, size.width * 0.12)
        let availableFigureWidth = max(24, (size.width - horizontalGap) / 2)
        let availableFigureHeight = max(24, size.height - 6)
        scale = min(
            availableFigureWidth / OpenSourceMuscleRegions.bodyViewBoxWidth,
            availableFigureHeight / OpenSourceMuscleRegions.bodyViewBoxHeight
        )
        let figureWidth = OpenSourceMuscleRegions.bodyViewBoxWidth * scale
        let figureHeight = OpenSourceMuscleRegions.bodyViewBoxHeight * scale
        let top = (size.height - figureHeight) / 2
        let frontLeft = size.width * 0.27 - figureWidth / 2
        let backLeft = size.width * 0.73 - figureWidth / 2
        frontTransform = Self.transform(
            scale: scale,
            left: frontLeft,
            top: top,
            viewBoxMinX: OpenSourceMuscleRegions.frontViewBoxMinX
        )
        backTransform = Self.transform(
            scale: scale,
            left: backLeft,
            top: top,
            viewBoxMinX: OpenSourceMuscleRegions.backViewBoxMinX
        )
    }

    private static func transform(
        scale: CGFloat,
        left: CGFloat,
        top: CGFloat,
        viewBoxMinX: CGFloat
    ) -> CGAffineTransform {
        CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: left - viewBoxMinX * scale,
            ty: top
        )
    }
}

private enum MuscleHeatPalette {
    private struct RGBA {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        func mixed(with other: RGBA, fraction: Double) -> RGBA {
            let value = min(1, max(0, fraction))
            return RGBA(
                red: red + (other.red - red) * value,
                green: green + (other.green - green) * value,
                blue: blue + (other.blue - blue) * value,
                alpha: alpha + (other.alpha - alpha) * value
            )
        }

        var color: Color {
            Color(red: red, green: green, blue: blue).opacity(alpha)
        }
    }

    private static let low = RGBA(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255, alpha: 1)
    private static let medium = RGBA(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255, alpha: 1)
    private static let high = RGBA(red: 0xE1 / 255, green: 0x1D / 255, blue: 0x48 / 255, alpha: 1)
    private static let peak = RGBA(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255, alpha: 1)

    static func color(intensity: Double) -> Color {
        let value = min(1, max(0, intensity))
        switch value {
        case ..<0.28:
            return RGBA(red: low.red, green: low.green, blue: low.blue, alpha: 0.42)
                .mixed(with: low, fraction: value / 0.28)
                .color
        case ..<0.58:
            return low.mixed(with: medium, fraction: (value - 0.28) / 0.30).color
        case ..<0.86:
            return medium.mixed(with: high, fraction: (value - 0.58) / 0.28).color
        default:
            return high.mixed(with: peak, fraction: (value - 0.86) / 0.14).color
        }
    }
}
