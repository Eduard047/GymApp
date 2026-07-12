#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.dropFirst().first
    ?? "GymApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
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

context.translateBy(x: 0, y: CGFloat(height))
context.scaleBy(x: 1, y: -1)
let rect = CGRect(x: 0, y: 0, width: width, height: height)
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [CGColor(red: 20/255, green: 40/255, blue: 60/255, alpha: 1),
             CGColor(red: 45/255, green: 91/255, blue: 132/255, alpha: 1)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])

context.setFillColor(CGColor(gray: 1, alpha: 0.20))
context.fillEllipse(in: CGRect(x: 530, y: -10, width: 540, height: 540))
context.setFillColor(CGColor(gray: 1, alpha: 0.12))
context.fillEllipse(in: CGRect(x: -210, y: 625, width: 470, height: 470))

let scale = CGFloat(width) / 108
func scaled(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
}

context.setFillColor(CGColor(gray: 0, alpha: 0.13))
[
    scaled(18, 39, 8, 32), scaled(28, 43, 6, 24), scaled(38, 49, 32, 12),
    scaled(74, 43, 6, 24), scaled(82, 39, 8, 32)
].forEach(context.fill)

context.setFillColor(CGColor(red: 245/255, green: 247/255, blue: 1, alpha: 1))
[scaled(20, 37, 8, 34), scaled(80, 37, 8, 34)].forEach(context.fill)
context.setFillColor(CGColor(red: 231/255, green: 236/255, blue: 1, alpha: 1))
[scaled(30, 41, 7, 26), scaled(71, 41, 7, 26)].forEach(context.fill)
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(scaled(38, 47, 32, 14))
context.setFillColor(CGColor(red: 123/255, green: 143/255, blue: 170/255, alpha: 1))
[scaled(47, 49, 2, 10), scaled(53, 49, 2, 10), scaled(59, 49, 2, 10)].forEach(context.fill)

guard let image = context.makeImage() else { fatalError("Could not render icon") }
let url = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create PNG destination")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
print(url.path)
