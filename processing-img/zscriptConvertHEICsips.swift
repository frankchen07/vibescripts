#!/usr/bin/swift

import Foundation

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
        let outputPath = (inputPath as NSString).deletingPathExtension + "_scriptconvertedsips.jpg"
        
        print("Converting: \(heicFile)")
        
        // Use sips command-line tool - it's Apple's built-in image processor
        // that might use similar code paths to Photos app
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = [
            "-s", "format", "jpeg",
            "-s", "formatOptions", "100",  // Maximum quality
            "--setProperty", "formatOptions", "100",
            inputPath,
            "--out", outputPath
        ]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("Successfully converted: \(heicFile)")
            } else {
                print("Error: sips failed for \(heicFile) with status \(process.terminationStatus)")
            }
        } catch {
            print("Error running sips for \(heicFile): \(error)")
            continue
        }
    }
    
    print("Conversion complete!")
} catch {
    print("Error: \(error)")
    exit(1)
} 