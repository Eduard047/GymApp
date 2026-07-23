#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repositoryRoot = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let sourceURL = repositoryRoot.appendingPathComponent("branding/app-icon-master.png")
let defaultOutputURL = repositoryRoot.appendingPathComponent(
    "ios/GymApp-iOS/GymApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
)
let outputURL = CommandLine.arguments.dropFirst().first.map {
    URL(fileURLWithPath: $0).standardizedFileURL
} ?? defaultOutputURL

guard
    let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
    let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fatalError("Could not load master icon at \(sourceURL.path)")
}

let width = 1024
let height = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else { fatalError("Could not create icon bitmap") }

let rect = CGRect(x: 0, y: 0, width: width, height: height)
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(rect)
context.interpolationQuality = .high
context.draw(sourceImage, in: rect)

guard let image = context.makeImage() else { fatalError("Could not render icon") }
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("Could not create PNG destination")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
print(outputURL.path)
