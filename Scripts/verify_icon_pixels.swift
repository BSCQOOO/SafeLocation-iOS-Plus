import AppKit
import Foundation
import ImageIO

func decode(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Cannot decode icon: \(path)")
    }
    return image
}

func pixels(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    }
    return bytes
}

let source = decode(CommandLine.arguments[1])
let packaged = decode(CommandLine.arguments[2])
let expected = pixels(source, width: packaged.width, height: packaged.height)
let actual = pixels(packaged, width: packaged.width, height: packaged.height)
var total = 0.0
for index in expected.indices where index % 4 != 3 {
    total += abs(Double(expected[index]) - Double(actual[index])) / 255
}
let error = total / Double(packaged.width * packaged.height * 3)
precondition(error < 0.035, "Packaged AppIcon differs from current source: MAE=\(error)")
print("Packaged AppIcon pixels match source; RGB mean absolute error=\(error)")
