#!/usr/bin/swift

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

// Check if a directory path was provided
guard CommandLine.arguments.count > 1 else {
    print("Usage: \(CommandLine.arguments[0]) <directory>")
    exit(1)
}

let directoryPath = CommandLine.arguments[1]
let fileManager = FileManager.default

// Check if directory exists
guard fileManager.fileExists(atPath: directoryPath) else {
    print("Error: Directory '\(directoryPath)' does not exist")
    exit(1)
}

// Get all HEIC files in the directory
do {
    let files = try fileManager.contentsOfDirectory(atPath: directoryPath)
    let heicFiles = files.filter { $0.lowercased().hasSuffix(".heic") }
    
    for heicFile in heicFiles {
        let inputPath = (directoryPath as NSString).appendingPathComponent(heicFile)
        let outputPath = (inputPath as NSString).deletingPathExtension + "_scriptconverted.jpg"
        
        print("Converting: \(heicFile)")
        
        // Load image using CGImageSource
        guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil) else {
            print("Error: Could not create image source for \(heicFile)")
            continue
        }
        
        // Get image properties
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            print("Error: Could not get image properties for \(heicFile)")
            continue
        }
        
        // Get dimensions for thumbnail
        guard let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else {
            print("Error: Could not get image dimensions for \(heicFile)")
            continue
        }
        
        // Use CGImageSourceCreateThumbnailAtIndex with transform option
        // This automatically handles orientation correctly
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,  // This handles orientation!
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),  // Full size
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true  // Important for HDR/tone mapping
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) else {
            print("Error: Could not create image from \(heicFile)")
            continue
        }
        
        // Create JPEG destination using ImageIO with modern UTType
        guard let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: outputPath) as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            print("Error: Could not create image destination for \(heicFile)")
            continue
        }
        
        // Set JPEG quality to maximum (1.0 = 100%)
        // Orientation is already handled by the thumbnail transform, so set it to 1 (up)
        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1.0,
            kCGImageDestinationOptimizeColorForSharing: true,
            kCGImagePropertyOrientation: 1  // Already oriented correctly
        ]
        
        // Add image to destination
        CGImageDestinationAddImage(destination, cgImage, destinationOptions as CFDictionary)
        
        // Finalize the destination (writes the file)
        guard CGImageDestinationFinalize(destination) else {
            print("Error: Could not finalize JPEG for \(heicFile)")
            continue
        }
        
        print("Successfully converted: \(heicFile)")
    }
    
    print("Conversion complete!")
} catch {
    print("Error: \(error)")
    exit(1)
} 