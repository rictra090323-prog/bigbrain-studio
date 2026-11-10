import AppKit

let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let bitmap = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                       space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}
let background = CGPath(roundedRect: CGRect(x: 78, y: 78, width: 868, height: 868),
                        cornerWidth: 205, cornerHeight: 205, transform: nil)
bitmap.saveGState()
bitmap.addPath(background)
bitmap.clip()
let colors = [color(0.10, 0.12, 0.20), color(0.24, 0.25, 0.41)] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
bitmap.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 150), end: CGPoint(x: 910, y: 910),
                          options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
bitmap.setStrokeColor(color(0.72, 0.76, 0.98, 0.28))
bitmap.setLineWidth(4)
for radius in [190.0, 286.0, 361.0] {
    bitmap.strokeEllipse(in: CGRect(x: 512 - radius, y: 512 - radius, width: radius * 2, height: radius * 2))
}
let lime = color(0.82, 0.99, 0.50)
let spark = CGMutablePath()
spark.move(to: CGPoint(x: 548, y: 806))
spark.addQuadCurve(to: CGPoint(x: 760, y: 485), control: CGPoint(x: 545, y: 548))
spark.addQuadCurve(to: CGPoint(x: 471, y: 236), control: CGPoint(x: 513, y: 501))
spark.addQuadCurve(to: CGPoint(x: 263, y: 542), control: CGPoint(x: 476, y: 490))
spark.addQuadCurve(to: CGPoint(x: 548, y: 806), control: CGPoint(x: 510, y: 532))
spark.closeSubpath()
bitmap.addPath(spark)
bitmap.setFillColor(lime)
bitmap.fillPath()
bitmap.fillEllipse(in: CGRect(x: 745, y: 718, width: 24, height: 24))
bitmap.restoreGState()
let png = NSBitmapImageRep(cgImage: bitmap.makeImage()!).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
