import SwiftUI
import AVFoundation

struct HomeView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Binding var animationState: ContentView.AnimationState
    @Binding var mode: ContentView.Mode
    @State private var showInstructions = false
    
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
                Spacer(minLength: 80)
                VStack(spacing: 12) {
                    HeadingView(animateIn: animationState.heading)
                    Spacer(minLength: 30)
                    GeometryReader { geometry in
                        VStack(spacing: 18) {
                            englishOCRButton
                            spanishOCRButton
                            objectDetectionButton
                        }
                    }
                    .frame(height: 220)
                    Spacer(minLength: 25)
                    voicePicker
                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                Spacer(minLength: 50)
            }
            
            infoButton
        }
        .sheet(isPresented: $showInstructions) {
            AppInstructionsView(selectedVoiceIdentifier: viewModel.selectedVoiceIdentifier)
                .onAppear {
                    if buttonDebouncer.canPress() {
                        viewModel.pauseCameraAndProcessing()
                        print("Instructions opened with voice: \(viewModel.selectedVoiceIdentifier)")
                    }
                }
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
    
    // MARK: - View Components
    
    private var splashBackground: some View {
        GeometryReader { geometry in
            Image("SplashScreen")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea(.all, edges: .all)
        }
    }
    
    private var englishOCRButton: some View {
        Button(action: {
            guard buttonDebouncer.canPress() else { return }
            onEnglishOCR()
        }) {
            HStack(spacing: 4) {
                Text("📖").font(.system(size: 34))
                OutlinedText(text: "Eng Text2Speech", fontSize: 20)
                ShadedEmoji(emoji: "🗣️", size: 29)
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
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
    }
    
    private var spanishOCRButton: some View {
        Button(action: {
            guard buttonDebouncer.canPress() else { return }
            onSpanishOCR()
        }) {
            HStack(spacing: 2) {
                Text("🇲🇽").font(.system(size: 31))
                OutlinedText(text: "Span", fontSize: 18)
                Text("🇺🇸").font(.system(size: 31))
                OutlinedText(text: "Eng", fontSize: 18)
                Text("🌎").font(.system(size: 31))
                OutlinedText(text: "Translate", fontSize: 18)
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
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
    }
    
    private var objectDetectionButton: some View {
        Button(action: {
            guard buttonDebouncer.canPress() else { return }
            onObjectDetection()
        }) {
            HStack(spacing: 4) {
                Text("🐶").font(.system(size: 35))
                OutlinedText(text: "Object Detection", fontSize: 20)
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
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
    
    private var voicePicker: some View {
        AnimatedVoicePicker(
            viewModel: viewModel,
            animateIn: animationState.picker,
            onVoiceChange: onVoiceChange,
            speechSynthesizer: speechSynthesizer
        )
        .onTapGesture {
            _ = buttonDebouncer.canPress()
        }
    }
    
    private var infoButton: some View {
        Button(action: {
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
    
    // MARK: - Helper Methods
    
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
