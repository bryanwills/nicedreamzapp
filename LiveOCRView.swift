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

    // MARK: - New callbacks for pinch gesture begin and end
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
        
        // MARK: - Assign new pinch gesture callbacks
        view.onPinchBegan = onPinchBegan
        view.onPinchEnded = onPinchEnded
        
        return view
    }

    func updateUIView(_ uiView: EnhancedCameraPreviewView, context: Context) {
        // Update camera settings if changed
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

    // MARK: - New optional callbacks for pinch gesture events
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
            // MARK: - Call onPinchBegan callback
            onPinchBegan?()
        case .changed:
            cameraManager?.handlePinchGesture(gesture.scale)
        case .ended, .cancelled:
            // MARK: - Call onPinchEnded callback
            onPinchEnded?()
        default:
            break
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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Full-screen camera preview with zoom
                EnhancedCameraPreview(
                    onFrame: { pixelBuffer in
                        if !viewModel.isPinching {
                            viewModel.processFrame(pixelBuffer, mode: ocrMode)
                        }
                    },
                    cameraManager: viewModel.cameraManager,
                    onCameraReady: { cameraView in
                        self.cameraPreviewRef = cameraView
                    },
                    viewModel: viewModel,
                    onPinchBegan: { viewModel.isPinching = true },
                    onPinchEnded: { viewModel.isPinching = false },
                )
                .ignoresSafeArea(.all)

                // Zoom indicator
                if viewModel.cameraManager.currentZoomLevel > 1.05 {
                    VStack {
                        Text(String(format: "%.1fx", viewModel.cameraManager.currentZoomLevel))
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
                    .animation(.easeInOut(duration: 0.2), value: viewModel.cameraManager.currentZoomLevel)
                }

                // Pinch to zoom instruction
                VStack {
                    Text("Pinch to zoom")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .opacity(0.2)
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            LinearGradient(
                                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ),
                                            lineWidth: 0.5
                                        )
                                )
                        )
                        .shadow(color: .black.opacity(0.2), radius: 4)
                        .padding(.top, geometry.safeAreaInsets.top + 20)
                    Spacer()
                }

                // Gradient overlay for better text visibility
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

                // Top bar
                VStack {
                    HStack {
                        Button(action: {
                            // The back button must immediately stop all processing (speech, OCR, camera) and switch mode instantly, overruling all background work for fast UI.
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()

                            // FORCE STOP everything synchronously
                            viewModel.stopSpeaking()
                            viewModel.stopSession()
                            viewModel.clearText()

                            // Set mode to home immediately
                            mode = .home
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .symbolRenderingMode(.palette)
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
                        .accessibilityLabel("Back to home")
                        .accessibilityHint("Returns to main menu and stops camera")
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

                VStack {
                    Spacer()

                    // Text overlay (can be toggled)
                    if showTextOverlay {
                        VStack(spacing: 16) {
                            let displayText = ocrMode == .english ? viewModel.recognizedText : viewModel.translatedText
                            let headerText = ocrMode == .english ? "Detected" : "English Translation"
                            let headerIcon = ocrMode == .english ? "text.viewfinder" : "translate"

                            if !displayText.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: headerIcon)
                                            .symbolRenderingMode(.palette)
                                            .font(.system(size: 14))
                                        Text(headerText)
                                            .font(.system(size: 14, weight: .medium))
                                        Spacer()
                                    }
                                    .foregroundColor(.white.opacity(0.7))

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
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 20)
                        .animation(.spring(), value: showTextOverlay)
                    }

                    // Bottom action buttons
                    HStack(spacing: 10) {  // Reduced spacing to fit all buttons
                        // Settings button
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showSettings = true
                            }
                        }) {
                            Image(systemName: "gearshape.fill")
                                .symbolRenderingMode(.palette)
                                .font(.system(size: 20))
                                .frame(width: 48, height: 48)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial.opacity(0.15))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityHint("Opens settings and text history")
                        
                        // Torch button
                        TorchButton(
                            torchLevel: 0.0,
                            onLevelChanged: { level in
                                cameraPreviewRef?.setTorchLevel(level)
                            }
                        )
                        
                        // Wide angle toggle button
                        if viewModel.cameraPosition == .back {
                            Button(action: {
                                viewModel.toggleCameraZoom()
                            }) {
                                Image(systemName: "rectangle.3.offgrid")
                                    .symbolRenderingMode(.palette)
                                    .font(.system(size: 20))
                                    .frame(width: 48, height: 48)
                                    .background(
                                        Circle()
                                            .fill(viewModel.isUltraWide ? Color.cyan.opacity(0.15) : Color.clear)
                                            .overlay(
                                                Circle()
                                                    .stroke(viewModel.isUltraWide ? Color.cyan : Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                                    .foregroundStyle(viewModel.isUltraWide ? .cyan : .primary)
                            }
                        }

                        Spacer()

                        // Toggle text overlay
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showTextOverlay.toggle()
                            }
                        }) {
                            Image(systemName: showTextOverlay ? "text.bubble.fill" : "text.bubble")
                                .symbolRenderingMode(.palette)
                                .font(.system(size: 20))
                                .frame(width: 48, height: 48)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial.opacity(0.15))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel(showTextOverlay ? "Hide text overlay" : "Show text overlay")
                        .accessibilityHint("Toggles visual text display on screen")

                        // Accessibility value for speak/copy buttons: defined here once
                        let displayText = ocrMode == .english ? viewModel.recognizedText : viewModel.translatedText

                        // Speak button
                        Button(action: {
                            let textToSpeak = ocrMode == .english ? viewModel.recognizedText : viewModel.translatedText
                            if isSpeaking {
                                viewModel.stopSpeaking()
                                isSpeaking = false
                            } else {
                                viewModel.speak(text: textToSpeak, voiceIdentifier: selectedVoiceIdentifier) {
                                    isSpeaking = false
                                }
                                isSpeaking = true
                            }
                        }) {
                            Text("🗣️")
                                .font(.system(size: 22, weight: .medium))
                                .frame(width: 36, height: 36)
                                .background(
                                    isSpeaking
                                        ? Circle().fill(Color.green.opacity(0.85))
                                        : Circle().fill(Color.white.opacity(0.65))
                                )
                                .foregroundColor(.black)
                        }
                        .disabled(viewModel.recognizedText.isEmpty && viewModel.translatedText.isEmpty)
                        .opacity((viewModel.recognizedText.isEmpty && viewModel.translatedText.isEmpty) ? 0.5 : 1)
                        .accessibilityLabel(isSpeaking ? "Stop speaking" : "Speak detected text")
                        .accessibilityHint("Reads the recognized or translated text aloud")
                        .accessibilityValue(displayText.isEmpty ? "No text detected" : "Text ready to speak")

                        // Copy button
                        Button(action: {
                            let textToCopy = ocrMode == .english ? viewModel.recognizedText : viewModel.translatedText
                            viewModel.copyText(textToCopy)
                        }) {
                            Image(systemName: "doc.on.doc.fill")
                                .symbolRenderingMode(.palette)
                                .font(.system(size: 20))
                                .frame(width: 48, height: 48)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial.opacity(0.15))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .foregroundStyle(.primary)
                        }
                        .disabled(viewModel.recognizedText.isEmpty && viewModel.translatedText.isEmpty)
                        .opacity((viewModel.recognizedText.isEmpty && viewModel.translatedText.isEmpty) ? 0.5 : 1)
                        .accessibilityLabel("Copy text")
                        .accessibilityHint("Copies detected text to clipboard")
                        .accessibilityValue(displayText.isEmpty ? "No text to copy" : "Text ready to copy")

                        // Clear button
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                viewModel.stopSpeaking()
                                viewModel.clearText()
                                isSpeaking = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .font(.system(size: 20))
                                .frame(width: 48, height: 48)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial.opacity(0.15))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .foregroundStyle(.primary)
                        }
                        .disabled(viewModel.recognizedText.isEmpty && viewModel.translatedText.isEmpty)
                        .opacity((viewModel.recognizedText.isEmpty && viewModel.translatedText.isEmpty) ? 0.5 : 1)
                        .accessibilityLabel("Clear text")
                        .accessibilityHint("Clears detected text and stops speaking")
                    }
                    .padding(.horizontal, 20)  // Good padding from screen edges
                    .padding(.bottom, 30)
                }

                // Settings overlay
                if showSettings {
                    SettingsOverlayView(
                        viewModel: CameraViewModel(), // Pass a dummy for OCR mode
                        isPresented: $showSettings,
                        mode: ocrMode == .english ? .englishOCR : .spanishToEnglishOCR
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .onAppear {
                viewModel.startSession()
            }
            .onDisappear {
                viewModel.stopSession()
                viewModel.clearText()
                isSpeaking = false
                cameraPreviewRef?.setTorchLevel(0)
            }
            .preferredColorScheme(.dark)
        }
    }
}

