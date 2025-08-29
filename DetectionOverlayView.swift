import SwiftUI
import UIKit

struct DetectionOverlayView: View {
    let detectedObjects: [YOLODetection]
    let isPortrait: Bool
    let orientation: UIDeviceOrientation

    // Create a color palette for unique object colors
    private var objectColors: [String: Color] {
        var colors: [String: Color] = [:]
        let vibrantColors: [Color] = [
            Color(red: 1.0, green: 0.2, blue: 0.4), // Hot Pink
            Color(red: 0.0, green: 0.9, blue: 1.0), // Cyan
            Color(red: 0.5, green: 1.0, blue: 0.0), // Lime Green
            Color(red: 1.0, green: 0.5, blue: 0.0), // Orange
            Color(red: 0.8, green: 0.0, blue: 1.0), // Purple
            Color(red: 1.0, green: 1.0, blue: 0.0), // Yellow
            Color(red: 0.0, green: 0.5, blue: 1.0), // Sky Blue
            Color(red: 1.0, green: 0.0, blue: 0.5), // Magenta
            Color(red: 0.0, green: 1.0, blue: 0.5), // Spring Green
            Color(red: 1.0, green: 0.7, blue: 0.0), // Gold
        ]

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
                // Clean up LiDAR histories if LiDAR is active
                let _ = cleanupHistoriesIfNeeded()

                // Draw all bounding boxes
                ForEach(detectedObjects) { object in
                    let displayRect = calculateDisplayRect(
                        for: object.rect,
                        in: geometry.size,
                        orientation: orientation,
                        isPortrait: isPortrait
                    )

                    // Draw bounding box
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

                // Draw labels
                ForEach(arrangeLabels(objects: detectedObjects, in: geometry.size)) { labelPosition in
                    Text(labelPosition.label)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(objectColors[labelPosition.objectId]?.opacity(0.25) ?? Color.blue.opacity(0.25))
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
                        .rotationEffect(getLabelRotation())
                        .position(x: labelPosition.x, y: labelPosition.y)
                        .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // Only cleanup if LiDAR is actually running
    private func cleanupHistoriesIfNeeded() {
        if LiDARManager.shared.isRunning {
            let currentIds = Set(detectedObjects.map(\.id))
            LiDARManager.shared.cleanupOldHistories(currentDetectionIds: currentIds)
        }
    }

    struct LabelPosition: Identifiable {
        let id = UUID()
        let label: String
        let className: String
        let objectId: String
        let x: CGFloat
        let y: CGFloat
    }

    private func arrangeLabels(objects: [YOLODetection], in size: CGSize) -> [LabelPosition] {
        var positions: [LabelPosition] = []
        var occupiedRects: [CGRect] = []

        // Sort by confidence for priority placement
        let sortedObjects = objects.sorted { $0.score > $1.score }

        for object in sortedObjects {
            let displayRect = calculateDisplayRect(
                for: object.rect,
                in: size,
                orientation: orientation,
                isPortrait: isPortrait
            )

            // Build enhanced label with LiDAR position info
            let label = buildEnhancedLabel(for: object)

            let labelWidth = CGFloat(label.count * 9 + 24)
            let labelHeight: CGFloat = 28

            // Try different positions for the label
            let candidatePositions = [
                CGPoint(x: displayRect.midX, y: displayRect.minY - 20), // Top center
                CGPoint(x: displayRect.midX, y: displayRect.maxY + 20), // Bottom center
                CGPoint(x: displayRect.midX, y: displayRect.midY), // Center
                CGPoint(x: displayRect.minX + labelWidth / 2, y: displayRect.minY - 20), // Top left
                CGPoint(x: displayRect.maxX - labelWidth / 2, y: displayRect.minY - 20), // Top right
            ]

            var placed = false
            for position in candidatePositions {
                let adjustedX = max(labelWidth / 2, min(size.width - labelWidth / 2, position.x))
                let adjustedY = max(labelHeight / 2, min(size.height - labelHeight / 2, position.y))

                let labelRect = CGRect(
                    x: adjustedX - labelWidth / 2,
                    y: adjustedY - labelHeight / 2,
                    width: labelWidth,
                    height: labelHeight
                )

                // Check overlap with existing labels
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

            // If no good position found, place it offset from center
            if !placed {
                let offsetIndex = positions.count
                let offsetX = CGFloat(offsetIndex % 3 - 1) * 100
                let offsetY = CGFloat(offsetIndex / 3) * 35

                let finalX = max(labelWidth / 2, min(size.width - labelWidth / 2, displayRect.midX + offsetX))
                let finalY = max(labelHeight / 2, min(size.height - labelHeight / 2, displayRect.midY + offsetY))

                positions.append(LabelPosition(
                    label: label,
                    className: object.className,
                    objectId: object.id.uuidString,
                    x: finalX,
                    y: finalY
                ))
            }
        }

        return positions
    }

    // UPDATED: Enhanced label with position info when LiDAR is active
    private func buildEnhancedLabel(for detection: YOLODetection) -> String {
        let confidence = Int((detection.score * 100).rounded())
        var label = "\(detection.className.lowercased()) \(confidence)%"

        // Add LiDAR info only when enabled and running
        if LiDARManager.shared.isEnabled, LiDARManager.shared.isRunning {
            let center = CGPoint(x: detection.rect.midX, y: detection.rect.midY)

            // Try to get distance reading
            if let feet = LiDARManager.shared.distanceFeet(at: center),
               feet >= 1, feet <= 20
            {
                // Get position (L/R/C) based on center point
                let position = LiDARManager.horizontalBucket(forNormalizedX: center.x)

                // Format: "bottle 85% 3ft L" (distance first, then position)
                label += " \(feet)ft \(position)"
            }
        }

        return label
    }

    private func getLabelRotation() -> Angle {
        switch orientation {
        case .landscapeLeft:
            .degrees(90)
        case .landscapeRight:
            .degrees(-90)
        default:
            .degrees(0)
        }
    }

    // SIMPLIFIED COORDINATE CALCULATION
    private func calculateDisplayRect(for normalizedRect: CGRect, in size: CGSize, orientation: UIDeviceOrientation, isPortrait: Bool) -> CGRect {
        if isPortrait {
            // Portrait mode - direct mapping
            return CGRect(
                x: normalizedRect.minX * size.width,
                y: normalizedRect.minY * size.height,
                width: normalizedRect.width * size.width,
                height: normalizedRect.height * size.height
            )
        } else {
            // Landscape mode - apply transformations
            let transformedRect = switch orientation {
            case .landscapeLeft:
                CGRect(
                    x: (1.0 - normalizedRect.maxY) * size.width,
                    y: normalizedRect.minX * size.height,
                    width: normalizedRect.height * size.width,
                    height: normalizedRect.width * size.height
                )

            case .landscapeRight:
                CGRect(
                    x: normalizedRect.minY * size.width,
                    y: (1.0 - normalizedRect.maxX) * size.height,
                    width: normalizedRect.height * size.width,
                    height: normalizedRect.width * size.height
                )

            default:
                CGRect(
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
