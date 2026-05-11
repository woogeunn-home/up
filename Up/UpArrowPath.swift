import CoreGraphics

/// Up arrow glyph path, transcribed verbatim from the source SVG (viewBox 10×12).
/// Coordinates are in the SVG's coordinate space; consumers scale as needed.
enum UpArrowPath {
    static let viewBoxWidth: CGFloat = 10
    static let viewBoxHeight: CGFloat = 12

    static let path: CGPath = {
        let p = CGMutablePath()

        // Subpath 1: outer chevron + base
        p.move(to: CGPoint(x: 0.808594, y: 5.50195))
        p.addCurve(to: CGPoint(x: 0.228516, y: 5.27344),
                   control1: CGPoint(x: 0.578125, y: 5.50195),
                   control2: CGPoint(x: 0.384766, y: 5.42578))
        p.addCurve(to: CGPoint(x: 0, y: 4.68164),
                   control1: CGPoint(x: 0.0761719, y: 5.12109),
                   control2: CGPoint(x: 0, y: 4.92383))
        p.addCurve(to: CGPoint(x: 0.263672, y: 4.07227),
                   control1: CGPoint(x: 0, y: 4.45508),
                   control2: CGPoint(x: 0.0878906, y: 4.25195))
        p.addLine(to: CGPoint(x: 4.07812, y: 0.251953))
        p.addCurve(to: CGPoint(x: 4.35938, y: 0.0703125),
                   control1: CGPoint(x: 4.15625, y: 0.173828),
                   control2: CGPoint(x: 4.25, y: 0.113281))
        p.addCurve(to: CGPoint(x: 4.70508, y: 0),
                   control1: CGPoint(x: 4.47266, y: 0.0234375),
                   control2: CGPoint(x: 4.58789, y: 0))
        p.addCurve(to: CGPoint(x: 5.04492, y: 0.0703125),
                   control1: CGPoint(x: 4.81836, y: 0),
                   control2: CGPoint(x: 4.93164, y: 0.0234375))
        p.addCurve(to: CGPoint(x: 5.33203, y: 0.251953),
                   control1: CGPoint(x: 5.1582, y: 0.113281),
                   control2: CGPoint(x: 5.25391, y: 0.173828))
        p.addLine(to: CGPoint(x: 9.14648, y: 4.07227))
        p.addCurve(to: CGPoint(x: 9.41016, y: 4.68164),
                   control1: CGPoint(x: 9.32227, y: 4.25195),
                   control2: CGPoint(x: 9.41016, y: 4.45508))
        p.addCurve(to: CGPoint(x: 9.17578, y: 5.27344),
                   control1: CGPoint(x: 9.41016, y: 4.92383),
                   control2: CGPoint(x: 9.33203, y: 5.12109))
        p.addCurve(to: CGPoint(x: 8.60156, y: 5.50195),
                   control1: CGPoint(x: 9.02344, y: 5.42578),
                   control2: CGPoint(x: 8.83203, y: 5.50195))
        p.addCurve(to: CGPoint(x: 8.26172, y: 5.43164),
                   control1: CGPoint(x: 8.47656, y: 5.50195),
                   control2: CGPoint(x: 8.36328, y: 5.47852))
        p.addCurve(to: CGPoint(x: 7.99805, y: 5.23828),
                   control1: CGPoint(x: 8.16016, y: 5.38086),
                   control2: CGPoint(x: 8.07227, y: 5.31641))
        p.addLine(to: CGPoint(x: 6.67383, y: 3.92578))
        p.addLine(to: CGPoint(x: 4.69922, y: 1.62305))
        p.addLine(to: CGPoint(x: 2.73047, y: 3.92578))
        p.addLine(to: CGPoint(x: 1.41211, y: 5.23828))
        p.addCurve(to: CGPoint(x: 1.14258, y: 5.43164),
                   control1: CGPoint(x: 1.33398, y: 5.31641),
                   control2: CGPoint(x: 1.24414, y: 5.38086))
        p.addCurve(to: CGPoint(x: 0.808594, y: 5.50195),
                   control1: CGPoint(x: 1.04492, y: 5.47852),
                   control2: CGPoint(x: 0.933594, y: 5.50195))
        p.closeSubpath()

        // Subpath 2: vertical stem
        p.move(to: CGPoint(x: 4.70508, y: 11.2207))
        p.addCurve(to: CGPoint(x: 4.08984, y: 10.9746),
                   control1: CGPoint(x: 4.45117, y: 11.2207),
                   control2: CGPoint(x: 4.24609, y: 11.1387))
        p.addCurve(to: CGPoint(x: 3.85547, y: 10.3359),
                   control1: CGPoint(x: 3.93359, y: 10.8145),
                   control2: CGPoint(x: 3.85547, y: 10.6016))
        p.addLine(to: CGPoint(x: 3.85547, y: 3.83789))
        p.addLine(to: CGPoint(x: 3.94336, y: 1.63477))
        p.addCurve(to: CGPoint(x: 4.1543, y: 1.06641),
                   control1: CGPoint(x: 3.94336, y: 1.40039),
                   control2: CGPoint(x: 4.01367, y: 1.21094))
        p.addCurve(to: CGPoint(x: 4.70508, y: 0.849609),
                   control1: CGPoint(x: 4.29492, y: 0.921875),
                   control2: CGPoint(x: 4.47852, y: 0.849609))
        p.addCurve(to: CGPoint(x: 5.25, y: 1.06641),
                   control1: CGPoint(x: 4.92773, y: 0.849609),
                   control2: CGPoint(x: 5.10938, y: 0.921875))
        p.addCurve(to: CGPoint(x: 5.46094, y: 1.63477),
                   control1: CGPoint(x: 5.39062, y: 1.21094),
                   control2: CGPoint(x: 5.46094, y: 1.40039))
        p.addLine(to: CGPoint(x: 5.54883, y: 3.83789))
        p.addLine(to: CGPoint(x: 5.54883, y: 10.3359))
        p.addCurve(to: CGPoint(x: 5.31445, y: 10.9746),
                   control1: CGPoint(x: 5.54883, y: 10.6016),
                   control2: CGPoint(x: 5.4707, y: 10.8145))
        p.addCurve(to: CGPoint(x: 4.70508, y: 11.2207),
                   control1: CGPoint(x: 5.1582, y: 11.1387),
                   control2: CGPoint(x: 4.95508, y: 11.2207))
        p.closeSubpath()

        return p
    }()
}
