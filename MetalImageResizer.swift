import Foundation
import CoreVideo
import Metal
import MetalKit
import Accelerate

class MetalImageResizer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let letterboxPipelineState: MTLComputePipelineState
    private let rotatePipelineState: MTLComputePipelineState
    private let textureCache: CVMetalTextureCache
    
    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        // Create texture cache
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard let textureCache = cache else {
            return nil
        }
        self.textureCache = textureCache
        
        // Simple letterbox kernel
        let letterboxKernel = """
        #include <metal_stdlib>
        using namespace metal;
        
        kernel void letterboxResize(
            texture2d<float, access::read> inTexture [[texture(0)]],
            texture2d<float, access::write> outTexture [[texture(1)]],
            constant float2 &scale [[buffer(0)]],
            constant float2 &offset [[buffer(1)]],
            uint2 gid [[thread_position_in_grid]])
        {
            if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
                return;
            }
            
            // Calculate source position
            float2 srcPos = (float2(gid) - offset) / scale;
            
            // Check bounds
            if (srcPos.x < 0 || srcPos.y < 0 || 
                srcPos.x >= float(inTexture.get_width()) || 
                srcPos.y >= float(inTexture.get_height())) {
                // Black padding
                outTexture.write(float4(0.0, 0.0, 0.0, 1.0), gid);
                return;
            }
            
            // Read nearest pixel
            uint2 srcCoord = uint2(srcPos);
            float4 color = inTexture.read(srcCoord);
            
            // BGRA to RGB
            outTexture.write(float4(color.b, color.g, color.r, color.a), gid);
        }
        """
        
        // Rotation kernel for portrait mode
        let rotateKernel = """
        #include <metal_stdlib>
        using namespace metal;
        
        kernel void rotate90(texture2d<float, access::read> inTexture [[texture(0)]],
                            texture2d<float, access::write> outTexture [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
                return;
            }
            
            // Rotate 90 degrees clockwise: new_x = old_y, new_y = width - old_x - 1
            uint2 inCoord = uint2(gid.y, inTexture.get_width() - gid.x - 1);
            
            float4 color = inTexture.read(inCoord);
            // Keep BGRA format for now
            outTexture.write(color, gid);
        }
        """
        
        do {
            let library = try device.makeLibrary(source: letterboxKernel + "\n" + rotateKernel, options: nil)
            guard let letterboxFunction = library.makeFunction(name: "letterboxResize"),
                  let rotateFunction = library.makeFunction(name: "rotate90") else {
                return nil
            }
            self.letterboxPipelineState = try device.makeComputePipelineState(function: letterboxFunction)
            self.rotatePipelineState = try device.makeComputePipelineState(function: rotateFunction)
        } catch {
            return nil
        }
    }
    
    func resize(_ pixelBuffer: CVPixelBuffer, isPortrait: Bool) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Enable rotation for portrait mode
        var shouldRotate = isPortrait && width > height
        
        // Additional check for mismatch
        if (isPortrait && width > height) || (!isPortrait && height > width) {
            shouldRotate = true  // Force rotation if dimensions don't match expected orientation
        }
        
        // Calculate letterbox parameters
        let targetSize: Float = 640.0
        let scale: Float
        let padX: Int
        let padY: Int
        
        if shouldRotate {
            // After rotation, dimensions swap
            scale = min(targetSize / Float(height), targetSize / Float(width))
            let scaledWidth = Int(Float(height) * scale)
            let scaledHeight = Int(Float(width) * scale)
            padX = (640 - scaledWidth) / 2
            padY = (640 - scaledHeight) / 2
        } else {
            scale = min(targetSize / Float(width), targetSize / Float(height))
            let scaledWidth = Int(Float(width) * scale)
            let scaledHeight = Int(Float(height) * scale)
            padX = (640 - scaledWidth) / 2
            padY = (640 - scaledHeight) / 2
        }
        
        // Store info
        UserDefaults.standard.set(scale, forKey: "letterbox_scale")
        UserDefaults.standard.set(padX, forKey: "letterbox_padX")
        UserDefaults.standard.set(padY, forKey: "letterbox_padY")
        UserDefaults.standard.set(shouldRotate ? height : width, forKey: "original_width")
        UserDefaults.standard.set(shouldRotate ? width : height, forKey: "original_height")
        UserDefaults.standard.set(shouldRotate, forKey: "was_rotated")
        
        // Create textures
        guard let inputTexture = createTexture(from: pixelBuffer) else {
            return nil
        }
        
        guard let outputPixelBuffer = createPixelBuffer(width: 640, height: 640),
              let outputTexture = createTexture(from: outputPixelBuffer) else {
            return nil
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }
        
        // Process texture (rotate if needed)
        let processedTexture: MTLTexture
        
        if shouldRotate {
            // Create intermediate texture for rotation
            let rotatedDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: height,  // Swapped dimensions
                height: width,
                mipmapped: false
            )
            rotatedDesc.usage = [.shaderRead, .shaderWrite]
            
            guard let rotatedTexture = device.makeTexture(descriptor: rotatedDesc),
                  let rotateEncoder = commandBuffer.makeComputeCommandEncoder() else {
                return nil
            }
            
            // Rotate the input
            rotateEncoder.setComputePipelineState(rotatePipelineState)
            rotateEncoder.setTexture(inputTexture, index: 0)
            rotateEncoder.setTexture(rotatedTexture, index: 1)
            
            let rotateThreadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let rotateThreadgroups = MTLSize(
                width: (height + 15) / 16,
                height: (width + 15) / 16,
                depth: 1
            )
            
            rotateEncoder.dispatchThreadgroups(rotateThreadgroups, threadsPerThreadgroup: rotateThreadgroupSize)
            rotateEncoder.endEncoding()
            
            processedTexture = rotatedTexture
        } else {
            processedTexture = inputTexture
        }
        
        // Now letterbox resize
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        
        encoder.setComputePipelineState(letterboxPipelineState)
        encoder.setTexture(processedTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        var scaleBuffer = SIMD2<Float>(scale, scale)
        var offsetBuffer = SIMD2<Float>(Float(padX), Float(padY))
        encoder.setBytes(&scaleBuffer, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        encoder.setBytes(&offsetBuffer, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (640 + 15) / 16,
            height: (640 + 15) / 16,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        CVMetalTextureCacheFlush(textureCache, 0)
        return outputPixelBuffer
    }
    
    private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard status == kCVReturnSuccess, let texture = cvTexture else {
            return nil
        }
        
        return CVMetalTextureGetTexture(texture)
    }
    
    private func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }
}
