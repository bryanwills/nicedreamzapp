import AVFoundation
import SwiftUI

// MARK: - Basic UI Components

struct ShadedEmoji: View {
    let emoji: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: size * 1.35, height: size * 1.35)
                .shadow(color: Color.black.opacity(0.09), radius: 3, x: 0, y: 2)
            Text(emoji)
                .font(.system(size: size))
        }
    }
}

struct OutlinedText: View {
    let text: String
    let fontSize: CGFloat
    let strokeWidth: CGFloat
    let strokeColor: Color
    let fillColor: Color

    init(
        text: String,
        fontSize: CGFloat,
        strokeWidth: CGFloat = 1.1,
        strokeColor: Color = .black,
        fillColor: Color = .white
    ) {
        self.text = text
        self.fontSize = fontSize
        self.strokeWidth = strokeWidth
        self.strokeColor = strokeColor
        self.fillColor = fillColor
    }

    var body: some View {
        ZStack {
            Text(text)
                .font(.system(size: fontSize, weight: .bold, design: .default))
                .foregroundColor(strokeColor)
                .offset(x: -strokeWidth, y: -strokeWidth)
            Text(text)
                .font(.system(size: fontSize, weight: .bold, design: .default))
                .foregroundColor(strokeColor)
                .offset(x: strokeWidth, y: -strokeWidth)
            Text(text)
                .font(.system(size: fontSize, weight: .bold, design: .default))
                .foregroundColor(strokeColor)
                .offset(x: -strokeWidth, y: strokeWidth)
            Text(text)
                .font(.system(size: fontSize, weight: .bold, design: .default))
                .foregroundColor(strokeColor)
                .offset(x: strokeWidth, y: strokeWidth)

            Text(text)
                .font(.system(size: fontSize, weight: .bold, design: .default))
                .foregroundColor(fillColor)
        }
    }
}

// MARK: - Button Styles

enum ButtonStyles {
    @ViewBuilder
    static func glassBackground() -> some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.25))
                .background(Color.clear)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .blendMode(.screen)
                .opacity(0.7)

            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .shadow(color: Color.white.opacity(0.2), radius: 8, x: -2, y: -2)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 2, y: 2)
                .blur(radius: 2)

            Capsule()
                .stroke(Color.black.opacity(0.30), lineWidth: 2)
                .blur(radius: 2)
                .offset(x: 1, y: 1)
                .mask(Capsule().fill(LinearGradient(colors: [Color.black, Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
    }
}

// MARK: - Heading View

struct HeadingView: View {
    let animateIn: Bool

    var body: some View {
        GeometryReader { geometry in
            let scaleFactor = min(geometry.size.width / 390, 1.0)
            let titleSize: CGFloat = 52 * scaleFactor
            let subtitleSize: CGFloat = 44 * scaleFactor
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .overlay(Capsule().stroke(Color.black, lineWidth: 1.1))
                    .shadow(color: Color.blue.opacity(0.10), radius: 10 * scaleFactor)
                VStack(spacing: -8 * scaleFactor) {
                    OutlinedText(
                        text: "RealTime",
                        fontSize: titleSize,
                        strokeWidth: 2.1,
                        strokeColor: .black,
                        fillColor: Color(red: 0.64, green: 0.85, blue: 1.0)
                    )
                    OutlinedText(
                        text: "Ai Camera",
                        fontSize: subtitleSize,
                        strokeWidth: 2.1,
                        strokeColor: .black,
                        fillColor: Color(red: 0.81, green: 0.93, blue: 1.0)
                    )
                }
                .padding(.horizontal, 25 * scaleFactor)
                .padding(.vertical, 14 * scaleFactor)
            }
            .frame(width: geometry.size.width * 0.92, height: 120)
            .position(x: geometry.size.width / 2, y: 60)
            .opacity(animateIn ? 1 : 0)
            .scaleEffect(animateIn ? 1 : 0.88)
            .animation(.interpolatingSpring(stiffness: 200, damping: 14).delay(animateIn ? 0.05 : 0), value: animateIn)
        }
        .frame(height: 120)
    }
}

// MARK: - Voice Picker

struct AnimatedVoicePicker: View {
    @ObservedObject var viewModel: CameraViewModel
    let animateIn: Bool
    let onVoiceChange: () -> Void
    let speechSynthesizer: AVSpeechSynthesizer
    @State private var showVoiceGrid = false

    private func isPremiumPlus(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let name = voice.name.lowercased()
        return name.contains("premium") || name.contains("plus") || name.contains("ava")
    }

    private var premiumEnglishVoices: [AVSpeechSynthesisVoice] {
        let allVoices = AVSpeechSynthesisVoice.speechVoices().filter { v in
            v.language.hasPrefix("en") && !v.name.lowercased().contains("robot") && !v.name.lowercased().contains("whisper") && !v.name.lowercased().contains("grandma")
        }
        let favoriteNames = ["Ava", "Samantha", "Daniel", "Karen", "Moira", "Serena", "Martha", "Aaron", "Fred", "Tessa", "Fiona", "Allison", "Nicky", "Joelle", "Oliver"]
        let premiumPlus = allVoices.filter { isPremiumPlus($0) }
        let enhanced = allVoices.filter { $0.quality == .enhanced && !isPremiumPlus($0) }
        let regular = allVoices.filter { $0.quality != .enhanced && !isPremiumPlus($0) }
        let sortedPremiumPlus = premiumPlus.sorted { lhs, rhs in
            let f1 = favoriteNames.firstIndex(of: lhs.name) ?? Int.max
            let f2 = favoriteNames.firstIndex(of: rhs.name) ?? Int.max
            return f1 < f2
        }
        let sortedEnhanced = enhanced.sorted { lhs, rhs in
            let f1 = favoriteNames.firstIndex(of: lhs.name) ?? Int.max
            let f2 = favoriteNames.firstIndex(of: rhs.name) ?? Int.max
            return f1 < f2
        }
        let sortedRegular = regular.sorted { lhs, rhs in
            let f1 = favoriteNames.firstIndex(of: lhs.name) ?? Int.max
            let f2 = favoriteNames.firstIndex(of: rhs.name) ?? Int.max
            return f1 < f2
        }
        var result = [AVSpeechSynthesisVoice]()
        result.append(contentsOf: sortedPremiumPlus)
        if result.count < 10 { result.append(contentsOf: sortedEnhanced.prefix(10 - result.count)) }
        if result.count < 10 { result.append(contentsOf: sortedRegular.prefix(10 - result.count)) }
        if let ava = allVoices.first(where: { $0.name == "Ava" && $0.language.hasPrefix("en") }), !result.contains(where: { $0.identifier == ava.identifier }) {
            result.insert(ava, at: 0)
        }
        return Array(result.prefix(10))
    }

    private func genderEmoji(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.gender {
        case .female: "👩"
        case .male: "👨"
        default: "🧑"
        }
    }

    private func qualityTag(for voice: AVSpeechSynthesisVoice) -> String {
        if isPremiumPlus(voice) {
            return "(Premium)"
        }
        if voice.quality == .enhanced {
            return "(Enhanced)"
        }
        return ""
    }

    private var selectedVoice: AVSpeechSynthesisVoice? {
        premiumEnglishVoices.first(where: { $0.identifier == viewModel.selectedVoiceIdentifier })
    }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3)) {
                showVoiceGrid.toggle()
            }
        }) {
            let voice = selectedVoice
            let defaultVoice = premiumEnglishVoices.first ?? AVSpeechSynthesisVoice(language: "en-US")!
            HStack(spacing: 6) {
                Text(genderEmoji(for: voice ?? defaultVoice))
                    .font(.system(size: 28))
                Text(voice?.name ?? "Select Voice")
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundColor(.white)
                if let v = voice {
                    let tag = qualityTag(for: v)
                    if !tag.isEmpty {
                        Text(tag)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                Image(systemName: showVoiceGrid ? "chevron.down" : "chevron.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.purple.opacity(0.24)))
            .overlay(Capsule().stroke(Color.black, lineWidth: 1.1))
        }
        .opacity(animateIn ? 1 : 0)
        .scaleEffect(animateIn ? 1 : 0.7)
        .animation(.easeOut(duration: 0.3), value: animateIn)
        .overlay(
            Group {
                if showVoiceGrid {
                    Color.clear
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25)) {
                                showVoiceGrid = false
                            }
                        }
                        .offset(y: -400)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(premiumEnglishVoices, id: \.identifier) { voice in
                            Button(action: {
                                viewModel.selectedVoiceIdentifier = voice.identifier
                                onVoiceChange()
                                withAnimation(.spring(response: 0.25)) {
                                    showVoiceGrid = false
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Text(genderEmoji(for: voice))
                                        .font(.system(size: 20))
                                    Text(voice.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white)
                                    Text(qualityTag(for: voice))
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(voice.identifier == viewModel.selectedVoiceIdentifier ?
                                            Color.purple.opacity(0.5) :
                                            Color.black.opacity(0.6))
                                )
                            }
                        }
                    }
                    .padding(8)
                    .frame(width: 280)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.85))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                            )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 10)
                    .offset(y: -200)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        )
        .accessibilityLabel("Voice Selection")
        .accessibilityHint("Choose your preferred voice for speech feedback")
    }
}
