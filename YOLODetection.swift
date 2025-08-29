import CoreGraphics
import Foundation

struct YOLODetection: Identifiable, Equatable {
    let id = UUID()
    let classIndex: Int
    let className: String
    let score: Float
    let rect: CGRect

    static func == (lhs: YOLODetection, rhs: YOLODetection) -> Bool {
        lhs.classIndex == rhs.classIndex &&
            lhs.className == rhs.className &&
            lhs.score == rhs.score &&
            lhs.rect == rhs.rect
    }
}
