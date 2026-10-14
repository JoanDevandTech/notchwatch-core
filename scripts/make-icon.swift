// Dibuja el icono de la app (PNG 1024×1024) solo con CoreGraphics:
// una píldora negra con halo rojo (la isla) sobre una lista de incidencias.
// Uso: swift scripts/make-icon.swift build/icon-1024.png
import CoreGraphics
import Foundation
import ImageIO

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()

func rgba(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha]) ?? CGColor(gray: 0, alpha: 1)
}

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    exit(1)
}

// Fondo: baldosa redondeada (rejilla de iconos de macOS) con degradado azul → morado.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
context.saveGState()
context.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
context.clip()
if let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [rgba(0.12, 0.16, 0.33), rgba(0.38, 0.17, 0.46)] as CFArray,
    locations: [0, 1]
) {
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 100, y: 924),
        end: CGPoint(x: 924, y: 100),
        options: []
    )
}

// Lista de incidencias (tres filas con su barra de prioridad).
let priorityColors = [rgba(1, 0.32, 0.28), rgba(1, 0.6, 0.12), rgba(1, 0.84, 0.2)]
for index in 0..<3 {
    let y = 450 - CGFloat(index) * 105
    let row = CGRect(x: 232, y: y, width: 560, height: 78)
    context.addPath(CGPath(roundedRect: row, cornerWidth: 26, cornerHeight: 26, transform: nil))
    context.setFillColor(rgba(1, 1, 1, 0.13 - CGFloat(index) * 0.03))
    context.fillPath()
    context.setFillColor(priorityColors[index])
    context.addPath(CGPath(roundedRect: CGRect(x: 256, y: y + 19, width: 12, height: 40), cornerWidth: 6, cornerHeight: 6, transform: nil))
    context.fillPath()
    context.setFillColor(rgba(1, 1, 1, 0.55 - CGFloat(index) * 0.12))
    context.addPath(CGPath(roundedRect: CGRect(x: 292, y: y + 31, width: 300 - CGFloat(index) * 50, height: 16), cornerWidth: 8, cornerHeight: 8, transform: nil))
    context.fillPath()
}

// La isla: píldora negra con halo rojo.
let pill = CGRect(x: 232, y: 620, width: 560, height: 160)
let pillPath = CGPath(roundedRect: pill, cornerWidth: 80, cornerHeight: 80, transform: nil)
context.saveGState()
context.setShadow(offset: .zero, blur: 70, color: rgba(1, 0.3, 0.27, 0.95))
context.addPath(pillPath)
context.setFillColor(rgba(0, 0, 0))
context.fillPath()
context.restoreGState()
context.addPath(pillPath)
context.setStrokeColor(rgba(1, 0.34, 0.3))
context.setLineWidth(8)
context.strokePath()
// Punto de estado a la izquierda y "contador" a la derecha.
context.setFillColor(rgba(1, 0.34, 0.3))
context.fillEllipse(in: CGRect(x: 292, y: 665, width: 70, height: 70))
context.setFillColor(rgba(1, 1, 1, 0.92))
context.addPath(CGPath(roundedRect: CGRect(x: 662, y: 670, width: 60, height: 60), cornerWidth: 30, cornerHeight: 30, transform: nil))
context.fillPath()
context.restoreGState()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: output) as CFURL,
          "public.png" as CFString,
          1,
          nil
      )
else {
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
