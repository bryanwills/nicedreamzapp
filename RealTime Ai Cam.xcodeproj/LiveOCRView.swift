import SwiftUI
import AVFoundation

struct LiveOCRView: View {
    @StateObject var viewModel = LiveOCRViewModel()
    
    var body: some View {
        ZStack {
            // Camera preview fills entire screen
            CameraView(viewModel: viewModel.cameraViewModel)
                .ignoresSafeArea()
            
            // Overlay UI controls
            VStack {
                Spacer()
                
                // Recognized Text Display
                ScrollView {
                    Text(viewModel.recognizedText)
                        .padding()
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                        .padding(.horizontal)
                }
                .frame(maxHeight: 120)
                
                // Translated Text Display
                ScrollView {
                    Text(viewModel.translatedText)
                        .padding()
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                        .padding(.horizontal)
                }
                .frame(maxHeight: 120)
                .padding(.top, 4)
                
                // Buttons
                HStack(spacing: 20) {
                    Button(action: {
                        let textToSpeak = viewModel.recognizedText
                        let utterance = AVSpeechUtterance(string: textToSpeak)
                        let synthesizer = AVSpeechSynthesizer()
                        synthesizer.speak(utterance)
                    }) {
                        Label("Speak", systemImage: "speaker.wave.2.fill")
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(.ultraThinMaterial)
                            .cornerRadius(15)
                            .shadow(radius: 5)
                    }
                    
                    Button(action: {
                        UIPasteboard.general.string = viewModel.recognizedText
                    }) {
                        Label("Copy", systemImage: "doc.on.doc.fill")
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(.ultraThinMaterial)
                            .cornerRadius(15)
                            .shadow(radius: 5)
                    }
                    
                    Button(action: {
                        // Back action implementation depends on navigation management in parent view
                    }) {
                        Label("Back", systemImage: "arrow.backward")
                            .padding(.vertical, 10)
                            .padding(.horizontal, 20)
                            .background(.ultraThinMaterial)
                            .cornerRadius(15)
                            .shadow(radius: 5)
                    }
                }
                .foregroundColor(.primary)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .padding(.horizontal)
        }
    }
}

// Assume CameraView and LiveOCRViewModel are implemented elsewhere as per original code

