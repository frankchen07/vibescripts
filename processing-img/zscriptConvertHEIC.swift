#!/usr/bin/swift

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

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
        let outputPath = (inputPath as NSString).deletingPathExtension + "_sips.jpg"
        
        print("Converting: \(heicFile)")
        
        // Load image with CIImage for subtle contrast enhancement
        guard let ciImage = CIImage(contentsOf: URL(fileURLWithPath: inputPath)) else {
            print("Error: Could not load image \(heicFile)")
            continue
        }
        
        let originalColorSpace = ciImage.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            print("Error: Could not create sRGB color space")
            continue
        }
        
        // Apply subtle adjustments to better match Preview's output
        // Preview appears to boost highlights (whiter areas) more than shadows
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ciImage
        colorControls.brightness = 0.012  // Moderate brightness boost (for whiter highlights)
        colorControls.contrast = 1.01  // Boost (1.01-1.015 range)
        colorControls.saturation = 1.0
        
        let enhancedImage = colorControls.outputImage ?? ciImage
        
        // Use CIContext with proper color matching
        let context = CIContext(options: [
            .workingColorSpace: originalColorSpace,
            .outputColorSpace: sRGBColorSpace,
            .useSoftwareRenderer: false
        ])
        
        // Render to JPEG with quality 100
        guard let jpegData = context.jpegRepresentation(of: enhancedImage,
                                                      colorSpace: sRGBColorSpace,
                                                      options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0]) else {
            print("Error: Could not convert \(heicFile) to JPEG")
            continue
        }
        
        // Write JPEG data
        do {
            try jpegData.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            print("Error saving \(heicFile): \(error)")
            continue
        }
        
        print("Successfully converted: \(heicFile)")
    }
    
    print("Conversion complete!")
} catch {
    print("Error: \(error)")
    exit(1)
} 