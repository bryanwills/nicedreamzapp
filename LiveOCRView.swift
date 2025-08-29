import AVFoundation
import SwiftUI

enum OCRMode {
    case english
    case spanishToEnglish
}

// Enhanced Camera Preview with zoom support
struct EnhancedCameraPreview: UIViewRepresentable {
    let onFrame: (CVPixelBuffer) -> Void
    let cameraManager: ZoomCameraManager
    var onCameraReady: ((CameraPreviewView) -> Void)?
    @ObservedObject var viewModel: LiveOCRViewModel

    var onPinchBegan: (() -> Void)?
    var onPinchEnded: (() -> Void)?

    func makeUIView(context _: Context) -> EnhancedCameraPreviewView {
        let view = EnhancedCameraPreviewView()
        view.onFrame = onFrame
        view.cameraManager = cameraManager
        view.isUltraWide = viewModel.isUltraWide
        view.cameraPosition = viewModel.cameraPosition
        view.onCameraReady = { device in
            cameraManager.setup(device: device)
            onCameraReady?(view)
        }
        view.setupGestures()
        view.onPinchBegan = onPinchBegan
        view.onPinchEnded = onPinchEnded
        return view
    }

    func updateUIView(_ uiView: EnhancedCameraPreviewView, context _: Context) {
        if uiView.isUltraWide != viewModel.isUltraWide || uiView.cameraPosition != viewModel.cameraPosition {
            uiView.isUltraWide = viewModel.isUltraWide
            uiView.cameraPosition = viewModel.cameraPosition
            uiView.reconfigureCamera()
        }
    }

    static func dismantleUIView(_ uiView: EnhancedCameraPreviewView, coordinator _: ()) {
        uiView.stopSession()
    }
}

// Enhanced CameraPreviewView with gesture support
class EnhancedCameraPreviewView: CameraPreviewView {
    var cameraManager: ZoomCameraManager?
    var onPinchBegan: (() -> Void)?
    var onPinchEnded: (() -> Void)?

    func setupGestures() {
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchGesture)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            cameraManager?.setPinchGestureStartZoom()
            onPinchBegan?()
        case .changed:
            cameraManager?.handlePinchGesture(gesture.scale)
        case .ended, .cancelled:
            onPinchEnded?()
        default:
            break
        }
    }
}

// Liquid Glass Popup for Translation Actions
struct TranslationActionsPopup: View {
    @Binding var isPresented: Bool
    let translatedText: String
    let onCopy: () -> Void
    let onContinue: () -> Void
    let onNewScan: () -> Void

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        onContinue()
                    }
                }

            // Glass popup
            VStack(spacing: 20) {
                Text("Translation Ready")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                VStack(spacing: 12) {
                    // Copy button
                    Button(action: {
                        onCopy()
                        withAnimation(.spring(response: 0.3)) {
                            isPresented = false
                        }
                    }) {
                        HStack {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 18))
                            Text("Copy Translation")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.blue.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                                )
                        )
                    }

                    // Continue Reading button
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            onContinue()
                        }
                    }) {
                        HStack {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 18))
                            Text("Continue Reading")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.green.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.green.opacity(0.5), lineWidth: 1)
                                )
                        )
                    }

                    // New Scan button
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            onNewScan()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 18))
                            Text("New Scan")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.orange.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                                )
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .scaleEffect(isPresented ? 1 : 0.9)
            .opacity(isPresented ? 1 : 0)
        }
    }
}

struct LiveOCRView: View {
    @Binding var mode: ContentView.Mode
    @StateObject private var viewModel = LiveOCRViewModel()
    let ocrMode: OCRMode
    let selectedVoiceIdentifier: String

    @State private var showTextOverlay = true
    @State private var isSpeaking = false
    @State private var showSettings = false
    @State private var cameraPreviewRef: CameraPreviewView?
    @State private var showTranslationPopup = false
    @State private var isTranslating = false
    @State private var isWideScreen = false

    @State private var showTorchPresets = false

    @StateObject private var buttonDebouncer = ButtonPressDebouncer() // Debouncer to avoid rapid multiple presses

    // Computed property for display text
    private var displayText: String {
        if ocrMode == .english {
            viewModel.recognizedText
        } else {
            viewModel.isTranslated ? viewModel.translatedText : viewModel.recognizedText
        }
    }

    // Header text that changes based on state
    private var headerText: String {
        if ocrMode == .english {
            "Detected"
        } else {
            viewModel.isTranslated ? "Translation" : "Spanish Text"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let isVerySmallScreen = screenWidth <= 375
            let buttonSize: CGFloat = isVerySmallScreen ? 48 : 56
            let horizontalPadding: CGFloat = isVerySmallScreen ? 16 : 20

            ZStack {
                // Full-screen camera preview
                EnhancedCameraPreview(
                    onFrame: { pixelBuffer in
                        if !viewModel.isPinching, !isTranslating {
                            viewModel.processFrame(pixelBuffer, mode: ocrMode)
                        }
                    },
                    cameraManager: viewModel.cameraManager,
                    onCameraReady: { cameraView in
                        cameraPreviewRef = cameraView
                    },
                    viewModel: viewModel,
                    onPinchBegan: { viewModel.isPinching = true },
                    onPinchEnded: { viewModel.isPinching = false }
                )
                .ignoresSafeArea()

                // Gradient overlays
                VStack {
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .ignoresSafeArea()

                    Spacer()

                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.7)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 250)
                    .ignoresSafeArea()
                }

                // Top bar - FIXED VERSION
                VStack {
                    HStack {
                        // Back button with debouncer usage and updated style
                        Button(action: {
                            if buttonDebouncer.canPress() {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()

                                viewModel.stopSpeaking()
                                viewModel.stopSession()
                                viewModel.clearText()
                                mode = .home
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Back")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.85)
                            )
                        }
                        .padding(.leading, max(geometry.safeAreaInsets.leading + 16, isVerySmallScreen ? 8 : 20))

                        Spacer()

                        // Mode indicator - FIXED with proper safe area handling
                        Text(ocrMode == .english ? "English" : "Span → Eng")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial.opacity(0.9))
                            )
                            .padding(.trailing, max(geometry.safeAreaInsets.trailing + 16, isVerySmallScreen ? 8 : 20))
                    }
                    .padding(.top, geometry.safeAreaInsets.top + 10)

                    Spacer()
                }

                // Main content area
                VStack {
                    Spacer()

                    // Text overlay - clickable when translated
                    if showTextOverlay, !displayText.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Circle()
                                    .fill(viewModel.isTranslated ? Color.green : Color.blue)
                                    .frame(width: 8, height: 8)
                                Text(headerText)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                                if isTranslating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                            }

                            ScrollView {
                                Text(displayText)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 100)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial.opacity(0.95))
                        )
                        .onTapGesture {
                            if ocrMode == .spanishToEnglish, viewModel.isTranslated {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                showTranslationPopup = true
                            }
                        }
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Bottom action buttons - fixed layout as per instructions
                    HStack {
                        // Settings button with debouncer
                        Button(action: {
                            if buttonDebouncer.canPress() {
                                withAnimation(.spring(response: 0.3)) {
                                    showSettings = true
                                }
                            }
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 22))
                                .frame(width: buttonSize, height: buttonSize)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial.opacity(0.95))
                                )
                                .foregroundStyle(.white)
                        }
                        Spacer(minLength: 0)

                        // Torch button with overlay for presets and debouncer
                        ZStack {
                            Button(action: {
                                if buttonDebouncer.canPress() {
                                    if viewModel.torchLevel > 0 {
                                        viewModel.handleToggleTorch(level: 0.0)
                                        showTorchPresets = false
                                    } else {
                                        showTorchPresets = true
                                    }
                                }
                            }) {
                                Image(systemName: viewModel.torchLevel > 0 ? "flashlight.on.fill" : "flashlight.off.fill")
                                    .font(.system(size: 22))
                                    .frame(width: buttonSize, height: buttonSize)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial.opacity(0.95))
                                    )
                                    .foregroundStyle(viewModel.torchLevel > 0 ? Color.yellow : Color.white)
                            }
                            .overlay(
                                Group {
                                    if showTorchPresets {
                                        VStack(spacing: 8) {
                                            ForEach([100, 75, 50, 25], id: \.self) { percentage in
                                                Button(action: {
                                                    let level = Float(percentage) / 100.0
                                                    viewModel.handleToggleTorch(level: level)
                                                    showTorchPresets = false
                                                }) {
                                                    Text("\(percentage)%")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundColor(.white)
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
                                },
                                alignment: .top
                            )
                        }
                        Spacer(minLength: 0)

                        // Wide Screen Toggle button with debouncer
                        Button(action: {
                            if buttonDebouncer.canPress() {
                                viewModel.handleToggleCameraZoom()
                            }
                        }) {
                            Image(systemName: "rectangle.3.offgrid")
                                .font(.system(size: 22))
                                .frame(width: buttonSize, height: buttonSize)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial.opacity(0.95))
                                )
                                .foregroundStyle(viewModel.isUltraWide ? Color.cyan : Color.white)
                        }
                        Spacer(minLength: 0)

                        // Flip Camera button with debouncer
                        Button(action: {
                            if buttonDebouncer.canPress() {
                                viewModel.handleFlipCamera()
                            }
                        }) {
                            Image(systemName: "camera.rotate")
                                .font(.system(size: 22))
                                .frame(width: buttonSize, height: buttonSize)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial.opacity(0.95))
                                )
                                .foregroundStyle(.white)
                        }
                        Spacer(minLength: 0)

                        // Translate or Copy button (always present) with debouncer
                        Group {
                            if ocrMode == .spanishToEnglish, !viewModel.isTranslated {
                                Button(action: {
                                    if buttonDebouncer.canPress() {
                                        isTranslating = true
                                        viewModel.translateSpanishText { success in
                                            isTranslating = false
                                            if success {
                                                let feedback = UINotificationFeedbackGenerator()
                                                feedback.notificationOccurred(.success)
                                            }
                                        }
                                    }
                                }) {
                                    Image(systemName: "character.book.closed.fill")
                                        .font(.system(size: 22))
                                        .frame(width: buttonSize, height: buttonSize)
                                        .background(
                                            Circle()
                                                .fill(.ultraThinMaterial.opacity(0.95))
                                        )
                                        .foregroundStyle(.white)
                                }
                                .disabled(isTranslating)
                                .opacity(isTranslating ? 0.6 : 1)
                            } else {
                                Button(action: {
                                    if buttonDebouncer.canPress() {
                                        let textToCopy = ocrMode == .english ? viewModel.recognizedText : viewModel.translatedText
                                        viewModel.copyText(textToCopy)

                                        let feedback = UINotificationFeedbackGenerator()
                                        feedback.notificationOccurred(.success)
                                    }
                                }) {
                                    Image(systemName: "doc.on.doc.fill")
                                        .font(.system(size: 22))
                                        .frame(width: buttonSize, height: buttonSize)
                                        .background(
                                            Circle()
                                                .fill(.ultraThinMaterial.opacity(0.95))
                                        )
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        Spacer(minLength: 0)

                        // Speak button with debouncer
                        Button(action: {
                            if buttonDebouncer.canPress() {
                                if isSpeaking {
                                    viewModel.stopSpeaking()
                                    isSpeaking = false
                                } else {
                                    // For Spanish mode, translate first if needed
                                    if ocrMode == .spanishToEnglish, !viewModel.isTranslated {
                                        isTranslating = true
                                        viewModel.translateSpanishText { success in
                                            isTranslating = false
                                            if success {
                                                viewModel.speak(text: viewModel.translatedText, voiceIdentifier: selectedVoiceIdentifier) {
                                                    isSpeaking = false
                                                }
                                                isSpeaking = true
                                            }
                                        }
                                    } else {
                                        let textToSpeak = ocrMode == .english ? viewModel.recognizedText : viewModel.translatedText
                                        viewModel.speak(text: textToSpeak, voiceIdentifier: selectedVoiceIdentifier) {
                                            isSpeaking = false
                                        }
                                        isSpeaking = true
                                    }
                                }
                            }
                        }) {
                            Image(systemName: "person.wave.2.fill")
                                .font(.system(size: 22))
                                .frame(width: buttonSize, height: buttonSize)
                                .background(
                                    Circle()
                                        .fill(isSpeaking ? Color.green : Color.gray.opacity(0.5))
                                )
                                .foregroundStyle(.white)
                        }
                        .scaleEffect(isSpeaking ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isSpeaking)
                        Spacer(minLength: 0)

                        // Reset (Clear) button with debouncer
                        Button(action: {
                            if buttonDebouncer.canPress() {
                                withAnimation(.spring(response: 0.3)) {
                                    viewModel.stopSpeaking()
                                    viewModel.clearText()
                                    viewModel.resetTranslation()
                                    isSpeaking = false
                                }
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 22))
                                .frame(width: buttonSize, height: buttonSize)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial.opacity(0.95))
                                )
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalPadding + max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing))
                    .padding(.bottom, 30)
                }

                // Translation popup (Spanish mode only)
                if showTranslationPopup, ocrMode == .spanishToEnglish {
                    TranslationActionsPopup(
                        isPresented: $showTranslationPopup,
                        translatedText: viewModel.translatedText,
                        onCopy: {
                            viewModel.copyText(viewModel.translatedText)
                            viewModel.continueReading()
                        },
                        onContinue: {
                            showTranslationPopup = false
                            viewModel.continueReading()
                        },
                        onNewScan: {
                            showTranslationPopup = false
                            viewModel.clearText()
                            viewModel.resetTranslation()
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(100)
                }

                // Settings overlay
                if showSettings {
                    SettingsOverlayView(
                        viewModel: CameraViewModel(),
                        isPresented: $showSettings,
                        mode: ocrMode == .english ? .englishOCR : .spanishToEnglishOCR
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .onAppear {
            viewModel.startSession()
            // Sync torchLevel to 0 initially
            // torchLevel is now managed by viewModel
        }
        .onDisappear {
            viewModel.stopSession()
            viewModel.clearText()
            viewModel.resetTranslation()
            isSpeaking = false
            // Turn off torch when leaving the view (matches user intent)
            viewModel.handleToggleTorch(level: 0)
        }
        .preferredColorScheme(.dark)
    }
}
