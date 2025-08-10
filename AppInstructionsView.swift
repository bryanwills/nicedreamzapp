// This file provides the missing AppInstructionsView for the project.
// It presents a simple set of usage instructions for the RealTime Ai Camera app.

import SwiftUI
import AVFoundation

struct AppInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("👋 Welcome to RealTime Ai Camera!")
                        .font(.largeTitle.bold())
                    
                    Button(action: playAudioInstructions) {
                        HStack {
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.title2)
                            Text("Play Complete Audio Tutorial")
                                .font(.headline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Play complete audio tutorial")
                    .accessibilityHint("Plays detailed voice instructions for using the app")

                    Text("Snap, Detect, Translate—All in Real Time!")
                        .font(.title2)
                        .padding(.bottom, 6)
                    
                    Text("🔒 100% Private · 📴 Works fully offline—even in ✈️ Airplane Mode · 🚀 Best-in-class AI, just for you.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 10)

                    Group {
                        Text("✨ What you can do:")
                            .font(.headline)
                        Text("📖 English OCR: Instantly read and hear English text from your camera.")
                        Text("🇲🇽Span🇺🇸Eng🌎Translate: Translate Spanish text to English—hear it spoken.")
                        Text("🐶 Object Detection: Spot objects and get audio feedback.")
                        HStack(alignment: .center, spacing: 8) {
                            ShadedEmoji(emoji: "🗣️", size: 22)
                            Text("Voice Picker: Pick your favorite voice for feedback.")
                        }
                        Text("🤏 Pinch-to-zoom: Use two fingers to zoom the camera in Spanish OCR or Object Detection.")
                        Text("🔄 Switch Camera: Use to swap front/rear cameras.")
                        Text("🌐 Wide/Ultra-wide: Use the grid button to toggle lenses (if available).")
                        Text("🔦 Torch: Tap the flashlight to adjust brightness.")
                        Text("💬 Overlay: Toggle text overlay with the speech bubble.")
                        HStack(alignment: .center, spacing: 8) {
                            ShadedEmoji(emoji: "🗣️", size: 22)
                            Text("Speak: Tap to hear the recognized or translated text.")
                        }
                        Text("📋 Copy: Tap to copy text to your history.")
                        Text("⚙️ Settings: Access settings and history.")
                    }
                    .font(.body)
                    .padding(.bottom, 4)

                    Divider().padding(.vertical, 6)

                    Group {
                        Text("🔧 Quick Tips:")
                            .font(.headline)
                        Text("🔄: Switch front/rear cameras.")
                        Text("🌐: Toggle wide/ultra-wide lens.")
                        Text("🔦: Adjust flashlight.")
                        Text("💬: Show/hide text overlay.")
                        HStack(alignment: .center, spacing: 8) {
                            ShadedEmoji(emoji: "🗣️", size: 22)
                            Text("Speak or stop speaking.")
                        }
                        Text("📋: Copy detected or translated text.")
                        Text("⚙️: Open settings and see history.")
                        Text("🤏: Pinch to zoom camera.")
                    }
                    .font(.body)
                    .padding(.bottom, 4)

                    Divider().padding(.vertical, 6)

                    Text("📷 Please allow camera access for best results!")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("Instructions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func playAudioInstructions() {
        let instructions = """
        Welcome to RealTime AI Camera. This app has three main modes:

        First, English Text to Speech. Point your camera at any English text, and the app will read it aloud automatically. Great for reading signs, documents, or menus.

        Second, Spanish to English Translation. Point your camera at Spanish text, and it will translate to English and speak it. Perfect for travel or learning.

        Third, Object Detection. The camera will identify objects around you and announce them. Helpful for navigation and understanding your environment.

        Navigation tips: All buttons have voice labels when using VoiceOver. Double-tap to activate any button. The app works completely offline for your privacy.

        In all camera modes, you can pinch to zoom, and use the flashlight button for better lighting. The back button is always available to return to the home screen.

        For best results, hold the phone steady and ensure good lighting when scanning text or objects.
        """

        let utterance = AVSpeechUtterance(string: instructions)
        utterance.rate = 0.45
        utterance.volume = 1.0

        let speechSynthesizer = AVSpeechSynthesizer()
        speechSynthesizer.speak(utterance)
    }
}
