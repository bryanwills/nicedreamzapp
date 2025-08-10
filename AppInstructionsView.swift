// This file provides the missing AppInstructionsView for the project.
// It presents a simple set of usage instructions for the RealTime Ai Camera app.

import SwiftUI

struct AppInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Getting Started")
                        .font(.largeTitle.bold())
                        .padding(.bottom, 4)
                    Text("Welcome to RealTime Ai Camera!")
                        .font(.title2)
                        .padding(.bottom, 2)
                    Text("This app lets you:\n• Detect and translate English and Spanish text using OCR\n• Detect objects in real time with your camera\n• Use voice feedback with customizable voices\n• Adjust detection confidence and torch level\n• Switch between Indoor/Outdoor filter modes")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Divider().padding(.vertical, 8)
                    
                    Group {
                        Text("Main Features")
                            .font(.headline)
                        Text("- \"English Text (OCR)\": Read and speak out English text from the camera live view.\n- \"SpanEng Translate\": Instantly translate Spanish text to English, with spoken output.\n- \"Object Detection\": Recognizes everyday items live and gives audio feedback.\n- \"Voice Picker\": Choose your preferred system voice for feedback on the home screen.")
                    }
                    
                    Divider().padding(.vertical, 8)

                    Group {
                        Text("Controls & Tips")
                            .font(.headline)
                        Text("• On object detection, tap the lightning bolt for torch presets.\n• Use the ‘eye’ slider to adjust confidence threshold.\n• Pinch to zoom in object detection mode.\n• Use the segment control to filter Indoor/Outdoor detections.\n• Tap the back button to return home.")
                    }
                    
                    Divider().padding(.vertical, 8)
                    
                    Text("For the best results, ensure you allow camera access when prompted.")
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
}
