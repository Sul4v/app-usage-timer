import UIKit

/// The shield screen's layout is fixed by Apple, but the `icon` slot takes any
/// UIImage — so we draw our own: a Capsule-branded progress ring in the state
/// color with today's minutes in the middle. This is what makes the reminder
/// feel like ours rather than a stock iOS sheet.
enum ShieldRing {
    static func image(minutes: Int, limit: Int, ratio: Double, color: UIColor) -> UIImage {
        let size = CGSize(width: 240, height: 240)
        let lineWidth: CGFloat = 18
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = (size.width - lineWidth) / 2 - 4
            let start = -CGFloat.pi / 2

            // Track
            let track = UIBezierPath(arcCenter: center, radius: radius,
                                     startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            track.lineWidth = lineWidth
            UIColor.white.withAlphaComponent(0.15).setStroke()
            track.stroke()

            // Progress arc (full circle once over the limit)
            let progress = CGFloat(min(max(ratio, 0.02), 1))
            let arc = UIBezierPath(arcCenter: center, radius: radius,
                                   startAngle: start, endAngle: start + 2 * .pi * progress,
                                   clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()

            // Center text: big minutes, small "of limit"
            let big = UsageMath.formatMinutes(minutes) as NSString
            let bigAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 52, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let bigSize = big.size(withAttributes: bigAttrs)

            let small = "of \(UsageMath.formatMinutes(limit))" as NSString
            let smallAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.6),
            ]
            let smallSize = small.size(withAttributes: smallAttrs)

            let totalH = bigSize.height + 2 + smallSize.height
            big.draw(at: CGPoint(x: center.x - bigSize.width / 2,
                                 y: center.y - totalH / 2),
                     withAttributes: bigAttrs)
            small.draw(at: CGPoint(x: center.x - smallSize.width / 2,
                                   y: center.y - totalH / 2 + bigSize.height + 2),
                       withAttributes: smallAttrs)
        }
    }
}
