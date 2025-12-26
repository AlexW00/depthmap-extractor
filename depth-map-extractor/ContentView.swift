//
//  ContentView.swift
//  depth-map-extractor
//
//  Drop Zone UI for Depth Map Extraction
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var inputImageURL: URL?
    @State private var inputImage: NSImage?
    @State private var depthMapImage: NSImage?
    @State private var depthMapCGImage: CGImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var isTargeted = false
    
    private let depthConverter = DepthConverter()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Depth Map Extractor")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Drop a photo to generate a 16-bit depth map")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Main content area
            HStack(spacing: 20) {
                // Input drop zone / preview
                VStack {
                    Text("Input")
                        .font(.headline)
                    
                    dropZone
                }
                
                // Arrow
                if inputImage != nil {
                    Image(systemName: "arrow.right")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                
                // Output preview
                if inputImage != nil {
                    VStack {
                        Text("Depth Map")
                            .font(.headline)
                        
                        outputPreview
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Action buttons
            HStack(spacing: 16) {
                if inputImage != nil {
                    Button("Clear") {
                        clearAll()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Save") {
                        Task {
                            await convertAndSave()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing || depthMapImage == nil)
                }
            }
            
            // Status
            if isProcessing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating depth map...")
                        .foregroundStyle(.secondary)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(30)
        .frame(minWidth: 500, minHeight: 500)
    }
    
    // MARK: - Drop Zone
    
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                )
            
            if let image = inputImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(10)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    
                    Text("Drop JPEG or PNG here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    Button("Choose File...") {
                        openFilePicker()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(width: 200, height: 280)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            
            // Start security-scoped access for sandboxed apps
            let didStartAccess = url.startAccessingSecurityScopedResource()
            
            Task { @MainActor in
                await loadImage(from: url)
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
    
    // MARK: - Output Preview
    
    private var outputPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            
            if let depthImage = depthMapImage {
                Image(nsImage: depthImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(10)
            } else if isProcessing {
                ProgressView()
            } else {
                Text("Depth map will appear here")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 200, height: 280)
        .onDrag {
            createDepthMapItemProvider()
        }
    }
    
    private func createDepthMapItemProvider() -> NSItemProvider {
        guard let cgImage = depthMapCGImage,
              let inputURL = inputImageURL else {
            return NSItemProvider()
        }
        
        // Create a temporary file for the depth map TIFF
        let fileName = inputURL.deletingPathExtension().lastPathComponent + "_depth.tiff"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try TIFFExporter.export(cgImage, to: tempURL)
            let provider = NSItemProvider(contentsOf: tempURL)
            // Set suggested name without extension - system adds it automatically
            provider?.suggestedName = inputURL.deletingPathExtension().lastPathComponent + "_depth"
            return provider ?? NSItemProvider()
        } catch {
            return NSItemProvider()
        }
    }
    
    // MARK: - Actions
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await loadImage(from: url)
            }
        }
    }
    
    private func loadImage(from url: URL) async {
        errorMessage = nil
        inputImageURL = url
        
        if let image = NSImage(contentsOf: url) {
            inputImage = image
            await generateDepthMap()
        } else {
            errorMessage = "Failed to load image"
        }
    }
    
    private func generateDepthMap() async {
        guard let url = inputImageURL else { return }
        
        isProcessing = true
        errorMessage = nil
        depthMapImage = nil
        
        do {
            let cgImage = try await depthConverter.generateDepthMap(from: url)
            depthMapCGImage = cgImage
            depthMapImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isProcessing = false
    }
    
    private func convertAndSave() async {
        guard let url = inputImageURL else { return }
        
        // Create save panel
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.tiff]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "_depth.tiff"
        
        guard panel.runModal() == .OK, let saveURL = panel.url else { return }
        
        isProcessing = true
        errorMessage = nil
        
        do {
            let cgImage = try await depthConverter.generateDepthMap(from: url)
            try TIFFExporter.export(cgImage, to: saveURL)
            
            // Open in Finder
            NSWorkspace.shared.activateFileViewerSelecting([saveURL])
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
        
        isProcessing = false
    }
    
    private func clearAll() {
        inputImageURL = nil
        inputImage = nil
        depthMapImage = nil
        depthMapCGImage = nil
        errorMessage = nil
    }
}

#Preview {
    ContentView()
}
