import SwiftUI
import AVFoundation

struct MemoryMonitor {
    static func currentMemoryUsage() -> Float {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return Float(info.resident_size) / 1024.0 / 1024.0
    }
}

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

//

@MainActor
struct ContentView: View {
    enum Mode: String, RawRepresentable {
        case home = "home"
        case englishOCR = "englishOCR"
        case spanishToEnglishOCR = "spanishToEnglishOCR"
        case objectDetection = "objectDetection"
    }

    @SceneStorage("appMode") private var storedMode: Mode = .home
    @State private var mode: Mode = .home
    @StateObject private var viewModel = CameraViewModel()
    @State private var orientation = UIDevice.current.orientation
    
    private var normalizedOrientation: UIDeviceOrientation {
        switch orientation {
        case .portraitUpsideDown: return .portrait
        case .landscapeRight: return .landscapeLeft
        default: return orientation
        }
    }
    
    @State private var showSettings = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @StateObject private var ocrViewModel = LiveOCRViewModel()
    
    // Consolidated animation state
    @State private var animationState = AnimationState()
    
    @State private var memoryUsageMB: Float = MemoryMonitor.currentMemoryUsage()
    
    @Environment(\.scenePhase) private var scenePhase
    
    private var isPortrait: Bool {
        normalizedOrientation == .portrait || !normalizedOrientation.isValidInterfaceOrientation
    }

    private var rotationAngle: Angle {
        switch normalizedOrientation {
        case .landscapeLeft: return .degrees(90)
        default: return .degrees(0)
        }
    }
    
    // Animation state struct for cleaner state management
    struct AnimationState {
        var splash = false
        var heading = false
        var button1 = false
        var button2 = false
        var button3 = false
        var picker = false
        var hasAnimatedOnce = false
        
        mutating func reset() {
            splash = false
            heading = false
            button1 = false
            button2 = false
            button3 = false
            picker = false
        }
        
        mutating func showAll() {
            heading = true
            button1 = true
            button2 = true
            button3 = true
            picker = true
        }
    }
    
    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Text(String(format: "Memory: %.0f MB", memoryUsageMB))
                        .font(.caption.bold())
                        .padding(6)
                        .background(Color.black.opacity(0.16))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                    Spacer()
                }
                Spacer()
            }
            .padding([.top, .leading], 12)
            
            contentForMode
            
            // Settings overlay for OCR mode
            if showSettings && (mode == .englishOCR || mode == .spanishToEnglishOCR) {
                SettingsOverlayView(viewModel: viewModel, isPresented: $showSettings, mode: mode)
                // Immediately stop all processing when settings overlay appears
                .onAppear {
                    ocrViewModel.stopSession()
                }
                // Resume OCR processing only if still in OCR mode
                .onDisappear {
                    if mode == .englishOCR || mode == .spanishToEnglishOCR {
                        ocrViewModel.startSession()
                    }
                }
            }
        }
        .onAppear {
            // Only restore if it was home
            if storedMode == .home {
                mode = storedMode
            } else {
                mode = .home  // Always start at home
            }
            setupOrientationObserver()
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    memoryUsageMB = MemoryMonitor.currentMemoryUsage()
                }
            }
        }
        .onChange(of: scenePhase) { newValue in  // iOS 15 compatible version
            handleScenePhaseChange(newValue)
            storedMode = mode
        }
    }
    
    // Simplified content switching
    @ViewBuilder
    private var contentForMode: some View {
        switch mode {
        case .home:
            homeView
            
        case .englishOCR:
            ocrView(mode: .english)
            
        case .spanishToEnglishOCR:
            ocrView(mode: .spanishToEnglish)
            
        case .objectDetection:
            ObjectDetectionView(
                viewModel: viewModel,
                mode: $mode,
                showSettings: $showSettings,
                orientation: normalizedOrientation,
                isPortrait: isPortrait,
                rotationAngle: rotationAngle,
                onBack: switchToHome
            )
            .ignoresSafeArea()
            .onAppear {
                viewModel.reinitialize()
                viewModel.startSession()
            }
            .onDisappear {
                cleanupCurrentMode()
            }
        }
    }
    
    private var homeView: some View {
        HomeScreenView(
            viewModel: viewModel,
            animationState: $animationState,
            mode: $mode,
            onEnglishOCR: { switchToMode(.englishOCR) },
            onSpanishOCR: { switchToMode(.spanishToEnglishOCR) },
            onObjectDetection: {
                cleanupCurrentMode()
                mode = .objectDetection
                viewModel.startSession()
            },
            onVoiceChange: playWelcomeMessage,
            speechSynthesizer: speechSynthesizer
        )
    }
    
    private func ocrView(mode ocrMode: OCRMode) -> some View {
        LiveOCRView(
            mode: $mode,
            ocrMode: ocrMode,
            selectedVoiceIdentifier: viewModel.selectedVoiceIdentifier
        )
        .ignoresSafeArea()
        .onDisappear {
            ocrViewModel.shutdown()
        }
        // Immediately stop all processing when any overlay or modal appears over OCR view
        .sheet(isPresented: $showSettings) {
            SettingsOverlayView(viewModel: viewModel, isPresented: $showSettings, mode: mode)
            // Immediately stop all processing when settings overlay appears
            .onAppear {
                ocrViewModel.stopSession()
            }
            // Resume OCR processing only if still in OCR mode
            .onDisappear {
                if mode == .englishOCR || mode == .spanishToEnglishOCR {
                    ocrViewModel.startSession()
                }
            }
        }
    }
    
    // Consolidated mode switching
    private func switchToMode(_ newMode: Mode) {
        cleanupCurrentMode()
        mode = newMode
    }
    
    private func switchToHome() {
        cleanupCurrentMode()
        mode = .home
    }
    
    private func cleanupCurrentMode() {
        ocrViewModel.shutdown()
        
        if mode == .objectDetection {
            viewModel.stopSession()  // Don't shutdown completely
            viewModel.clearDetections()
            // DON'T nil out viewModel or its yoloProcessor
        }
        showSettings = false
    }
    
    private func playWelcomeMessage() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let utterance = AVSpeechUtterance(string: "Welcome to the real-time AI. iOS Detection app. Thank you for choosing this voice!")
            utterance.voice = AVSpeechSynthesisVoice(identifier: viewModel.selectedVoiceIdentifier)
            utterance.rate = 0.5
            utterance.volume = 0.9
            speechSynthesizer.speak(utterance)
        }
    }
    
    private func setupOrientationObserver() {
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                orientation = UIDevice.current.orientation
            }
        }
    }
    
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        // When the app backgrounds (e.g., phone call or home),
        // stop ALL detection and OCR processes, and return to home screen.
        if newPhase == .background {
            cleanupCurrentMode()         // Stop all detection/OCR, clear resources, and reset view models
            viewModel.shutdown()         // Fully shut down processing and camera
            mode = .home                 // Always go to home screen on resume
        } else if newPhase == .active && mode == .objectDetection {
            viewModel.resumeCameraAndProcessing()
        }
    }
    
    // Emergency shutdown for all camera/vision sessions
    private func emergencyShutdown() {
        viewModel.shutdown()  // Stops object detection camera
        ocrViewModel.shutdown()  // Currently broken for camera
        // Need to add: Stop OCR camera preview
    }
}

// MARK: - Home Screen View
struct HomeScreenView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var animationState: ContentView.AnimationState
    @Binding var mode: ContentView.Mode
    @State private var showInstructions = false
    
    let onEnglishOCR: () -> Void
    let onSpanishOCR: () -> Void
    let onObjectDetection: () -> Void
    let onVoiceChange: () -> Void
    let speechSynthesizer: AVSpeechSynthesizer
    
    var body: some View {
        ZStack {
            splashBackground
            
            VStack {
                Spacer(minLength: 60)
                VStack(spacing: 24) {
                    HeadingView(animateIn: animationState.heading)
                    Spacer(minLength: 80)
                    GeometryReader { geometry in
                        VStack(spacing: 20) {
                            // English Text2Speech button with shaded emojis on both sides
                            Button(action: onEnglishOCR) {
                                HStack(spacing: 6) {
                                    Text("📖").font(.system(size: 31))
                                    Text("Eng Text2Speech")
                                        .font(.system(size: 21, weight: .bold, design: .rounded))
                                        .tracking(0.3)
                                    ShadedEmoji(emoji: "🗣️", size: 26)
                                }
                                .padding(.vertical, 18)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 24)
                            .background(
                                Capsule().fill(Color.blue.opacity(0.20))
                            )
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.blue, lineWidth: 2))
                            .opacity(animationState.button1 ? 1 : 0)
                            .foregroundStyle(.white)
                            .shadow(color: Color.blue.opacity(0.50), radius: 12)
                            .scaleEffect(animationState.button1 ? 1 : 0.7)
                            .animation(.easeOut(duration: 0.3), value: animationState.button1)
                            .accessibilityLabel("English Text to Speech")
                            .accessibilityHint("Point camera at English text to read it aloud")
                            .accessibilityAddTraits(.isButton)
                            
                            // Spanish to English Translate button (no shaded emoji, plain text with emoji inline)
                            Button(action: onSpanishOCR) {
                                HStack(spacing: 2) {
                                    Text("🇲🇽").font(.system(size: 28))
                                    Text("Span").font(.system(size: 21, weight: .bold, design: .rounded))
                                    Text("🇺🇸").font(.system(size: 28))
                                    Text("Eng").font(.system(size: 21, weight: .bold, design: .rounded))
                                    Text("🌎").font(.system(size: 28))
                                    Text("Translate").font(.system(size: 21, weight: .bold, design: .rounded))
                                }
                                .padding(.vertical, 18)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 24)
                            .background(
                                Capsule().fill(Color.green.opacity(0.20))
                            )
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.green, lineWidth: 2))
                            .opacity(animationState.button2 ? 1 : 0)
                            .foregroundStyle(.white)
                            .shadow(color: Color.green.opacity(0.50), radius: 12)
                            .scaleEffect(animationState.button2 ? 1 : 0.7)
                            .animation(.easeOut(duration: 0.3), value: animationState.button2)
                            .accessibilityLabel("Spanish to English Translator")
                            .accessibilityHint("Point camera at Spanish text to translate and speak in English")
                            .accessibilityAddTraits(.isButton)
                            
                            // Object Detection button (no shaded emoji, plain text with emoji inline)
                            Button(action: onObjectDetection) {
                                HStack(spacing: 6) {
                                    Text("🐶").font(.system(size: 32))
                                    Text("Object Detection")
                                        .font(.system(size: 21, weight: .bold, design: .rounded))
                                }
                                .padding(.vertical, 18)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 24)
                            .background(
                                Capsule().fill(Color.orange.opacity(0.20))
                            )
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.orange, lineWidth: 2))
                            .opacity(animationState.button3 ? 1 : 0)
                            .foregroundStyle(.white)
                            .shadow(color: Color.orange.opacity(0.50), radius: 12)
                            .scaleEffect(animationState.button3 ? 1 : 0.7)
                            .animation(.easeOut(duration: 0.3), value: animationState.button3)
                            .accessibilityLabel("Object Detection")
                            .accessibilityHint("Identify objects around you and hear them announced")
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .frame(height: 220)
                    Spacer(minLength: 32)
                    voicePicker
                    Spacer(minLength: 50)
                }
                .padding(.horizontal)
                Spacer(minLength: 60)
            }
            
            infoButton
        }
        .sheet(isPresented: $showInstructions) {
            AppInstructionsView()
                // Immediately stop all processing when instructions overlay appears
                .onAppear {
                    viewModel.pauseCameraAndProcessing()
                }
                // Resume processing only if in object detection mode
                .onDisappear {
                    if mode == .objectDetection {
                        viewModel.resumeCameraAndProcessing()
                    }
                }
        }
        .onAppear {
            if !animationState.hasAnimatedOnce {
                animateInSequence()
                animationState.hasAnimatedOnce = true
            } else {
                animationState.showAll()
            }
            
            if !UserDefaults.standard.bool(forKey: "hasShownInstructions") {
                showInstructions = true
                UserDefaults.standard.set(true, forKey: "hasShownInstructions")
            }
        }
    }
    
    private var splashBackground: some View {
        GeometryReader { geometry in
            Image("SplashScreen")
                .resizable()
                .scaledToFill() // Ensures the image always stretches
                .ignoresSafeArea(.all, edges: .all) // Fill all edges
        }
    }
    
    private var voicePicker: some View {
        AnimatedVoicePicker(
            viewModel: viewModel,
            animateIn: animationState.picker,
            onVoiceChange: onVoiceChange,
            speechSynthesizer: speechSynthesizer
        )
    }
    
    private var infoButton: some View {
        Button(action: { showInstructions = true }) {
            Text("INFO 💡 GUIDE")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)  // Explicit white color for better readability
                .padding(.vertical, 6)
                .padding(.horizontal, 18)
        }
        .background(ButtonStyles.glassBackground()
            .opacity(0.20))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
        .overlay(Capsule().stroke(Color.black.opacity(0.32), lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding()
    }
    
    private func animateInSequence() {
        animationState.reset()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            animationState.splash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            animationState.heading = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
            animationState.button1 = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.20) {
            animationState.button2 = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.70) {
            animationState.button3 = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.20) {
            animationState.picker = true
        }
    }
}

// MARK: - Shared Button Styles
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
            let titleSize: CGFloat = 72 * scaleFactor
            let subtitleSize: CGFloat = 60 * scaleFactor
            
            VStack(spacing: -10 * scaleFactor) {
                StrokedText(text: "RealTime", size: titleSize)
                StrokedText(text: "Ai Camera", size: subtitleSize)
            }
            .multilineTextAlignment(.center)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .offset(y: 20 * scaleFactor)
            .opacity(animateIn ? 0.95 : 0)
            .scaleEffect(animateIn ? 1 : 0.85)
            .animation(.interpolatingSpring(stiffness: 200, damping: 14).delay(animateIn ? 0.05 : 0), value: animateIn)
        }
        .frame(height: 150)
    }
}

// Helper view for stroked text
struct StrokedText: View {
    let text: String
    let size: CGFloat
    
    var body: some View {
        ZStack {
            ForEach(Array(strokeOffsets.enumerated()), id: \.offset) { idx, offset in
                Text(text)
                    .font(.system(size: size, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                    .offset(x: offset.0, y: offset.1)
            }
            
            Text(text)
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.78, green: 0.93, blue: 1.0),
                            Color(red: 0.54, green: 0.80, blue: 0.97)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
    
    private var strokeOffsets: [(CGFloat, CGFloat)] {
        [(2, 2), (-2, -2), (2, -2), (-2, 2), (0, 2), (0, -2), (2, 0), (-2, 0)]
    }
}

// MARK: - Animated Voice Picker
struct AnimatedVoicePicker: View {
    @ObservedObject var viewModel: CameraViewModel
    let animateIn: Bool
    let onVoiceChange: () -> Void
    let speechSynthesizer: AVSpeechSynthesizer
    
    // Helper for detecting premium+ voice by name (e.g. "Ava", "Premium", "Plus", etc.).
    private func isPremiumPlus(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let name = voice.name.lowercased()
        return name.contains("premium") || name.contains("plus") || name.contains("ava")
    }
    
    // Updated premiumEnglishVoices to include premium+, then enhanced, then regular, sorted by favorite names, max 10, always include "Ava"
    private var premiumEnglishVoices: [AVSpeechSynthesisVoice] {
        let allVoices = AVSpeechSynthesisVoice.speechVoices().filter { v in
            v.language.hasPrefix("en") && !v.name.lowercased().contains("robot") && !v.name.lowercased().contains("whisper") && !v.name.lowercased().contains("grandma")
        }
        let favoriteNames = ["Ava", "Samantha", "Daniel", "Karen", "Moira", "Serena", "Martha", "Aaron", "Fred", "Tessa", "Fiona", "Allison", "Nicky", "Joelle", "Oliver"]
        let premiumPlus = allVoices.filter { isPremiumPlus($0) }
        let enhanced = allVoices.filter { $0.quality == .enhanced && !isPremiumPlus($0) }
        let regular = allVoices.filter { $0.quality != .enhanced && !isPremiumPlus($0) }
        let sortedPremiumPlus = premiumPlus.sorted { (lhs, rhs) in
            let f1 = favoriteNames.firstIndex(of: lhs.name) ?? Int.max
            let f2 = favoriteNames.firstIndex(of: rhs.name) ?? Int.max
            return f1 < f2
        }
        let sortedEnhanced = enhanced.sorted { (lhs, rhs) in
            let f1 = favoriteNames.firstIndex(of: lhs.name) ?? Int.max
            let f2 = favoriteNames.firstIndex(of: rhs.name) ?? Int.max
            return f1 < f2
        }
        let sortedRegular = regular.sorted { (lhs, rhs) in
            let f1 = favoriteNames.firstIndex(of: lhs.name) ?? Int.max
            let f2 = favoriteNames.firstIndex(of: rhs.name) ?? Int.max
            return f1 < f2
        }
        var result = [AVSpeechSynthesisVoice]()
        result.append(contentsOf: sortedPremiumPlus)
        if result.count < 10 { result.append(contentsOf: sortedEnhanced.prefix(10 - result.count)) }
        if result.count < 10 { result.append(contentsOf: sortedRegular.prefix(10 - result.count)) }
        // Always include Ava (US English) if present and not already included
        if let ava = allVoices.first(where: { $0.name == "Ava" && $0.language.hasPrefix("en") }), !result.contains(where: { $0.identifier == ava.identifier }) {
            result.insert(ava, at: 0)
        }
        return Array(result.prefix(10))
    }
    
    private func genderEmoji(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.gender {
        case .female: return "👩"
        case .male: return "👨"
        default: return "🧑"
        }
    }
    
    // Updated qualityTag to prevent duplicate tags if name already contains them
    private func qualityTag(for voice: AVSpeechSynthesisVoice) -> String {
        let name = voice.name
        if name.contains("(Premium)") || name.contains("(Enhanced)") {
            return ""
        }
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
        // Picker showing only premium English voices
        Picker(selection: Binding(
            get: { viewModel.selectedVoiceIdentifier },
            set: { newValue in
                viewModel.selectedVoiceIdentifier = newValue
                // Removed playVoiceDemo call here as per instructions
                onVoiceChange()
            }
        ), label:
            ZStack {
                Capsule()
                    .fill(Color.purple.opacity(0.24))
                    .frame(height: 36)
                HStack(spacing: 6) {
                    if let voice = selectedVoice {
                        Text(genderEmoji(for: voice))
                            .font(.system(size: 31))
                            .foregroundColor(.white)
                        Text(voice.name)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        let tag = qualityTag(for: voice)
                        if !tag.isEmpty {
                            Text(tag)
                                .font(.system(size: 18, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    } else {
                        Text("Select Voice")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        ) {
            ForEach(premiumEnglishVoices, id: \.identifier) { voice in
                let tag = qualityTag(for: voice)
                Text("\(genderEmoji(for: voice)) \(voice.name)\(tag.isEmpty ? "" : " \(tag)")")
                    .foregroundColor(.primary)  // Ensure menu items are readable
                    .tag(voice.identifier)
            }
        }
        .accessibilityLabel("Voice Selection")
        .accessibilityHint("Choose your preferred voice for speech feedback")
        .pickerStyle(MenuPickerStyle())
        .accentColor(.white)  // Set accent color to white for better visibility
        .padding(.vertical, 14)
        .padding(.horizontal, 32)
        .background(
            Capsule().fill(Color.purple.opacity(0.24))
        )
        .overlay(Capsule().stroke(Color.purple, lineWidth: 2))
        .opacity(animateIn ? 1 : 0)
        .scaleEffect(animateIn ? 1 : 0.7)
        .animation(.easeOut(duration: 0.3), value: animateIn)
    }
    
    private func playVoiceDemo(identifier: String) {
        let utterance = AVSpeechUtterance(string: "Welcome to the real-time AI. iOS Detection app. Thank you for choosing this voice!")
        if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        }
        utterance.rate = 0.5
        utterance.volume = 0.9
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speechSynthesizer.speak(utterance)
    }
}

// MARK: - Object Detection View (WITH LIDAR AND PORTRAIT MODE FIXES)
struct ObjectDetectionView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var mode: ContentView.Mode
    @Binding var showSettings: Bool
    @State private var showTorchPresets = false
    @State private var showConfidenceSlider = false
    @StateObject private var lidar = LiDARManager.shared
    let orientation: UIDeviceOrientation
    let isPortrait: Bool
    let rotationAngle: Angle
    let onBack: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraView(viewModel: viewModel)
                    .ignoresSafeArea()
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                // Set initial zoom on first change
                                if value == 1.0 {
                                    viewModel.setPinchGestureStartZoom()
                                }
                                viewModel.handlePinchGesture(value)
                            }
                    )

                DetectionOverlayView(
                    detectedObjects: viewModel.detections,
                    isPortrait: isPortrait,
                    orientation: orientation
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if viewModel.currentZoomLevel > 1.05 {
                    VStack {
                        Text(String(format: "%.1fx", viewModel.currentZoomLevel))
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.black.opacity(0.7))
                            )
                            .padding(.top, geometry.safeAreaInsets.top + 60)
                        Spacer()
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.currentZoomLevel)
                }
                
                if isPortrait {
                    portraitOverlays(geometry: geometry)
                } else {
                    landscapeOverlays(geometry: geometry)
                }
            }
        }
        .onAppear {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    // Removed print statement here
                }
            }
        }
    }
    
    @ViewBuilder
    private func portraitOverlays(geometry: GeometryProxy) -> some View {
        // Object count display and FPS display
        if !viewModel.detections.isEmpty {
            VStack(alignment: .trailing, spacing: 6) {
                Text("Objects: \(viewModel.detections.count)")
                    .font(.headline)
                    .padding(8)
                    .background(.ultraThinMaterial.opacity(0.20))
                    .foregroundStyle(.primary)
                    .cornerRadius(8)
                
                Text(String(format: "FPS: %.1f", viewModel.framesPerSecond))
                    .font(.headline)
                    .padding(8)
                    .background(.ultraThinMaterial.opacity(0.20))
                    .foregroundStyle(.primary)
                    .cornerRadius(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, geometry.safeAreaInsets.top + 12)
            .padding(.trailing, 18)
            .rotationEffect(.zero)
        }

        // Bottom controls with Mode Picker
        VStack {
            Spacer()
            
            // Mode picker above the control buttons
            Picker("Mode", selection: $viewModel.filterMode) {
                Text("All").tag("all")
                Text("Indoor").tag("indoor")
                Text("Outdoor").tag("outdoor")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            
            HStack(spacing: 10) {
                controlButton(
                    systemName: "camera.rotate",
                    foregroundColor: .primary,
                    action: {
                        viewModel.flipCamera()
                        // Turn off torch AND LiDAR if switching to front camera
                        if viewModel.cameraPosition == .front {
                            if viewModel.torchLevel > 0 {
                                viewModel.setTorchLevel(0.0)
                                showTorchPresets = false
                            }
                            if lidar.isActive {
                                lidar.toggle() // Turn off LiDAR when switching to front
                            }
                        }
                    }
                )
                .accessibilityLabel("Switch Camera")
                .accessibilityHint("Switches between front and rear camera")
                .accessibilityValue(viewModel.cameraPosition == .back ? "Using rear camera" : "Using front camera")
                
                if viewModel.cameraPosition == .back {
                    controlButton(
                        systemName: "rectangle.3.offgrid",
                        foregroundColor: viewModel.isUltraWide ? .cyan : .primary,
                        action: {
                            viewModel.toggleCameraZoom()
                        }
                    )
                    .accessibilityLabel(viewModel.isUltraWide ? "Switch to normal camera" : "Switch to wide angle camera")
                    .accessibilityHint("Changes camera field of view for wider or normal view")
                }
                
                if viewModel.cameraPosition == .back {
                    controlButton(
                        systemName: viewModel.torchLevel > 0 ? "flashlight.on.fill" : "flashlight.off.fill",
                        foregroundColor: viewModel.torchLevel > 0 ? .yellow : .primary,
                        action: {
                            if viewModel.torchLevel > 0 {
                                viewModel.setTorchLevel(0.0)
                                showTorchPresets = false
                            } else {
                                showTorchPresets = true
                            }
                        }
                    )
                    .overlay(
                        torchPresetsOverlay(isPortrait: true)
                    )
                }
                
                // Only show LiDAR button for back camera
                if lidar.isSupported && viewModel.cameraPosition == .back {
                    controlButton(
                        systemName: "ruler",
                        foregroundColor: lidar.isActive ? .green : .primary,
                        action: {
                            lidar.toggle()
                            // Force immediate depth capture setup
                            if !lidar.isActive {  // Just turned ON
                                viewModel.toggleDepthCapture(enabled: true)
                            } else {  // Just turned OFF
                                viewModel.toggleDepthCapture(enabled: false)
                            }
                        }
                    )
                    .accessibilityLabel(lidar.isActive ? "Turn off LiDAR ruler (distance measurement)" : "Turn on LiDAR ruler (distance measurement)")
                    .accessibilityHint("This button uses the ruler icon and toggles LiDAR distance measurement to objects in view.")
                }
                
                Button(action: {
                    viewModel.isSpeechEnabled.toggle()
                    if viewModel.isSpeechEnabled {
                        viewModel.announceSpeechEnabled()
                    } else {
                        viewModel.stopSpeech()
                    }
                }) {
                    Text("🗣️")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(
                            viewModel.isSpeechEnabled
                                ? Circle().fill(Color.green.opacity(0.85))
                                : Circle().fill(Color.white.opacity(0.65))
                        )
                        .foregroundColor(.black)
                }
                .accessibilityLabel(viewModel.isSpeechEnabled ? "Turn off speech announcements" : "Turn on speech announcements")
                .accessibilityHint("Controls automatic object detection announcements")
                .accessibilityValue(viewModel.isSpeechEnabled ? "Speech enabled" : "Speech disabled")
                
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        showConfidenceSlider.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "eye")
                            .font(.system(size: 22, weight: .medium))
                        Text("\(Int(viewModel.confidenceThreshold * 100))%")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.primary)
                    .frame(width: 90, height: 44)
                    .background(.ultraThinMaterial.opacity(0.20))
                    .clipShape(Capsule())
                }
                .overlay(
                    confidenceSliderOverlay(isPortrait: true)
                )
            }
            .padding(.bottom, geometry.safeAreaInsets.bottom + 40)
            .padding(.horizontal, 16)
        }
        
        // Back button
        backButton()
            .padding(.leading, 20)
            .padding(.top, geometry.safeAreaInsets.top + 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .rotationEffect(.zero)
    }
    
    @ViewBuilder
    private func landscapeOverlays(geometry: GeometryProxy) -> some View {
        // FPS and Objects display
        HStack(spacing: 8) {
            if !viewModel.detections.isEmpty {
                Text("Objects: \(viewModel.detections.count)")
                    .font(.headline)
                    .padding(8)
                    .background(.ultraThinMaterial.opacity(0.20))
                    .foregroundStyle(.primary)
                    .cornerRadius(8)
                    .fixedSize()
            }
            Text(String(format: "FPS: %.1f", viewModel.framesPerSecond))
                .font(.headline)
                .padding(8)
                .background(.ultraThinMaterial.opacity(0.20))
                .foregroundStyle(.primary)
                .cornerRadius(8)
                .fixedSize()
        }
        .rotationEffect(rotationAngle)
        .position(
            x: geometry.size.width - max(30, geometry.size.width * 0.15),
            y: max(120, geometry.size.height * 0.17)
        )

        HStack(spacing: 10) {
            controlButton(
                systemName: "camera.rotate",
                foregroundColor: .primary,
                size: 24,
                frameSize: 50,
                action: {
                    viewModel.flipCamera()
                    // Turn off torch AND LiDAR if switching to front camera
                    if viewModel.cameraPosition == .front {
                        if viewModel.torchLevel > 0 {
                            viewModel.setTorchLevel(0.0)
                            showTorchPresets = false
                        }
                        if lidar.isActive {
                            lidar.toggle() // Turn off LiDAR when switching to front
                        }
                    }
                }
            )
            .accessibilityLabel("Switch Camera")
            .accessibilityHint("Switches between front and rear camera")
            .accessibilityValue(viewModel.cameraPosition == .back ? "Using rear camera" : "Using front camera")
            
            if viewModel.cameraPosition == .back {
                controlButton(
                    systemName: "rectangle.3.offgrid",
                    foregroundColor: viewModel.isUltraWide ? .cyan : .primary,
                    size: 24,
                    frameSize: 50,
                    action: {
                        viewModel.toggleCameraZoom()
                    }
                )
                .accessibilityLabel(viewModel.isUltraWide ? "Switch to normal camera" : "Switch to wide angle camera")
                .accessibilityHint("Changes camera field of view for wider or normal view")
            } else {
                Color.clear.frame(width: 50, height: 50)
            }
            if viewModel.cameraPosition == .back {
                controlButton(
                    systemName: viewModel.torchLevel > 0 ? "flashlight.on.fill" : "flashlight.off.fill",
                    foregroundColor: viewModel.torchLevel > 0 ? .yellow : .primary,
                    size: 24,
                    frameSize: 50,
                    action: {
                        if viewModel.torchLevel > 0 {
                            viewModel.setTorchLevel(0.0)
                            showTorchPresets = false
                        } else {
                            showTorchPresets = true
                        }
                    }
                )
                .overlay(
                    torchPresetsOverlay(isPortrait: false)
                )
            }
            
            // Only show LiDAR button for back camera
            if lidar.isSupported && viewModel.cameraPosition == .back {
                controlButton(
                    systemName: "ruler",
                    foregroundColor: lidar.isActive ? .green : .primary,
                    size: 24,
                    frameSize: 50,
                    action: {
                        lidar.toggle()
                        // Force immediate depth capture setup (same as portrait)
                        if !lidar.isActive {  // Just turned ON
                            viewModel.toggleDepthCapture(enabled: true)
                        } else {  // Just turned OFF
                            viewModel.toggleDepthCapture(enabled: false)
                        }
                    }
                )
                .accessibilityLabel(lidar.isActive ? "Turn off LiDAR ruler (distance measurement)" : "Turn on LiDAR ruler (distance measurement)")
                .accessibilityHint("This button uses the ruler icon and toggles LiDAR distance measurement to objects in view.")
            }
            
            // REPLACED speech toggle button body:
            Button(action: {
                viewModel.isSpeechEnabled.toggle()
                if viewModel.isSpeechEnabled {
                    viewModel.announceSpeechEnabled()
                } else {
                    viewModel.stopSpeech()
                }
            }) {
                Text("🗣️")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(
                                viewModel.isSpeechEnabled
                                    ? Color.green.opacity(0.45)
                                    : Color.clear
                            )
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .fill(.ultraThinMaterial.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                    .opacity(viewModel.isSpeechEnabled ? 0 : 1)
                            )
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                viewModel.isSpeechEnabled
                                    ? Color.green.opacity(0.5)
                                    : Color.white.opacity(0.2),
                                lineWidth: 1
                            )
                    )
                    .foregroundColor(viewModel.isSpeechEnabled ? .black : .white)
            }
            .accessibilityLabel(viewModel.isSpeechEnabled ? "Turn off speech announcements" : "Turn on speech announcements")
            .accessibilityHint("Controls automatic object detection announcements")
            .accessibilityValue(viewModel.isSpeechEnabled ? "Speech enabled" : "Speech disabled")
            
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    showConfidenceSlider.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "eye")
                        .font(.system(size: 22, weight: .medium))
                    Text("\(Int(viewModel.confidenceThreshold * 100))%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .foregroundColor(.primary)
                .frame(width: 90, height: 44)
                .background(.ultraThinMaterial.opacity(0.20))
                .clipShape(Capsule())
            }
            .overlay(
                confidenceSliderOverlay(isPortrait: false)
            )
            Picker("Mode", selection: $viewModel.filterMode) {
                Text("All").tag("all")
                Text("Indoor").tag("indoor")
                Text("Outdoor").tag("outdoor")
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 200)
        }
        .padding(.trailing, 50)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rotationEffect(rotationAngle)
        .fixedSize()
        .position(
            x: max(40, geometry.size.width * 0.05),
            y: geometry.size.height - max(235, geometry.size.height * 0.3)
        )
        
        backButton()
            .rotationEffect(rotationAngle)
            .fixedSize()
            .position(
                x: max(60, geometry.size.width * 0.08),
                y: min(50, geometry.size.height * 0.12)
            )
    }
    
    private func controlButton(
        systemName: String,
        foregroundColor: Color = .primary,
        size: CGFloat = 26,
        frameSize: CGFloat = 60,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(foregroundColor)
                .symbolRenderingMode(.palette)
                .frame(width: frameSize, height: frameSize)
                .background(
                    RoundedRectangle(cornerRadius: frameSize/2)
                        .fill(foregroundColor == .cyan ? Color.cyan.opacity(0.15) : Color.clear)
                )
                .clipShape(Circle())
        }
    }
    
    private func backButton() -> some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onBack()
        }) {
            Text("Back")
                .padding(12)
                .background(.ultraThinMaterial.opacity(0.20))
                .foregroundStyle(.primary)
                .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private func torchPresetsOverlay(isPortrait: Bool) -> some View {
        if showTorchPresets {
            VStack(spacing: 8) {
                ForEach([100, 75, 50, 25], id: \.self) { percentage in
                    torchPresetButton(percentage: percentage)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .offset(y: -90)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        }
    }

    private func torchPresetButton(percentage: Int, rotateText: Bool = false) -> some View {
        Button(action: {
            let level = Float(percentage) / 100.0
            viewModel.setTorchLevel(level)
            showTorchPresets = false
        }) {
            Text("\(percentage)%")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .rotationEffect(.zero)
                .frame(width: 60, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Int(viewModel.torchLevel * 100) == percentage ? Color.yellow.opacity(0.4) : Color.white.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Int(viewModel.torchLevel * 100) == percentage ? Color.yellow : Color.white.opacity(0.3), lineWidth: 1)
                )
        }
    }
    
    @ViewBuilder
    private func confidenceSliderOverlay(isPortrait: Bool) -> some View {
        if showConfidenceSlider {
            Group {
                if isPortrait {
                    VStack(spacing: 8) {
                        Slider(value: $viewModel.confidenceThreshold, in: 0.0001...1.0, onEditingChanged: { editing in
                            // Only dismiss when user stops dragging
                            if !editing {
                                // Add a small delay to ensure the value is set
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showConfidenceSlider = false
                                }
                            }
                        })
                        .accentColor(.blue)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 160, height: 32)
                        Text("\(Int(viewModel.confidenceThreshold * 100))%")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                    }
                } else {
                    VStack(spacing: 8) {
                        Slider(value: $viewModel.confidenceThreshold, in: 0.0001...1.0, onEditingChanged: { editing in
                            // Only dismiss when user stops dragging
                            if !editing {
                                // Add a small delay to ensure the value is set
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    showConfidenceSlider = false
                                }
                            }
                        })
                        .accentColor(.blue)
                        .frame(width: 160, height: 32)
                        Text("\(Int(viewModel.confidenceThreshold * 100))%")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(10)
            // Removed .background here as per instructions
            .shadow(radius: 8)
            .offset(y: isPortrait ? -90 : -60)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - LiveOCR View Wrapper
struct LiveOCRViewWrapper: View {
    @Binding var mode: ContentView.Mode
    let ocrMode: OCRMode
    let selectedVoiceIdentifier: String
    @Binding var viewModel: LiveOCRViewModel?
    let onBack: () -> Void
    
    var body: some View {
        LiveOCRView(
            mode: $mode,
            ocrMode: ocrMode,
            selectedVoiceIdentifier: selectedVoiceIdentifier
        )
        .onAppear {
            if viewModel == nil {
                viewModel = LiveOCRViewModel()
            }
        }
    }
}

