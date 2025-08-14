import SwiftUI
import AVFoundation
import CoreVideo

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

// Helper view for outlined text
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
            // Black stroke/outline
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
            
            // White fill
            Text(text)
                .font(.system(size: fontSize, weight: .bold, design: .default))
                .foregroundColor(fillColor)
        }
    }
}

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
    @StateObject private var ocrViewModel = LiveOCRViewModel()
    // Added debouncer for mode switching buttons in ContentView
    @StateObject private var buttonDebouncer = ButtonPressDebouncer()
    
    private var normalizedOrientation: UIDeviceOrientation {
        switch orientation {
        case .portraitUpsideDown: return .portrait
        case .landscapeRight: return .landscapeLeft
        default: return orientation
        }
    }
    
    @State private var showSettings = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    
    // Consolidated animation state
    @State private var animationState = AnimationState()
    
    @Environment(\.scenePhase) private var scenePhase
    
    // Add debounce for mode switching
    @State private var lastModeSwitch = Date.distantPast
    
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
        }
        .onDisappear {
            // No memory timers to invalidate anymore
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
                onBack: switchToHome,
                buttonDebouncer: buttonDebouncer  // Pass debouncer to ObjectDetectionView
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
            buttonDebouncer: buttonDebouncer,
            onEnglishOCR: {
                mode = .englishOCR
            },
            onSpanishOCR: {
                mode = .spanishToEnglishOCR
            },
            onObjectDetection: {
                mode = .objectDetection
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
            // Defensive cleanup for OCR shutdown
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
    
    /// Consolidated mode switching with debounce
    private func switchToMode(_ newMode: Mode) {
        let now = Date()
        print("[DEBUG] switchToMode called with newMode: \(newMode), current mode: \(mode)")
        guard now.timeIntervalSince(lastModeSwitch) > 1.0 else { return }  // Prevent rapid switching
        lastModeSwitch = now

        // Only reset if not already at home
        if mode != .home {
            performReset()
        }

        // Small delay to ensure cleanup completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            mode = newMode
            print("[DEBUG] mode switched to: \(mode)")

            // Reinitialize for the new mode
            if newMode == .objectDetection {
                viewModel.reinitialize()
                viewModel.startSession()
            } else if newMode == .englishOCR || newMode == .spanishToEnglishOCR {
                ocrViewModel.startSession()
            }
        }
    }
    
    private func switchToHome() {
        let now = Date()
        guard now.timeIntervalSince(lastModeSwitch) > 1.0 else { return }  // Prevent rapid switching
        lastModeSwitch = now
        
        performReset()
        mode = .home
        
        // Reinitialize viewModel for home start
        viewModel.reinitialize()
        ocrViewModel.shutdown()
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
    
    // MARK: - Perform basic reset on mode switch or panic; no memory cache clearing here anymore
    private func performReset() {
        print("performReset() called - performing basic reset")
        
        // Defensive autoreleasepool
        autoreleasepool {
            // Stop all active processing
            viewModel.stopSession()
            viewModel.stopSpeech()
            ocrViewModel.shutdown()
            
            // Clear all detections and state
            viewModel.clearDetections()
            
            // Defensive check: attempt to reset YOLO processor
            if let yoloProc = viewModel.yoloProcessor {
                print("YOLO Processor retain count: \(CFGetRetainCount(yoloProc))")
                yoloProc.reset()
            } else {
                print("YOLO Processor is nil")
            }
            
            // Reset various settings to defaults (except user preferences)
            viewModel.confidenceThreshold = 0.75
            viewModel.frameRate = 30
            viewModel.filterMode = "all"
            viewModel.currentZoomLevel = 1.0
            viewModel.isUltraWide = false
            viewModel.torchLevel = 0.0
            viewModel.isTorchOn = false
            
            // Stop and cleanup LiDAR data
            LiDARManager.shared.stop()
            LiDARManager.shared.cleanupOldHistories(currentDetectionIds: Set())
            
            // Clear OCR text
            ocrViewModel.clearText()
            
            // Attempt to print retain count of view models for debugging
            print("CameraViewModel retain count: \(CFGetRetainCount(viewModel))")
            print("LiveOCRViewModel retain count: \(CFGetRetainCount(ocrViewModel))")
        }
        
        // Reinitialize viewModel and OCR view model after cleanup
        viewModel.reinitialize()
        ocrViewModel.shutdown()
        print("Basic reset completed, view models reinitialized")
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
        if newPhase == .background {
            // Basic reset when going to background
            performReset()
            mode = .home
        } else if newPhase == .inactive {
            // Stop camera when app is inactive (control center, notifications)
            viewModel.stopSession()
            ocrViewModel.stopSession()
        } else if newPhase == .active {
            // Fresh start when coming back
            performReset()
            
            // Reinitialize if returning to detection mode
            if mode == .objectDetection {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    viewModel.reinitialize()
                    viewModel.startSession()
                }
            }
        }
    }
}

// MARK: - Home Screen View
struct HomeScreenView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var animationState: ContentView.AnimationState
    @Binding var mode: ContentView.Mode
    @State private var showInstructions = false
    
    // Added debouncer object for per-button press debounce
    @StateObject var buttonDebouncer: ButtonPressDebouncer
    
    let onEnglishOCR: () -> Void
    let onSpanishOCR: () -> Void
    let onObjectDetection: () -> Void
    let onVoiceChange: () -> Void
    let speechSynthesizer: AVSpeechSynthesizer
    
    var body: some View {
        ZStack {
            splashBackground
            
            VStack {
                Spacer(minLength: 80) // Increased from 24 to lower the heading
                VStack(spacing: 12) {
                    HeadingView(animateIn: animationState.heading)
                    Spacer(minLength: 30) // Increased from 16
                    GeometryReader { geometry in
                        VStack(spacing: 18) { // Reduced from 20 for tighter spacing
                            // English Text2Speech button with outlined text
                            Button(action: {
                                // Per-button debounce: ignore press if too soon
                                guard buttonDebouncer.canPress() else { return }
                                onEnglishOCR()
                            }) {
                                HStack(spacing: 4) { // Reduced spacing
                                    Text("📖").font(.system(size: 34))
                                    OutlinedText(text: "Eng Text2Speech", fontSize: 20) // Reduced from 26
                                    ShadedEmoji(emoji: "🗣️", size: 29)
                                }
                                .padding(.vertical, 16) // Reduced from 18
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 20) // Reduced from 24
                            .background(
                                Capsule().fill(Color.blue.opacity(0.20))
                                    .overlay(Capsule().stroke(Color.black, lineWidth: 1.1))
                            )
                            .clipShape(Capsule())
                            .opacity(animationState.button1 ? 1 : 0)
                            .shadow(color: Color.blue.opacity(0.50), radius: 12)
                            .scaleEffect(animationState.button1 ? 1 : 0.7)
                            .animation(.easeOut(duration: 0.3), value: animationState.button1)
                            .accessibilityLabel("English Text to Speech")
                            .accessibilityHint("Point camera at English text to read it aloud")
                            .accessibilityAddTraits(.isButton)
                            
                            // Spanish to English Translate button with outlined text
                            Button(action: {
                                // Per-button debounce: ignore press if too soon
                                guard buttonDebouncer.canPress() else { return }
                                onSpanishOCR()
                            }) {
                                HStack(spacing: 2) {
                                    Text("🇲🇽").font(.system(size: 31))
                                    OutlinedText(text: "Span", fontSize: 18) // Reduced from 26
                                    Text("🇺🇸").font(.system(size: 31))
                                    OutlinedText(text: "Eng", fontSize: 18) // Reduced from 26
                                    Text("🌎").font(.system(size: 31))
                                    OutlinedText(text: "Translate", fontSize: 18) // Reduced from 26
                                }
                                .padding(.vertical, 16) // Reduced from 18
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 20) // Reduced from 24
                            .background(
                                Capsule().fill(Color.green.opacity(0.20))
                                    .overlay(Capsule().stroke(Color.black, lineWidth: 1.1))
                            )
                            .clipShape(Capsule())
                            .opacity(animationState.button2 ? 1 : 0)
                            .shadow(color: Color.green.opacity(0.50), radius: 12)
                            .scaleEffect(animationState.button2 ? 1 : 0.7)
                            .animation(.easeOut(duration: 0.3), value: animationState.button2)
                            .accessibilityLabel("Spanish to English Translator")
                            .accessibilityHint("Point camera at Spanish text to translate and speak in English")
                            .accessibilityAddTraits(.isButton)
                            
                            // Object Detection button with outlined text
                            Button(action: {
                                // Per-button debounce: ignore press if too soon
                                guard buttonDebouncer.canPress() else { return }
                                onObjectDetection()
                            }) {
                                HStack(spacing: 4) { // Reduced spacing
                                    Text("🐶").font(.system(size: 35))
                                    OutlinedText(text: "Object Detection", fontSize: 20) // Reduced from 26
                                }
                                .padding(.vertical, 16) // Reduced from 18
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 20) // Reduced from 24
                            .background(
                                Capsule().fill(Color.orange.opacity(0.20))
                                    .overlay(Capsule().stroke(Color.black, lineWidth: 1.1))
                            )
                            .clipShape(Capsule())
                            .opacity(animationState.button3 ? 1 : 0)
                            .shadow(color: Color.orange.opacity(0.50), radius: 12)
                            .scaleEffect(animationState.button3 ? 1 : 0.7)
                            .animation(.easeOut(duration: 0.3), value: animationState.button3)
                            .accessibilityLabel("Object Detection")
                            .accessibilityHint("Identify objects around you and hear them announced")
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .frame(height: 220)
                    Spacer(minLength: 25) // Reduced from 32
                    voicePicker
                    Spacer(minLength: 40) // Reduced from 50
                }
                .padding(.horizontal)
                Spacer(minLength: 50) // Reduced from 60
            }
            
            // Info button with debouncer protection
            infoButton
        }
        .sheet(isPresented: $showInstructions) {
            AppInstructionsView(selectedVoiceIdentifier: viewModel.selectedVoiceIdentifier)
            // Immediately stop all processing when instructions overlay appears
            .onAppear {
                // Debounce sheet appearance action
                if buttonDebouncer.canPress() {
                    viewModel.pauseCameraAndProcessing()
                    print("Instructions opened with voice: \(viewModel.selectedVoiceIdentifier)")
                }
            }
            // Resume processing only if in object detection mode
            .onDisappear {
                if buttonDebouncer.canPress() {
                    if mode == .objectDetection {
                        viewModel.resumeCameraAndProcessing()
                    }
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
        // Remove the background and overlay - let the picker handle its own styling
        .onTapGesture {
            _ = buttonDebouncer.canPress()
        }
    }
    
    private var infoButton: some View {
        Button(action: {
            // Debounced info button action
            guard buttonDebouncer.canPress() else { return }
            showInstructions = true
        }) {
            HStack(spacing: 6) {
                OutlinedText(text: "INFO", fontSize: 14)
                Text("💡").font(.system(size: 14))
                OutlinedText(text: "GUIDE", fontSize: 14)
            }
            .foregroundColor(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 18)
        }
        .background(ButtonStyles.glassBackground()
            .opacity(0.20))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.black, lineWidth: 1.1))
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
            let titleSize: CGFloat = 52 * scaleFactor // Reduced from 72
            let subtitleSize: CGFloat = 44 * scaleFactor // Reduced from 60
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.20)) // Match button opacity of 0.20
                    .overlay(Capsule().stroke(Color.black, lineWidth: 1.1))
                    .shadow(color: Color.blue.opacity(0.10), radius: 10 * scaleFactor)
                VStack(spacing: -8 * scaleFactor) { // Reduced spacing
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
                .padding(.horizontal, 25 * scaleFactor) // Reduced from 30
                .padding(.vertical, 14 * scaleFactor) // Reduced from 18
            }
            .frame(width: geometry.size.width * 0.92, height: 120) // Reduced height from 150
            .position(x: geometry.size.width / 2, y: 60) // Center horizontally
            .opacity(animateIn ? 1 : 0) // Full opacity for the whole view
            .scaleEffect(animateIn ? 1 : 0.88)
            .animation(.interpolatingSpring(stiffness: 200, damping: 14).delay(animateIn ? 0.05 : 0), value: animateIn)
        }
        .frame(height: 120) // Reduced from 150
    }
}

struct EmbossedGradientText: View {
    let text: String
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Main white & blue halo, tight
            Text(text)
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
                .shadow(color: Color.blue.opacity(0.38), radius: 6, x: 0, y: 0)
                .shadow(color: Color.white.opacity(0.44), radius: 4, x: 0, y: 0)
            // Embossed top highlight
            Text(text)
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.68))
                .offset(x: -1, y: -2)
                .blur(radius: 0.7)
            // Embossed shadow (bottom right)
            Text(text)
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundColor(.black.opacity(0.13))
                .offset(x: 1, y: 2)
                .blur(radius: 0.7)
            // Water blue gradient fill
            Text(text)
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.70, green: 0.90, blue: 1.0),
                            Color(red: 0.45, green: 0.75, blue: 1.0),
                            Color(red: 0.60, green: 0.92, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Inner shine highlight
                    Text(text)
                        .font(.system(size: size, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.22))
                        .blur(radius: 1.1)
                        .offset(y: -size * 0.14)
                        .mask(
                            LinearGradient(
                                colors: [Color.white, Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
        }
    }
}

// MARK: - Animated Voice Picker
struct AnimatedVoicePicker: View {
    @ObservedObject var viewModel: CameraViewModel
    let animateIn: Bool
    let onVoiceChange: () -> Void
    let speechSynthesizer: AVSpeechSynthesizer
    @State private var showVoiceGrid = false
    
    // Helper for detecting premium+ voice by name
    private func isPremiumPlus(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let name = voice.name.lowercased()
        return name.contains("premium") || name.contains("plus") || name.contains("ava")
    }
    
    // Updated premiumEnglishVoices
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
        // Main button
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
            // Compact grid overlay - positioned ABOVE the button
            Group {
                if showVoiceGrid {
                    // Tap outside to close
                    Color.clear
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25)) {
                                showVoiceGrid = false
                            }
                        }
                        .offset(y: -400)
                    
                    // Voice grid
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
                            .fill(Color.black.opacity(0.85))  // Darker background
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                            )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 10)
                    .offset(y: -200)  // Lowered position
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        )
        .accessibilityLabel("Voice Selection")
        .accessibilityHint("Choose your preferred voice for speech feedback")
    }
}// MARK: - Voice Selection Grid
struct VoiceSelectionGrid: View {
    let voices: [AVSpeechSynthesisVoice]
    let selectedVoiceId: String
    let onSelect: (String) -> Void
    let genderEmoji: (AVSpeechSynthesisVoice) -> String
    let qualityTag: (AVSpeechSynthesisVoice) -> String
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(voices, id: \.identifier) { voice in
                        Button(action: {
                            onSelect(voice.identifier)
                        }) {
                            VStack(spacing: 8) {
                                Text(genderEmoji(voice))
                                    .font(.system(size: 36))
                                Text(voice.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                let tag = qualityTag(voice)
                                if !tag.isEmpty {
                                    Text(tag)
                                        .font(.system(size: 20))
                                        .foregroundColor(.yellow)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(voice.identifier == selectedVoiceId ?
                                          Color.purple.opacity(0.3) :
                                          Color.gray.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(voice.identifier == selectedVoiceId ?
                                           Color.purple :
                                           Color.clear, lineWidth: 2)
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Select Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onSelect(selectedVoiceId)
                    }
                }
            }
        }
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
    @State private var lidarNotificationMessage: String? = nil
    let orientation: UIDeviceOrientation
    let isPortrait: Bool
    let rotationAngle: Angle
    let onBack: () -> Void
    
    // Added debouncer for all control buttons in ObjectDetectionView
    @ObservedObject var buttonDebouncer: ButtonPressDebouncer
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraView(viewModel: viewModel)
                    .ignoresSafeArea()
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                viewModel.handlePinchGesture(value)
                            }
                            .onEnded { _ in
                                // When gesture ends, update the initial zoom to current zoom
                                // This prevents snap-back on the next gesture
                                viewModel.setPinchGestureStartZoom()
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                // Set initial zoom when gesture begins (value will be ~1.0)
                                if value > 0.98 && value < 1.02 {
                                    viewModel.setPinchGestureStartZoom()
                                }
                            }
                    )

                DetectionOverlayView(
                    detectedObjects: viewModel.detections,
                    isPortrait: isPortrait,
                    orientation: orientation
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if viewModel.currentZoomLevel > 1.05 || viewModel.currentZoomLevel < 0.95 {
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
                
                // Beautiful glass notification overlay
                Group {
                    if let message = lidarNotificationMessage {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "ruler")
                                    .font(.system(size: 16, weight: .medium))
                                Text(message)
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.white.opacity(0.25),
                                                        Color.white.opacity(0.05)
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                            )
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                            .animation(.spring(response: 0.3), value: lidarNotificationMessage)
                            Spacer()
                        }
                        .rotationEffect(isPortrait ? .zero : rotationAngle)
                        .padding(.bottom, isPortrait ? 10 : 0)
                        .padding(.leading, isPortrait ? 0 : 12)
                    }
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
        .onChange(of: lidar.isAvailable) { newValue in
            if !newValue && lidar.isEnabled {
                showLiDARNotification("LiDAR not available in \(viewModel.isUltraWide ? "ultra-wide" : "this") mode")
            }
        }
        .onChange(of: viewModel.isUltraWide) { _ in
            if lidar.isEnabled && !lidar.isAvailable {
                showLiDARNotification("LiDAR only works with 1x camera")
            }
        }
        .onChange(of: viewModel.currentZoomLevel) { newValue in
            // Check if LiDAR is enabled and zoom changed significantly
            if lidar.isEnabled && lidar.isAvailable {
                if newValue < 0.95 || newValue > 1.05 {
                    // Not at 1x - LiDAR might not work well
                    showLiDARNotification("LiDAR works best at 1x zoom")
                }
            }
        }
    }
    
    private func showLiDARNotification(_ message: String) {
        lidarNotificationMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            lidarNotificationMessage = nil
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
            .padding(.top, geometry.safeAreaInsets.top + 18)
            .padding(.trailing, 35)
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
            .padding(.horizontal, 40)
            .padding(.bottom, 10)
            
            HStack(spacing: 12) {
                Spacer()
                
                // All control buttons wrapped with debouncer guard
                
                controlButton(
                    systemName: "camera.rotate",
                    foregroundColor: .primary,
                    size: 26,
                    frameSize: 48,
                    action: {
                        guard buttonDebouncer.canPress() else { return }
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
                        size: 26,
                        frameSize: 48,
                        action: {
                            guard buttonDebouncer.canPress() else { return }
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
                        size: 26,
                        frameSize: 48,
                        action: {
                            guard buttonDebouncer.canPress() else { return }
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
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.15)
                    )
                }
                
                // Only show LiDAR button for back camera
                if lidar.isSupported && viewModel.cameraPosition == .back {
                    controlButton(
                        systemName: "ruler",
                        foregroundColor: lidar.isEnabled && lidar.isAvailable ? .green :
                                       lidar.isAvailable ? .blue :
                                       Color.gray.opacity(0.6),
                        size: 26,
                        frameSize: 48,
                        action: {
                            guard buttonDebouncer.canPress() else { return }
                            if lidar.isAvailable {
                                lidar.toggle()
                                // Force immediate depth capture setup
                                if !lidar.isActive {  // Just turned ON
                                    viewModel.toggleDepthCapture(enabled: true)
                                } else {  // Just turned OFF
                                    viewModel.toggleDepthCapture(enabled: false)
                                }
                            } else {
                                showLiDARNotification("Switch to 1x camera for LiDAR")
                            }
                        }
                    )
                    .disabled(!lidar.isAvailable)
                    .opacity(lidar.isAvailable ? 1.0 : 0.6)
                    .accessibilityLabel(
                        !lidar.isAvailable ? "LiDAR unavailable in this mode" :
                        lidar.isEnabled ? "Turn off LiDAR distance measurement" :
                        "Turn on LiDAR distance measurement"
                    )
                    .accessibilityHint(
                        !lidar.isAvailable ? "Switch to 1x camera to use LiDAR" :
                        "Measures distance to detected objects"
                    )
                }
                
                // Updated speech toggle button with unified style and debounce
                Button(action: {
                    guard buttonDebouncer.canPress() else { return }
                    viewModel.isSpeechEnabled.toggle()
                    if viewModel.isSpeechEnabled {
                        viewModel.announceSpeechEnabled()
                    } else {
                        viewModel.stopSpeech()
                    }
                }) {
                    Text("🗣️")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .opacity(0.15)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    viewModel.isSpeechEnabled
                                        ? Color.green.opacity(0.5)
                                        : Color.white.opacity(0.25),
                                    lineWidth: viewModel.isSpeechEnabled ? 2 : 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
                        .foregroundColor(viewModel.isSpeechEnabled ? .black : .primary)
                }
                .accessibilityLabel(viewModel.isSpeechEnabled ? "Turn off speech announcements" : "Turn on speech announcements")
                .accessibilityHint("Controls automatic object detection announcements")
                .accessibilityValue(viewModel.isSpeechEnabled ? "Speech enabled" : "Speech disabled")
                
                Button(action: {
                    guard buttonDebouncer.canPress() else { return }
                    withAnimation(.spring(response: 0.3)) {
                        showConfidenceSlider.toggle()
                    }
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "eye")
                            .font(.system(size: 22, weight: .medium))
                        Text("\(Int(viewModel.confidenceThreshold * 100))%")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.primary)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial.opacity(0.20))
                    .clipShape(Circle())
                }
                .overlay(
                    confidenceSliderOverlay(isPortrait: true)
                )
                
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 36) // Added bottom padding to move controls higher from bottom
        }
        
        // Back button wrapped with debouncer
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
            x: geometry.size.width - max(30, geometry.size.width * 0.05),
            y: max(120, geometry.size.height * 0.07)
        )

        HStack(spacing: 12) {
            Spacer()
            
            // All control buttons wrapped with debouncer guard
            
            controlButton(
                systemName: "camera.rotate",
                foregroundColor: .primary,
                size: 24,
                frameSize: 48,
                action: {
                    guard buttonDebouncer.canPress() else { return }
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
                    frameSize: 48,
                    action: {
                        guard buttonDebouncer.canPress() else { return }
                        viewModel.toggleCameraZoom()
                    }
                )
                .accessibilityLabel(viewModel.isUltraWide ? "Switch to normal camera" : "Switch to wide angle camera")
                .accessibilityHint("Changes camera field of view for wider or normal view")
            } else {
                Color.clear.frame(width: 48, height: 48)
            }
            if viewModel.cameraPosition == .back {
                controlButton(
                    systemName: viewModel.torchLevel > 0 ? "flashlight.on.fill" : "flashlight.off.fill",
                    foregroundColor: viewModel.torchLevel > 0 ? .yellow : .primary,
                    size: 24,
                    frameSize: 48,
                    action: {
                        guard buttonDebouncer.canPress() else { return }
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
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.15)
                )
            }
            
            // Only show LiDAR button for back camera
            if lidar.isSupported && viewModel.cameraPosition == .back {
                controlButton(
                    systemName: "ruler",
                    foregroundColor: lidar.isEnabled && lidar.isAvailable ? .green :
                                   lidar.isAvailable ? .blue :
                                   Color.gray.opacity(0.6),
                    size: 24,
                    frameSize: 48,
                    action: {
                        guard buttonDebouncer.canPress() else { return }
                        if lidar.isAvailable {
                            lidar.toggle()
                            // Force immediate depth capture setup (same as portrait)
                            if !lidar.isActive {  // Just turned ON
                                viewModel.toggleDepthCapture(enabled: true)
                            } else {  // Just turned OFF
                                viewModel.toggleDepthCapture(enabled: false)
                            }
                        } else {
                            showLiDARNotification("Switch to 1x camera for LiDAR")
                        }
                    }
                )
                .disabled(!lidar.isAvailable)
                .opacity(lidar.isAvailable ? 1.0 : 0.6)
                .accessibilityLabel(
                    !lidar.isAvailable ? "LiDAR unavailable in this mode" :
                    lidar.isEnabled ? "Turn off LiDAR distance measurement" :
                    "Turn on LiDAR distance measurement"
                )
                .accessibilityHint(
                    !lidar.isAvailable ? "Switch to 1x camera to use LiDAR" :
                    "Measures distance to detected objects"
                )
            }
            
            // Updated speech toggle button with unified style and debounce
            Button(action: {
                guard buttonDebouncer.canPress() else { return }
                viewModel.isSpeechEnabled.toggle()
                if viewModel.isSpeechEnabled {
                    viewModel.announceSpeechEnabled()
                } else {
                    viewModel.stopSpeech()
                }
            }) {
                Text("🗣️")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.15)
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                viewModel.isSpeechEnabled
                                    ? Color.green.opacity(0.5)
                                    : Color.white.opacity(0.25),
                                lineWidth: viewModel.isSpeechEnabled ? 2 : 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
                    .foregroundColor(viewModel.isSpeechEnabled ? .black : .primary)
            }
            .accessibilityLabel(viewModel.isSpeechEnabled ? "Turn off speech announcements" : "Turn on speech announcements")
            .accessibilityHint("Controls automatic object detection announcements")
            .accessibilityValue(viewModel.isSpeechEnabled ? "Speech enabled" : "Speech disabled")
            
            Button(action: {
                guard buttonDebouncer.canPress() else { return }
                withAnimation(.spring(response: 0.3)) {
                    showConfidenceSlider.toggle()
                }
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "eye")
                        .font(.system(size: 22, weight: .medium))
                    Text("\(Int(viewModel.confidenceThreshold * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.primary)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial.opacity(0.20))
                .clipShape(Circle())
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
            
            Spacer()
        }
        .padding(.horizontal, 32)
        .rotationEffect(rotationAngle)
        .fixedSize()
        .position(
            x: max(40, geometry.size.width * 0.05),
            y: geometry.size.height - max(235, geometry.size.height * 0.45)
        )
        
        // Back button wrapped with debouncer
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
            guard buttonDebouncer.canPress() else { return }
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
            guard buttonDebouncer.canPress() else { return }
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

#Preview {
    ContentView()
}
