import UIKit

@objc final class OverlayView: UIView {

    private var boxes: [[String: Any]] = []

    // Basic paint equivalents
    private let boxColor = UIColor.green
    private let textBackgroundColor = UIColor.black.withAlphaComponent(0.7)
    private let textColor = UIColor.white
    private let textFont = UIFont.systemFont(ofSize: 16, weight: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func updateDetections(_ detections: [[String: Any]]) {
        boxes = detections
        DispatchQueue.main.async {
            self.setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.clear(rect)

        for det in boxes {
            guard
                let rectStr = det["rect"] as? String,
                let label = det["label"] as? String,
                let score = det["score"] as? NSNumber
            else { continue }

            let normalized = NSCoder.cgRect(for: rectStr)
            let left   = normalized.origin.x * rect.width
            let top    = (1 - normalized.origin.y - normalized.height) * rect.height
            let width  = normalized.width * rect.width
            let height = normalized.height * rect.height

            let boxRect = CGRect(x: left, y: top, width: width, height: height)

            // Draw bounding box
            ctx.setStrokeColor(boxColor.cgColor)
            ctx.setLineWidth(3)
            ctx.stroke(boxRect)

            // Draw background behind text
            let text = String(format: "%@ %.0f%%", label, score.floatValue * 100)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: textColor
            ]
            let size = text.size(withAttributes: attrs)
            let textBg = CGRect(x: left,
                                y: max(top - size.height, 0),
                                width: size.width + 8,
                                height: size.height + 4)

            ctx.setFillColor(textBackgroundColor.cgColor)
            ctx.fill(textBg)

            // Draw text
            text.draw(in: textBg.insetBy(dx: 4, dy: 2), withAttributes: attrs)
        }
    }

    @objc func clear() {
        boxes.removeAll()
        DispatchQueue.main.async { self.setNeedsDisplay() }
    }
}
