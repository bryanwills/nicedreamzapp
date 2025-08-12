import SwiftUI
import AVFoundation

enum OCRMode {
    case english
    case spanishToEnglish
}

// Enhanced Camera Preview with zoom support
struct EnhancedCameraPreview: UIViewRepresentable {
    let onFrame: (CVPixelBuffer) -> Void
    let cameraManager: ZoomCameraManager
    var onCameraReady: ((CameraPreviewView) -> Void)? = nil
    @ObservedObject var viewModel: LiveOCRViewModel
    
    var onPinchBegan: (() -> Void)? = nil
    var onPinchEnded: (() -> Void)? = nil
    
    func makeUIView(context: Context) -> EnhancedCameraPreviewView {
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
    
    func updateUIView(_ uiView: EnhancedCameraPreviewView, context: Context) {
        if uiView.isUltraWide != viewModel.isUltraWide || uiView.cameraPosition != viewModel.cameraPosition {
            uiView.isUltraWide = viewModel.isUltraWide
            uiView.cameraPosition = viewModel.cameraPosition
            uiView.reconfigureCamera()
        }
    }
    
    static func dismantleUIView(_ uiView: EnhancedCameraPreviewView, coordinator: ()) {
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
    
    // Computed property for display text based on mode and translation state
    private var displayText: String {
        if ocrMode == .english {
            return viewModel.recognizedText
        } else {
            // For Spanish mode: show Spanish until translated, then show English
            return viewModel.isTranslated ? viewModel.translatedText : viewModel.recognizedText
        }
    }
    
    // Header text that changes based on state
    private var headerText: String {
        if ocrMode == .english {
            return "Detected"
        } else {
            return viewModel.isTranslated ? "English Translation" : "Spanish Detected"
        }
    }
    
    // Header icon that changes based on state
    private var headerIcon: String {
        if ocrMode == .english {
            return "text.viewfinder"
        } else {
            return viewModel.isTranslated ? "checkmark.circle.fill" : "text.viewfinder"
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full-screen camera preview
                EnhancedCameraPreview(
                    onFrame: { pixelBuffer in
                        if !viewModel.isPinching && !isTranslating {
                            viewModel.processFrame(pixelBuffer, mode: ocrMode)
                        }
                    },
                    cameraManager: viewModel.cameraManager,
                    onCameraReady: { cameraView in
                        self.cameraPreviewRef = cameraView
                    },
                    viewModel: viewModel,
                    onPinchBegan: { viewModel.isPinching = true },
                    onPinchEnded: { viewModel.isPinching = false }
                )
                .ignoresSafeArea()
                // Gradient overlays
                VStack {
                    LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.7), Color.clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 150)
                    .edgesIgnoringSafeArea(.top)
                    
                    Spacer()
                    
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 300)
                    .edgesIgnoringSafeArea(.bottom)
                }
                .ignoresSafeArea()
                
                // Top bar with back button and mode indicator
                VStack {
                    HStack {
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            viewModel.stopSpeaking()
                            viewModel.stopSession()
                            viewModel.clearText()
                            mode = .home
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 17, weight: .medium))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 30)
                                    .fill(.ultraThinMaterial.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 30)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.leading, 20)
                        .padding(.top, geometry.safeAreaInsets.top + 10)
                        
                        Spacer()
                        
                        Text(ocrMode == .english ? "English OCR" : "Span → Eng")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial.opacity(0.15))
                            )
                            .padding(.trailing, 20)
                            .padding(.top, geometry.safeAreaInsets.top + 10)
                    }
                    Spacer()
                }
                
                // Main content area
                VStack {
                    Spacer()
                    
                    // Text overlay - now clickable for Spanish mode when translated
                    if showTextOverlay && !displayText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: headerIcon)
                                    .font(.system(size: 14))
                                    .foregroundColor(viewModel.isTranslated ? .green : .white.opacity(0.7))
                                Text(headerText)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
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
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 120)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            viewModel.isTranslated ? Color.green.opacity(0.3) : Color.white.opacity(0.1),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .onTapGesture {
                            // Only show popup if Spanish mode and translated
                            if ocrMode == .spanishToEnglish && viewModel.isTranslated {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                showTranslationPopup = true
                            }
                        }
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(), value: showTextOverlay)
                    }
                    
                    // Bottom action buttons
                    HStack(spacing: 16) {
                        // Settings button
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showSettings = true
                            }
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 22))
                                .frame(width: 50, height: 50)
                                .background(Circle().fill(.ultraThinMaterial))
                                .foregroundStyle(.primary)
                        }
                        
                        // Torch button
                        TorchButton(
                            torchLevel: 0.0,
                            onLevelChanged: { level in
                                cameraPreviewRef?.setTorchLevel(level)
                            }
                        )
                        
                        Spacer()
                        
                        // Only show action buttons when there's text
                        if !viewModel.recognizedText.isEmpty {
                            // For Spanish mode: Translate button
                            if ocrMode == .spanishToEnglish && !viewModel.isTranslated {
                                Button(action: {
                                    isTranslating = true
                                    viewModel.translateSpanishText { success in
                                        isTranslating = false
                                    }
                                }) {
                                    Text("Translate")
                                        .font(.system(size: 16, weight: .medium))
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(Capsule().fill(Color.blue))
                                        .foregroundColor(.white)
                                }
                                .disabled(isTranslating)
                            }
                            
                            // Copy button (shows after translation in Spanish mode, always in English mode)
                            if ocrMode == .english || viewModel.isTranslated {
                                Button(action: {
                                    let textToCopy = ocrMode == .english ? viewModel.recognizedText : viewModel.translatedText
                                    viewModel.copyText(textToCopy)
                                }) {
                                    Image(systemName: "doc.on.doc.fill")
                                        .font(.system(size: 22))
                                        .frame(width: 50, height: 50)
                                        .background(Circle().fill(.ultraThinMaterial))
                                        .foregroundStyle(.primary)
                                }
                            }
                            
                            // Speak button - single toggle
                            Button(action: {
                                if isSpeaking {
                                    viewModel.stopSpeaking()
                                    isSpeaking = false
                                } else {
                                    let textToSpeak = ocrMode == .english ? viewModel.recognizedText : 
                                                     (viewModel.isTranslated ? viewModel.translatedText : viewModel.recognizedText)
                                    
                                    // Translate first if needed
                                    if ocrMode == .spanishToEnglish && !viewModel.isTranslated {
                                        viewModel.translateSpanishText { success in
                                            if success {
                                                viewModel.speak(text: viewModel.translatedText, voiceIdentifier: selectedVoiceIdentifier) {
                                                    isSpeaking = false
                                                }
                                                isSpeaking = true
                                            }
                                        }
                                    } else {
                                        viewModel.speak(text: textToSpeak, voiceIdentifier: selectedVoiceIdentifier) {
                                            isSpeaking = false
                                        }
                                        isSpeaking = true
                                    }
                                }
                            }) {
                                Text("🗣️")
                                    .font(.system(size: 26))
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle().fill(isSpeaking ? Color.green : Color.gray.opacity(0.3))
                                    )
                                    .scaleEffect(isSpeaking ? 1.1 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: isSpeaking)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
                
                // Translation actions popup (Spanish mode only)
                if showTranslationPopup && ocrMode == .spanishToEnglish {
                    TranslationActionsPopup(
                        isPresented: $showTranslationPopup,
                        translatedText: viewModel.translatedText,
                        onCopy: {
                            viewModel.copyText(viewModel.translatedText)
                        },
                        onContinue: {
                            showTranslationPopup = false
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
        }
        .onDisappear {
            viewModel.stopSession()
            viewModel.clearText()
            viewModel.resetTranslation()
            isSpeaking = false
            cameraPreviewRef?.setTorchLevel(0)
        }
        .preferredColorScheme(.dark)
    }
}
