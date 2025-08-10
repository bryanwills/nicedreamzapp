import AVFoundation

class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    private var synthesizer = AVSpeechSynthesizer()

    func speakInstructions(supportsLiDAR: Bool) {
        var instructions = [
            "Welcome to RealTime AI Camera.",
            "Object Detection mode detects and labels up to six hundred and one objects in real time.",
            "English OCR mode reads printed English text aloud.",
            "Spanish to English mode translates printed Spanish text into English and reads it aloud."
        ]

        if supportsLiDAR {
            instructions.append(
                "Tap the white ruler icon — it turns green when active — to enable LiDAR Distance Assist. This measures object distance, filters far-away objects, and stabilizes bounding boxes."
            )
        } else {
            instructions.append(
                "LiDAR Distance Assist is available only on LiDAR-equipped iPhone and iPad Pro models."
            )
        }

        instructions.append(contentsOf: [
            "You can switch between front and back cameras.",
            "Toggle wide and ultra-wide lenses.",
            "Adjust torch brightness between twenty five, fifty, seventy five, and one hundred percent.",
            "Pinch the screen to zoom in or out.",
            "Toggle text overlay on or off.",
            "Speak detected or translated text aloud.",
            "Copy text to the history for later use.",
            "Tap 'Play Complete Audio Tutorial' any time to hear these instructions again."
        ])

        speak(instructions.joined(separator: " "))
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
}
