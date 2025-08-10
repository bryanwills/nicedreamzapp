import SwiftUI

struct PerformanceOverlayView: View {
    let fps: Double // kept for signature compatibility
    let objectCount: Int
    let isPortrait: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.stack.person.crop")
                .font(.system(size: 14, weight: .medium))
            Text("Objects: \(objectCount)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.55))
        .cornerRadius(6)
        .padding(.horizontal, isPortrait ? 16 : 24)
        .padding(.vertical, isPortrait ? 12 : 6)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isPortrait)
    }
}
