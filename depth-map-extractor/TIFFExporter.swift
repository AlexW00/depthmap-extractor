//
//  TIFFExporter.swift
//  depth-map-extractor
//
//  16-bit TIFF Export for Apple Motion compatibility
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Exports CGImages as 16-bit grayscale TIFFs optimized for Apple Motion
enum TIFFExporter {
    
    enum ExportError: Error, LocalizedError {
        case failedToCreateDestination
        case failedToWriteImage
        
        var errorDescription: String? {
            switch self {
            case .failedToCreateDestination: return "Failed to create TIFF file destination"
            case .failedToWriteImage: return "Failed to write image to TIFF file"
            }
        }
    }
    
    /// Export a CGImage as a 16-bit uncompressed TIFF
    /// - Parameters:
    ///   - image: The CGImage to export (should be 16-bit grayscale for best results)
    ///   - url: Destination URL for the TIFF file
    static func export(_ image: CGImage, to url: URL) throws {
        // Create image destination for TIFF
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportError.failedToCreateDestination
        }
        
        // Configure TIFF properties for Motion compatibility
        // Compression = 1 means no compression (fastest loading in Motion)
        // LZW (5) is also a good option for smaller files
        let tiffProperties: [CFString: Any] = [
            kCGImagePropertyTIFFCompression: 1  // No compression
        ]
        
        let imageProperties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: tiffProperties
        ]
        
        // Add image to destination with properties
        CGImageDestinationAddImage(destination, image, imageProperties as CFDictionary)
        
        // Finalize and write to disk
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.failedToWriteImage
        }
    }
    
    /// Export with LZW compression (smaller file size, still fast in Motion)
    static func exportCompressed(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportError.failedToCreateDestination
        }
        
        let tiffProperties: [CFString: Any] = [
            kCGImagePropertyTIFFCompression: 5  // LZW compression
        ]
        
        let imageProperties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: tiffProperties
        ]
        
        CGImageDestinationAddImage(destination, image, imageProperties as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.failedToWriteImage
        }
    }
}
