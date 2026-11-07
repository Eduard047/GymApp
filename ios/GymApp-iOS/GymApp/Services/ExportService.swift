import Foundation
import UIKit

enum ExportService {
    struct DiagnosticsContext: Equatable, Sendable {
        let version: String
        let build: String
        let operatingSystemVersion: String
        let localeIdentifier: String
        let cloudSyncEnabled: Bool
        let hasSuccessfulSync: Bool
        let hasError: Bool
    }

    /// Explicit diagnostics allowlist. This type cannot accept owners, sessions, notes,
    /// exercise names, set values, or authentication state.
    private struct DiagnosticsReport: Encodable {
        struct Application: Encodable {
            let version: String
            let build: String
            let operatingSystemVersion: String
            let localeIdentifier: String
        }

        struct WorkoutData: Encodable {
            let exerciseCount: Int
            let workoutCount: Int
            let setCount: Int
            let manualMuscleMappingCount: Int
        }

        struct CloudSync: Encodable {
            let enabled: Bool
            let hasSuccessfulSync: Bool
            let hasError: Bool
        }

        let schemaVersion = 1
        let reportType = "diagnostics"
        let application: Application
        let workoutData: WorkoutData
        let cloudSync: CloudSync
    }

    static func diagnosticsJSON(
        snapshot: WorkoutDiagnosticsSnapshot,
        context: DiagnosticsContext,
        prettyPrinted: Bool = true
    ) throws -> Data {
        let report = DiagnosticsReport(
            application: .init(
                version: context.version,
                build: context.build,
                operatingSystemVersion: context.operatingSystemVersion,
                localeIdentifier: context.localeIdentifier
            ),
            workoutData: .init(
                exerciseCount: snapshot.exerciseCount,
                workoutCount: snapshot.workoutCount,
                setCount: snapshot.setCount,
                manualMuscleMappingCount: snapshot.manualMuscleMappingCount
            ),
            cloudSync: .init(
                enabled: context.cloudSyncEnabled,
                hasSuccessfulSync: context.hasSuccessfulSync,
                hasError: context.hasError
            )
        )
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        if prettyPrinted { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        return try encoder.encode(report)
    }

    static func writeJSON(_ data: Data, name: String = "GymApp-backup") throws -> URL {
        let url = temporaryURL(name: name, extension: "json")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }

    static func writeDiagnosticsPDF(
        title: String = "GymApp diagnostics",
        sections: [(heading: String, lines: [String])]
    ) throws -> URL {
        let url = temporaryURL(name: "GymApp-diagnostics", extension: "pdf")
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { context in
            let margin: CGFloat = 44
            let maxWidth = page.width - margin * 2
            var y: CGFloat = margin

            func nextPageIfNeeded(_ height: CGFloat) {
                if y + height > page.height - margin {
                    context.beginPage()
                    y = margin
                }
            }

            func draw(_ text: String, font: UIFont, color: UIColor = .label, spacing: CGFloat = 8) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                paragraph.lineSpacing = 2
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let bounds = (text as NSString).boundingRect(
                    with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                nextPageIfNeeded(bounds.height + spacing)
                (text as NSString).draw(
                    with: CGRect(x: margin, y: y, width: maxWidth, height: ceil(bounds.height)),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                y += ceil(bounds.height) + spacing
            }

            context.beginPage()
            draw(gymLocalized(title), font: .boldSystemFont(ofSize: 24), spacing: 18)
            draw(
                gymText(
                    "Generated \(gymFormattedTimestamp(Date(), date: .abbreviated, time: .standard))",
                    "Створено \(gymFormattedTimestamp(Date(), date: .abbreviated, time: .standard))",
                    "Создано \(gymFormattedTimestamp(Date(), date: .abbreviated, time: .standard))",
                    languageCode: gymCurrentLanguageCode()
                ),
                font: .systemFont(ofSize: 10),
                color: .secondaryLabel,
                spacing: 18
            )
            for section in sections {
                draw(section.heading, font: .boldSystemFont(ofSize: 15), spacing: 8)
                for line in section.lines {
                    draw(line, font: .monospacedSystemFont(ofSize: 10, weight: .regular), color: .darkGray, spacing: 5)
                }
                y += 10
            }
        }
        try (url as NSURL).setResourceValue(URLFileProtection.completeUnlessOpen, forKey: .fileProtectionKey)
        return url
    }

    /// Workout report PDF: `WorkoutReport.lines` drawn with measured wrapping and height-based
    /// pagination, capped at `WorkoutReport.maxPages` like Android.
    static func writeWorkoutPDF(lines: [String], name: String = "GymApp-workouts") throws -> URL {
        let url = temporaryURL(name: name, extension: "pdf")
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let marginX: CGFloat = 44
        let top: CGFloat = 48
        let bottom: CGFloat = page.height - 44
        let lineHeight: CGFloat = 16
        let maxWidth = page.width - marginX * 2
        let ink = UIColor(red: 20 / 255, green: 32 / 255, blue: 44 / 255, alpha: 1)
        let bodyInk = UIColor(red: 45 / 255, green: 56 / 255, blue: 70 / 255, alpha: 1)
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: ink]
        let headingAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: ink]
        let bodyAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: bodyInk]

        try renderer.writePDF(to: url) { context in
            var pageNumber = 1
            var y = top
            var pageLimitReached = false
            context.beginPage()

            func drawWrapped(_ text: String, attributes: [NSAttributedString.Key: Any]) {
                if pageLimitReached { return }
                let wrapped = WorkoutReport.wrap(text, maxWidth: maxWidth) {
                    ($0 as NSString).size(withAttributes: attributes).width
                }
                for line in wrapped {
                    if y + lineHeight > bottom {
                        if pageNumber >= WorkoutReport.maxPages {
                            pageLimitReached = true
                            return
                        }
                        context.beginPage()
                        pageNumber += 1
                        y = top
                    }
                    (line as NSString).draw(at: CGPoint(x: marginX, y: y), withAttributes: attributes)
                    y += lineHeight
                }
            }

            for (index, line) in lines.enumerated() {
                if index == 0 {
                    drawWrapped(line, attributes: titleAttributes)
                    y += 8
                } else if line.hasPrefix("## ") {
                    y += 6
                    drawWrapped(String(line.dropFirst(3)), attributes: headingAttributes)
                    y += 2
                } else {
                    drawWrapped(line, attributes: bodyAttributes)
                }
            }
        }
        try (url as NSURL).setResourceValue(URLFileProtection.completeUnlessOpen, forKey: .fileProtectionKey)
        return url
    }

    private static func temporaryURL(name: String, extension fileExtension: String) -> URL {
        let cleanName = name
            .replacingOccurrences(of: #"[^A-Za-z0-9._-]"#, with: "-", options: .regularExpression)
            .prefix(80)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(cleanName)-\(stamp)")
            .appendingPathExtension(fileExtension)
    }
}
