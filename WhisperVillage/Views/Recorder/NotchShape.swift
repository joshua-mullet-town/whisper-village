import SwiftUI

struct NotchShape: Shape {
    var topCornerRadius: CGFloat {
        if bottomCornerRadius > 15 {
            bottomCornerRadius - 5
        } else {
            8
        }
    }
    
    var bottomCornerRadius: CGFloat
    
    init(cornerRadius: CGFloat? = nil) {
        if cornerRadius == nil {
            self.bottomCornerRadius = 10
        } else {
            self.bottomCornerRadius = cornerRadius!
        }
    }
    
    var animatableData: CGFloat {
        get { bottomCornerRadius }
        set { bottomCornerRadius = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at top edge, after the left concave corner
        path.move(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY))

        // Top edge (narrower than body due to concave corners)
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY))

        // Top-right corner - standard convex rounded corner
        path.addArc(
            center: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius),
            radius: topCornerRadius,
            startAngle: .degrees(270),  // pointing up (from top edge)
            endAngle: .degrees(0),      // pointing right (to right edge)
            clockwise: false
        )

        // Right edge (at full width) going down
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomCornerRadius))

        // Bottom-right corner (convex/rounded as before)
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomCornerRadius, y: rect.maxY - bottomCornerRadius),
            radius: bottomCornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + bottomCornerRadius, y: rect.maxY))

        // Bottom-left corner (convex/rounded as before)
        path.addArc(
            center: CGPoint(x: rect.minX + bottomCornerRadius, y: rect.maxY - bottomCornerRadius),
            radius: bottomCornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left edge (at full width) going up
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topCornerRadius))

        // Top-left corner - standard convex rounded corner
        path.addArc(
            center: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            radius: topCornerRadius,
            startAngle: .degrees(180),  // pointing left (from left edge)
            endAngle: .degrees(270),    // pointing up (to top edge)
            clockwise: false
        )

        return path
    }
} 