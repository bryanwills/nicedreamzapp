import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
    @ObservedObject var viewModel: CameraViewModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        // Configure preview layer
        viewModel.previewLayer.videoGravity = .resizeAspectFill
        viewModel.previewLayer.frame = view.bounds
        view.layer.addSublayer(viewModel.previewLayer)
        
        // Start camera session
        DispatchQueue.global(qos: .userInitiated).async {
            viewModel.startSession()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame when view size changes
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            viewModel.previewLayer.frame = uiView.bounds
            CATransaction.commit()
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        // View is being removed
    }
}
