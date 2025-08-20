import SwiftUI
import AVFoundation
import CoreVideo

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
    @StateObject private var buttonDebouncer = ButtonPressDebouncer()
    // Correct singleton pattern: use @ObservedObject for ResourceManager.shared in SwiftUI views.
    @ObservedObject private var resourceManager = ResourceManager.shared
    
    private var normalizedOrientation: UIDeviceOrientation {
        switch orientation {
        case .portraitUpsideDown: return .portrait
        case .landscapeRight: return .landscapeLeft
        default: return orientation
        }
    }
    
    @State private var showSettings = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var animationState = AnimationState()
    @Environment(\.scenePhase) private var scenePhase
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
            
            if showSettings && (mode == .englishOCR || mode == .spanishToEnglishOCR) {
                SettingsOverlayView(viewModel: viewModel, isPresented: $showSettings, mode: mode)
                    .onAppear {
                        ocrViewModel.stopSession()
                    }
                    .onDisappear {
                        if mode == .englishOCR || mode == .spanishToEnglishOCR {
                            ocrViewModel.startSession()
                        }
                    }
            }
        }
        .onAppear {
            if storedMode == .home {
                mode = storedMode
            } else {
                mode = .home
            }
            setupOrientationObserver()
        }
        .onChange(of: scenePhase) { newValue in
            handleScenePhaseChange(newValue)
            storedMode = mode
        }
    }
    
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
                buttonDebouncer: buttonDebouncer
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
        HomeView(
            viewModel: viewModel,
            animationState: $animationState,
            mode: $mode,
            buttonDebouncer: buttonDebouncer,
            onEnglishOCR: {
                switchToMode(.ocrEnglish)
            },
            onSpanishOCR: {
                switchToMode(.ocrSpanish)
            },
            onObjectDetection: {
                switchToMode(.objectDetection)
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
        .sheet(isPresented: $showSettings) {
            SettingsOverlayView(viewModel: viewModel, isPresented: $showSettings, mode: mode)
                .onAppear {
                    ocrViewModel.stopSession()
                }
                .onDisappear {
                    if mode == .englishOCR || mode == .spanishToEnglishOCR {
                        ocrViewModel.startSession()
                    }
                }
        }
    }
    
    private func switchToHome() {
        let now = Date()
        guard now.timeIntervalSince(lastModeSwitch) > 1.0 else { return }
        lastModeSwitch = now
        
        SpeechManager.shared.resetSpeechState()
        performReset()
        switchToMode(.home)
        
        viewModel.reinitialize()
        ocrViewModel.shutdown()
    }
    
    private func cleanupCurrentMode() {
        SpeechManager.shared.resetSpeechState()
        ocrViewModel.shutdown()
        
        if mode == .objectDetection {
            viewModel.stopSession()
            viewModel.clearDetections()
        }
        showSettings = false
    }
    
    private func performReset() {
        // print("performReset() called - performing basic reset")
        
        autoreleasepool {
            viewModel.stopSession()
            SpeechManager.shared.resetSpeechState()
            viewModel.stopSpeech()
            ocrViewModel.shutdown()
            
            viewModel.clearDetections()
            
            if let yoloProc = viewModel.yoloProcessor {
                yoloProc.reset()
            }
            
            viewModel.confidenceThreshold = 0.75
            viewModel.frameRate = 30
            viewModel.filterMode = "all"
            viewModel.currentZoomLevel = 1.0
            viewModel.isUltraWide = false
            
            LiDARManager.shared.stop()
            LiDARManager.shared.cleanupOldHistories(currentDetectionIds: Set())
            
            ocrViewModel.clearText()
        }
        
        viewModel.reinitialize()
        ocrViewModel.shutdown()
        // print("Basic reset completed")
    }
    
    private func playWelcomeMessage() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let selectedVoice = AVSpeechSynthesisVoice(identifier: viewModel.selectedVoiceIdentifier)
            let voiceName = selectedVoice?.name ?? "Selected"
            let utterance = AVSpeechUtterance(string: "Welcome to the real-time AI. iOS Detection app. \(voiceName) voice chosen")
            utterance.voice = selectedVoice
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
            performReset()
            SpeechManager.shared.resetSpeechState()
            mode = .home
        } else if newPhase == .inactive {
            viewModel.stopSession()
            ocrViewModel.stopSession()
        } else if newPhase == .active {
            performReset()
            SpeechManager.shared.resetSpeechState()
            
            if mode == .objectDetection {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    viewModel.reinitialize()
                    viewModel.startSession()
                }
            }
        }
    }
    
    private func switchToMode(_ newMode: AppMode) {
        // Ensure newMode is the AppMode enum expected by ResourceManager.switchToMode()
        resourceManager.switchToMode(newMode)
        
        // Convert AppMode to ContentView.Mode
        switch newMode {
        case .home:
            mode = .home
        case .objectDetection:
            mode = .objectDetection
        case .ocrEnglish:
            mode = .englishOCR
        case .ocrSpanish:
            mode = .spanishToEnglishOCR
        }
    }
}

#Preview {
    ContentView()
}
