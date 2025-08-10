import SwiftUI
import UIKit

struct DetectionOverlayView: View {
    let detectedObjects: [YOLODetection]
    let isPortrait: Bool
    let orientation: UIDeviceOrientation

    // Create a color palette that assigns unique colors to each detection
    private var objectColors: [String: Color] {
        var colors: [String: Color] = [:]
        let vibrantColors: [Color] = [
            Color(red: 1.0, green: 0.2, blue: 0.4),      // Hot Pink
            Color(red: 0.0, green: 0.9, blue: 1.0),      // Cyan
            Color(red: 0.5, green: 1.0, blue: 0.0),      // Lime Green
            Color(red: 1.0, green: 0.5, blue: 0.0),      // Orange
            Color(red: 0.8, green: 0.0, blue: 1.0),      // Purple
            Color(red: 1.0, green: 1.0, blue: 0.0),      // Yellow
            Color(red: 0.0, green: 0.5, blue: 1.0),      // Sky Blue
            Color(red: 1.0, green: 0.0, blue: 0.5),      // Magenta
            Color(red: 0.0, green: 1.0, blue: 0.5),      // Spring Green
            Color(red: 1.0, green: 0.7, blue: 0.0),      // Gold
            Color(red: 0.3, green: 0.0, blue: 1.0),      // Indigo
            Color(red: 0.0, green: 1.0, blue: 0.8),      // Turquoise
            Color(red: 1.0, green: 0.3, blue: 0.7),      // Pink
            Color(red: 0.5, green: 0.8, blue: 1.0),      // Light Blue
            Color(red: 0.8, green: 1.0, blue: 0.5),      // Light Green
            Color(red: 1.0, green: 0.6, blue: 0.4),      // Coral
            Color(red: 0.6, green: 0.4, blue: 1.0),      // Lavender
            Color(red: 0.3, green: 1.0, blue: 0.7),      // Mint
            Color(red: 1.0, green: 0.9, blue: 0.5),      // Pastel Yellow
            Color(red: 0.7, green: 0.5, blue: 0.8),      // Mauve
        ]

        // Sort objects by their ID to ensure consistent color assignment
        let sortedObjects = detectedObjects.sorted { $0.id.uuidString < $1.id.uuidString }

        for (index, object) in sortedObjects.enumerated() {
            let colorIndex = index % vibrantColors.count
            colors[object.id.uuidString] = vibrantColors[colorIndex]
        }

        return colors
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                let _ = cleanupHistories()
                // First layer: Draw all bounding boxes with unique colors
                ForEach(detectedObjects) { object in
                    let displayRect = calculateDisplayRect(
                        for: object.rect,
                        in: geometry.size,
                        orientation: orientation,
                        isPortrait: isPortrait
                    )

                    // Only show if not taking up more than 70% of screen
                    if displayRect.width < geometry.size.width * 0.7 &&
                       displayRect.height < geometry.size.height * 0.7 {

                        // Shaded region with lighter, more colorful overlay
                        RoundedRectangle(cornerRadius: 12)
                            .fill(objectColors[object.id.uuidString]?.opacity(0.15) ?? Color.blue.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(objectColors[object.id.uuidString]?.opacity(0.5) ?? Color.blue.opacity(0.5), lineWidth: 2)
                            )
                            .frame(width: displayRect.width, height: displayRect.height)
                            .position(x: displayRect.midX, y: displayRect.midY)
                            .allowsHitTesting(false)
                    }
                }

                // Second layer: Draw labels in a non-overlapping way with matching colors
                ForEach(arrangeLabels(objects: detectedObjects, in: geometry.size)) { labelPosition in
                    Text(labelPosition.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(objectColors[labelPosition.objectId]?.opacity(0.25) ?? Color.blue.opacity(0.25))
                        )
                        .shadow(color: .black, radius: 2, x: 1, y: 1)
                        .rotationEffect(getLabelRotation())
                        .position(x: labelPosition.x, y: labelPosition.y)
                        .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // Clean up LiDAR distance histories for stale detections
    private func cleanupHistories() {
        let currentIds = Set(detectedObjects.map { $0.id })
        LiDARManager.shared.cleanupOldHistories(currentDetectionIds: currentIds)
    }

    // Structure to hold label positions
    struct LabelPosition: Identifiable {
        let id = UUID()
        let label: String
        let className: String
        let objectId: String  // Added to track which object this label belongs to
        let x: CGFloat
        let y: CGFloat
    }

    // Arrange labels to prevent overlap
    private func arrangeLabels(objects: [YOLODetection], in size: CGSize) -> [LabelPosition] {
        var positions: [LabelPosition] = []
        var occupiedRects: [CGRect] = []

        // Sort by confidence so higher confidence labels get priority placement
        let sortedObjects = objects.sorted { $0.score > $1.score }

        for object in sortedObjects {
            let displayRect = calculateDisplayRect(
                for: object.rect,
                in: size,
                orientation: orientation,
                isPortrait: isPortrait
            )

            // Skip if too large
            if displayRect.width >= size.width * 0.7 ||
               displayRect.height >= size.height * 0.7 {
                continue
            }

            // Build label text (LiDAR-aware)
            let label = buildCompactLabel(for: object)

            let labelWidth: CGFloat = CGFloat(label.count * 8 + 20) // Approximate width
            let labelHeight: CGFloat = 25

            // Try to place label at different positions around the box
            let candidatePositions = [
                CGPoint(x: displayRect.midX, y: displayRect.midY), // Center
                CGPoint(x: displayRect.midX, y: displayRect.minY - 15), // Top
                CGPoint(x: displayRect.midX, y: displayRect.maxY + 15), // Bottom
                CGPoint(x: displayRect.minX - labelWidth/2 - 5, y: displayRect.midY), // Left
                CGPoint(x: displayRect.maxX + labelWidth/2 + 5, y: displayRect.midY), // Right
                CGPoint(x: displayRect.minX, y: displayRect.minY - 15), // Top-left
                CGPoint(x: displayRect.maxX, y: displayRect.minY - 15), // Top-right
                CGPoint(x: displayRect.minX, y: displayRect.maxY + 15), // Bottom-left
                CGPoint(x: displayRect.maxX, y: displayRect.maxY + 15), // Bottom-right
            ]

            var placed = false
            for position in candidatePositions {
                // Make sure position is within screen bounds
                let adjustedX = max(labelWidth/2, min(size.width - labelWidth/2, position.x))
                let adjustedY = max(labelHeight/2, min(size.height - labelHeight/2, position.y))

                let labelRect = CGRect(
                    x: adjustedX - labelWidth/2,
                    y: adjustedY - labelHeight/2,
                    width: labelWidth,
                    height: labelHeight
                )

                // Check if this position overlaps with any existing labels
                var overlaps = false
                for occupied in occupiedRects {
                    if labelRect.intersects(occupied) {
                        overlaps = true
                        break
                    }
                }

                if !overlaps {
                    positions.append(LabelPosition(
                        label: label,
                        className: object.className,
                        objectId: object.id.uuidString,
                        x: adjustedX,
                        y: adjustedY
                    ))
                    occupiedRects.append(labelRect)
                    placed = true
                    break
                }
            }

            // If we couldn't find a non-overlapping position, place it offset from center
            if !placed {
                let offsetIndex = positions.count
                let offsetX = CGFloat(offsetIndex % 3 - 1) * 100
                let offsetY = CGFloat(offsetIndex / 3) * 30

                let finalX = max(labelWidth/2, min(size.width - labelWidth/2, displayRect.midX + offsetX))
                let finalY = max(labelHeight/2, min(size.height - labelHeight/2, displayRect.midY + offsetY))

                positions.append(LabelPosition(
                    label: label,
                    className: object.className,
                    objectId: object.id.uuidString,
                    x: finalX,
                    y: finalY
                ))

                occupiedRects.append(CGRect(
                    x: finalX - labelWidth/2,
                    y: finalY - labelHeight/2,
                    width: labelWidth,
                    height: labelHeight
                ))
            }
        }

        return positions
    }

    // MARK: - LiDAR-aware label builder
    private func buildCompactLabel(for detection: YOLODetection) -> String {
        // Confidence as int percent
        let pct = max(0, min(100, Int((detection.score * 100).rounded())))
        let side: String = {
            let x = detection.rect.midX
            if x < 0.4 { return "L" }
            if x > 0.6 { return "R" }
            return "C"
        }()
        let area = detection.rect.width * detection.rect.height
        let center = CGPoint(x: detection.rect.midX, y: detection.rect.midY)

        var label: String
        if area >= 0.05 && area <= 0.30, LiDARManager.shared.isRunning, LiDARManager.shared.isSupported {
            if let feet = LiDARManager.shared.smoothedDistanceFeet(for: detection.id, at: center), feet >= 1, feet <= 15 {
                label = "\(detection.className.lowercased()) \(pct)% \(Int(round(Double(feet))))ft \(side)"
            } else {
                label = "\(detection.className.lowercased()) \(pct)% \(side)"
            }
        } else {
            label = "\(detection.className.lowercased()) \(pct)% \(side)"
        }
        return label
    }

    private func getLabelRotation() -> Angle {
        switch orientation {
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        default:
            return .degrees(0)
        }
    }

    // MARK: - RESTORED ORIGINAL WORKING LOGIC
    private func calculateDisplayRect(for normalizedRect: CGRect, in size: CGSize, orientation: UIDeviceOrientation, isPortrait: Bool) -> CGRect {
        // Use the EXACT logic from your working code
        if isPortrait {
            // Portrait mode - direct mapping
            return CGRect(
                x: normalizedRect.minX * size.width,
                y: normalizedRect.minY * size.height,
                width: normalizedRect.width * size.width,
                height: normalizedRect.height * size.height
            )
        } else {
            // Landscape mode - apply transformations based on orientation
            var transformedRect: CGRect
            
            switch orientation {
            case .landscapeLeft:
                // Device rotated counter-clockwise 90°
                transformedRect = CGRect(
                    x: (1.0 - normalizedRect.maxY) * size.width,
                    y: normalizedRect.minX * size.height,
                    width: normalizedRect.height * size.width,
                    height: normalizedRect.width * size.height
                )
                
            case .landscapeRight:
                // Device rotated clockwise 90°
                transformedRect = CGRect(
                    x: normalizedRect.minY * size.width,
                    y: (1.0 - normalizedRect.maxX) * size.height,
                    width: normalizedRect.height * size.width,
                    height: normalizedRect.width * size.height
                )
                
            default:
                // Fallback to direct mapping
                transformedRect = CGRect(
                    x: normalizedRect.minX * size.width,
                    y: normalizedRect.minY * size.height,
                    width: normalizedRect.width * size.width,
                    height: normalizedRect.height * size.height
                )
            }
            
            return transformedRect
        }
    }
}
