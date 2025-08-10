import SwiftUI

struct PerformanceOverlayView: View {
    let fps: Double
    let objectCount: Int
    let isPortrait: Bool

    var body: some View {
        HStack(spacing: 28) {
            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .font(.system(size: 18, weight: .medium))
                Text(String(format: "%.0f FPS", fps))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65))
            .cornerRadius(8)

            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.person.crop")
                    .font(.system(size: 18, weight: .medium))
                Text("Objects: \(objectCount)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.55))
            .cornerRadius(8)
        }
        .padding(.horizontal, isPortrait ? 20 : 40)
        .padding(.vertical, isPortrait ? 18 : 10)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isPortrait)
    }
}

#Preview {
    ZStack {
        Color(.darkGray).ignoresSafeArea()
        VStack {
            PerformanceOverlayView(fps: 27.6, objectCount: 6, isPortrait: true)
            Spacer()
        }
    }
}
