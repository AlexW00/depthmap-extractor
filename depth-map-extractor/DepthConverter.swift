//
//  DepthConverter.swift
//  depth-map-extractor
//
//  AI Depth Map Extraction using CoreML + Vision
//

import Vision
import CoreImage
import CoreVideo
import Accelerate
import CoreML

/// Actor-isolated depth map generator using CoreML depth estimation models
actor DepthConverter {
    
    enum DepthError: Error, LocalizedError {
        case failedToLoadImage
        case modelNotFound
        case noDepthResult
        case failedToCreateContext
        case failedToConvertImage
        case unsupportedOutputFormat
        
        var errorDescription: String? {
            switch self {
            case .failedToLoadImage: return "Failed to load the input image"
            case .modelNotFound: return "Depth estimation model not found. Add DepthAnythingV2SmallF16.mlmodelc to the project."
            case .noDepthResult: return "CoreML did not return a depth result"
            case .failedToCreateContext: return "Failed to create Core Image context"
            case .failedToConvertImage: return "Failed to convert depth buffer to image"
            case .unsupportedOutputFormat: return "Model output format not supported"
            }
        }
    }
    
    private let context: CIContext
    private var cachedModel: VNCoreMLModel?
    
    init() {
        self.context = CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: true
        ])
    }
    
    /// Generate a 16-bit grayscale depth map from an image URL
    /// - Parameter imageURL: URL to the input image (JPEG, PNG, etc.)
    /// - Returns: CGImage with 16-bit grayscale depth data (white = close, black = far)
    nonisolated func generateDepthMap(from imageURL: URL) async throws -> CGImage {
        // Load the CoreML model
        let model = try await loadModel()
        
        // Create the CoreML Vision request
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        
        // Create handler and perform request
        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        try handler.perform([request])
        
        // Process the result
        guard let results = request.results else {
            throw DepthError.noDepthResult
        }
        
        // Handle different result types
        if let pixelBufferObservation = results.first as? VNPixelBufferObservation {
            return try await normalizeAndConvert(depthBuffer: pixelBufferObservation.pixelBuffer)
        } else if let featureValueObservation = results.first as? VNCoreMLFeatureValueObservation,
                  let multiArray = featureValueObservation.featureValue.multiArrayValue {
            return try await convertMultiArrayToImage(multiArray)
        } else {
            throw DepthError.unsupportedOutputFormat
        }
    }
    
    /// Load the CoreML model (cached after first load)
    private func loadModel() throws -> VNCoreMLModel {
        if let cached = getCachedModel() {
            return cached
        }
        
        // Try to load model from bundle
        // Supports: DepthAnythingV2SmallF16, DepthPro, or any depth estimation model
        let modelNames = [
            "DepthAnythingV2SmallF16",
            "DepthAnythingV2Small", 
            "DepthPro",
            "DepthProNormalizedInverseDepth"
        ]
        
        for name in modelNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                let config = MLModelConfiguration()
                config.computeUnits = .cpuAndNeuralEngine
                
                let mlModel = try MLModel(contentsOf: url, configuration: config)
                let vnModel = try VNCoreMLModel(for: mlModel)
                setCachedModel(vnModel)
                return vnModel
            }
        }
        
        throw DepthError.modelNotFound
    }
    
    private func getCachedModel() -> VNCoreMLModel? {
        return cachedModel
    }
    
    private func setCachedModel(_ model: VNCoreMLModel) {
        cachedModel = model
    }
    
    /// Normalize the depth buffer and convert to 16-bit grayscale
    private func normalizeAndConvert(depthBuffer: CVPixelBuffer) throws -> CGImage {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            throw DepthError.failedToConvertImage
        }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthBuffer)
        
        // Handle different pixel formats
        switch pixelFormat {
        case kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_DisparityFloat32:
            return try normalizeFloat32Buffer(
                baseAddress: baseAddress,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow
            )
        case kCVPixelFormatType_OneComponent16Half, kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DisparityFloat16:
            return try normalizeFloat16Buffer(
                baseAddress: baseAddress,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow
            )
        case kCVPixelFormatType_OneComponent8:
            return try normalize8BitBuffer(
                baseAddress: baseAddress,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow
            )
        default:
            // Fallback: use CIImage conversion
            return try convertViaCIImage(depthBuffer: depthBuffer)
        }
    }
    /// Convert MLMultiArray output to CGImage
    private func convertMultiArrayToImage(_ multiArray: MLMultiArray) throws -> CGImage {
        // Get dimensions
        let shape = multiArray.shape.map { $0.intValue }
        
        // Debug: print shape info
        print("MLMultiArray shape: \(shape), dataType: \(multiArray.dataType), strides: \(multiArray.strides)")
        
        // Determine dimensions based on shape
        let height: Int
        let width: Int
        
        if shape.count == 4 {
            // [N, C, H, W] - batch, channels, height, width
            height = shape[2]
            width = shape[3]
        } else if shape.count == 3 {
            // [C, H, W] or [1, H, W]
            height = shape[1]
            width = shape[2]
        } else if shape.count == 2 {
            // [H, W]
            height = shape[0]
            width = shape[1]
        } else {
            throw DepthError.unsupportedOutputFormat
        }
        
        print("Extracted dimensions: \(width) x \(height)")
        
        let pixelCount = width * height
        var floatBuffer = [Float](repeating: 0, count: pixelCount)
        
        // Use MLMultiArray subscript accessor for correct indexing
        // This handles strides and data types automatically
        if shape.count == 4 {
            for y in 0..<height {
                for x in 0..<width {
                    let value = multiArray[[0, 0, y, x] as [NSNumber]]
                    floatBuffer[y * width + x] = value.floatValue
                }
            }
        } else if shape.count == 3 {
            for y in 0..<height {
                for x in 0..<width {
                    let value = multiArray[[0, y, x] as [NSNumber]]
                    floatBuffer[y * width + x] = value.floatValue
                }
            }
        } else {
            for y in 0..<height {
                for x in 0..<width {
                    let value = multiArray[[y, x] as [NSNumber]]
                    floatBuffer[y * width + x] = value.floatValue
                }
            }
        }
        
        // Normalize using Accelerate
        var minVal: Float = 0
        var maxVal: Float = 0
        vDSP_minv(floatBuffer, 1, &minVal, vDSP_Length(pixelCount))
        vDSP_maxv(floatBuffer, 1, &maxVal, vDSP_Length(pixelCount))
        
        print("Depth values range: \(minVal) to \(maxVal)")
        
        let range = maxVal - minVal
        guard range > 0 else {
            throw DepthError.failedToConvertImage
        }
        
        // Normalize to [0, 1]: (value - min) / range
        var negMin = -minVal
        vDSP_vsadd(floatBuffer, 1, &negMin, &floatBuffer, 1, vDSP_Length(pixelCount))
        var invRange = 1.0 / range
        vDSP_vsmul(floatBuffer, 1, &invRange, &floatBuffer, 1, vDSP_Length(pixelCount))
        
        // Convert to 16-bit unsigned integers [0, 65535]
        var scale: Float = 65535.0
        var uint16Buffer = [UInt16](repeating: 0, count: pixelCount)
        
        vDSP_vsmul(floatBuffer, 1, &scale, &floatBuffer, 1, vDSP_Length(pixelCount))
        vDSP_vfixu16(floatBuffer, 1, &uint16Buffer, 1, vDSP_Length(pixelCount))
        
        return try create16BitGrayscaleImage(from: uint16Buffer, width: width, height: height)
    }
    
    /// Normalize 32-bit float buffer using Accelerate framework
    private func normalizeFloat32Buffer(
        baseAddress: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) throws -> CGImage {
        let floatPointer = baseAddress.assumingMemoryBound(to: Float.self)
        let pixelCount = width * height
        
        // Create a contiguous buffer (the source might have padding)
        var floatBuffer = [Float](repeating: 0, count: pixelCount)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float>.stride
        
        for y in 0..<height {
            for x in 0..<width {
                floatBuffer[y * width + x] = floatPointer[y * floatsPerRow + x]
            }
        }
        
        // Find min and max using Accelerate
        var minVal: Float = 0
        var maxVal: Float = 0
        vDSP_minv(floatBuffer, 1, &minVal, vDSP_Length(pixelCount))
        vDSP_maxv(floatBuffer, 1, &maxVal, vDSP_Length(pixelCount))
        
        // Avoid division by zero
        let range = maxVal - minVal
        guard range > 0 else {
            throw DepthError.failedToConvertImage
        }
        
        // Normalize to [0, 1]: (value - min) / range
        var negMin = -minVal
        vDSP_vsadd(floatBuffer, 1, &negMin, &floatBuffer, 1, vDSP_Length(pixelCount))
        var invRange = 1.0 / range
        vDSP_vsmul(floatBuffer, 1, &invRange, &floatBuffer, 1, vDSP_Length(pixelCount))
        
        // Convert to 16-bit unsigned integers [0, 65535]
        var scale: Float = 65535.0
        var uint16Buffer = [UInt16](repeating: 0, count: pixelCount)
        
        vDSP_vsmul(floatBuffer, 1, &scale, &floatBuffer, 1, vDSP_Length(pixelCount))
        vDSP_vfixu16(floatBuffer, 1, &uint16Buffer, 1, vDSP_Length(pixelCount))
        
        return try create16BitGrayscaleImage(from: uint16Buffer, width: width, height: height)
    }
    
    /// Normalize 16-bit float (half) buffer
    private func normalizeFloat16Buffer(
        baseAddress: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) throws -> CGImage {
        let pixelCount = width * height
        let halfFloatsPerRow = bytesPerRow / 2
        
        // Convert Float16 to Float32 for processing using Accelerate
        var floatBuffer = [Float](repeating: 0, count: pixelCount)
        let halfPointer = baseAddress.assumingMemoryBound(to: UInt16.self)
        
        // Create contiguous half buffer first
        var halfBuffer = [UInt16](repeating: 0, count: pixelCount)
        for y in 0..<height {
            for x in 0..<width {
                halfBuffer[y * width + x] = halfPointer[y * halfFloatsPerRow + x]
            }
        }
        
        // Convert IEEE 754 half to Float32 (Float16 is unavailable in macOS x86_64)
        for i in 0..<pixelCount {
            floatBuffer[i] = halfToFloat32(bitPattern: halfBuffer[i])
        }
        
        // Normalize using the same logic as Float32
        var minVal: Float = 0
        var maxVal: Float = 0
        vDSP_minv(floatBuffer, 1, &minVal, vDSP_Length(pixelCount))
        vDSP_maxv(floatBuffer, 1, &maxVal, vDSP_Length(pixelCount))
        
        let range = maxVal - minVal
        guard range > 0 else {
            throw DepthError.failedToConvertImage
        }
        
        var negMin = -minVal
        vDSP_vsadd(floatBuffer, 1, &negMin, &floatBuffer, 1, vDSP_Length(pixelCount))
        var invRange = 1.0 / range
        vDSP_vsmul(floatBuffer, 1, &invRange, &floatBuffer, 1, vDSP_Length(pixelCount))
        
        var scale: Float = 65535.0
        var uint16Buffer = [UInt16](repeating: 0, count: pixelCount)
        
        vDSP_vsmul(floatBuffer, 1, &scale, &floatBuffer, 1, vDSP_Length(pixelCount))
        vDSP_vfixu16(floatBuffer, 1, &uint16Buffer, 1, vDSP_Length(pixelCount))
        
        return try create16BitGrayscaleImage(from: uint16Buffer, width: width, height: height)
    }

    @inline(__always)
    private func halfToFloat32(bitPattern halfBits: UInt16) -> Float {
        let half = UInt32(halfBits)
        let sign = (half & 0x8000) << 16
        let exponent = Int((half >> 10) & 0x1F)
        let mantissa = Int(half & 0x03FF)

        if exponent == 0 {
            if mantissa == 0 {
                return Float(bitPattern: sign)
            }

            var mantissaNormalized = mantissa
            var exponentUnbiased = -14
            while (mantissaNormalized & 0x0400) == 0 {
                mantissaNormalized <<= 1
                exponentUnbiased -= 1
            }

            mantissaNormalized &= 0x03FF
            let exponentBiased = UInt32(exponentUnbiased + 127)
            let floatBits = sign | (exponentBiased << 23) | (UInt32(mantissaNormalized) << 13)
            return Float(bitPattern: floatBits)
        }

        if exponent == 0x1F {
            let floatBits = sign | 0x7F800000 | (UInt32(mantissa) << 13)
            return Float(bitPattern: floatBits)
        }

        let exponentBiased = UInt32((exponent - 15) + 127)
        let floatBits = sign | (exponentBiased << 23) | (UInt32(mantissa) << 13)
        return Float(bitPattern: floatBits)
    }
    
    /// Normalize 8-bit buffer (upscale to 16-bit)
    private func normalize8BitBuffer(
        baseAddress: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) throws -> CGImage {
        let pixelCount = width * height
        let uint8Pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        var uint16Buffer = [UInt16](repeating: 0, count: pixelCount)
        
        for y in 0..<height {
            for x in 0..<width {
                let value = uint8Pointer[y * bytesPerRow + x]
                // Scale 0-255 to 0-65535
                uint16Buffer[y * width + x] = UInt16(value) * 257
            }
        }
        
        return try create16BitGrayscaleImage(from: uint16Buffer, width: width, height: height)
    }
    
    /// Fallback conversion using CIImage
    private func convertViaCIImage(depthBuffer: CVPixelBuffer) throws -> CGImage {
        let ciImage = CIImage(cvPixelBuffer: depthBuffer)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        guard let cgImage = context.createCGImage(
            ciImage,
            from: ciImage.extent,
            format: .L16,
            colorSpace: colorSpace
        ) else {
            throw DepthError.failedToConvertImage
        }
        
        return cgImage
    }
    
    /// Create a 16-bit grayscale CGImage from UInt16 buffer
    private func create16BitGrayscaleImage(
        from buffer: [UInt16],
        width: Int,
        height: Int
    ) throws -> CGImage {
        let bytesPerPixel = 2
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 16
        let bitsPerPixel = 16
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        // Create data copy for CGDataProvider
        let data = buffer.withUnsafeBytes { Data($0) }
        
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw DepthError.failedToConvertImage
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder16Little.rawValue | CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw DepthError.failedToConvertImage
        }
        
        return cgImage
    }
}
