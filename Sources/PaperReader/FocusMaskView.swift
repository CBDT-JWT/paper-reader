import AppKit
import QuartzCore

/// A single Gaussian penumbra texture is stretched around the aperture. Reusing one
/// texture keeps the corners continuous and avoids separate corner-layer artifacts.
@MainActor final class FocusMaskView: NSView {
    var holes: [CGRect] = []
    var opacity = 0.48
    var feather: CGFloat = 12
    var holeVisibility = 1.0
    let maskLayer = CAShapeLayer()
    private let apertureFill = CALayer()
    private let penumbra = CALayer()
    private var textureRadius: CGFloat = -1
    private var textureScale: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(maskLayer)
        layer?.addSublayer(apertureFill)
        layer?.addSublayer(penumbra)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() { super.layout(); renderMask() }

    func renderMask() {
        let rectangle = holes.reduce(CGRect.null) { $0.union($1) }
        let radius = min(40, max(1, feather))
        let scale = window?.backingScaleFactor ?? 2
        // Overlap the opaque texture edge by at least two device pixels. Antialiased
        // layers otherwise leave a lighter hairline when their fractional edges meet.
        let overlap = max(1, 2 / scale)
        let opening = rectangle.insetBy(dx: overlap, dy: overlap)
        let path = CGMutablePath()
        path.addRect(bounds)
        let intersection = opening.intersection(bounds)
        if !rectangle.isNull, !intersection.isNull { path.addRect(intersection) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = Float(min(1, max(0, opacity)))
        maskLayer.frame = bounds
        maskLayer.contentsScale = scale
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = NSColor.black.cgColor
        maskLayer.path = path
        apertureFill.isHidden = rectangle.isNull
        apertureFill.frame = rectangle.isNull ? .zero : rectangle
        apertureFill.backgroundColor = NSColor.black.withAlphaComponent(1 - min(1, max(0, holeVisibility))).cgColor
        penumbra.isHidden = rectangle.isNull
        penumbra.frame = rectangle.isNull ? .zero : rectangle
        updateTexture(radius: radius, scale: scale)
        CATransaction.commit()
    }

    private func updateTexture(radius: CGFloat, scale: CGFloat) {
        guard radius != textureRadius || scale != textureScale else { return }
        let band = max(2, Int(ceil(radius * scale)))
        let size = band * 2 + 2
        let tail = (1 + erf(-3 / sqrt(2))) / 2
        func coverage(_ coordinate: Int) -> Double {
            let distance = Double(min(coordinate, size - 1 - coordinate))
            let fraction = min(1, distance / Double(band))
            let gaussian = (1 + erf((fraction - 0.5) * 6 / sqrt(2))) / 2
            return min(1, max(0, (gaussian - tail) / (1 - 2 * tail)))
        }
        let values = (0..<size).map(coverage)
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                // Integral of a Gaussian over a rectangle, including its rounded penumbra.
                // RGB stays black even at zero alpha, preventing white fringes when scaled.
                let alpha = 1 - values[x] * values[y]
                pixels[(y * size + x) * 4 + 3] = UInt8((min(1, max(0, alpha)) * 255).rounded())
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
        penumbra.contents = image
        penumbra.contentsScale = scale
        penumbra.contentsCenter = CGRect(x: Double(band) / Double(size), y: Double(band) / Double(size),
                                         width: 2 / Double(size), height: 2 / Double(size))
        textureRadius = radius
        textureScale = scale
    }
}
