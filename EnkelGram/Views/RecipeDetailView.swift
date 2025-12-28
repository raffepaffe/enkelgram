//
//  RecipeDetailView.swift
//  EnkelGram
//
//  Shows the full recipe detail with WebView and extracted content.
//  Handles loading Instagram post and extracting content via Vision OCR.
//

import SwiftUI
import WebKit
import PhotosUI

/// The detail view for a recipe.
///
/// This view:
/// 1. Shows the Instagram post in a WebView
/// 2. Captures a screenshot when loaded
/// 3. Extracts text using Vision OCR
/// 4. Saves the extracted content
///
struct RecipeDetailView: View {

    // MARK: - Properties

    /// The recipe being viewed.
    /// @Bindable allows us to modify the recipe and have SwiftData save changes.
    @Bindable var recipe: SavedRecipe

    /// Access to SwiftData for saving
    @Environment(\.modelContext) private var modelContext

    /// Dismiss action to go back to main list
    @Environment(\.dismiss) private var dismiss

    /// Controls whether we show the WebView or the saved content
    @State private var showWebView: Bool = false

    /// Triggers screenshot extraction when set to true
    @State private var shouldExtract: Bool = false

    /// Loading state for content extraction
    @State private var isExtracting: Bool = false

    /// Error message if something goes wrong
    @State private var errorMessage: String?

    /// Selected photo from picker
    @State private var selectedPhoto: PhotosPickerItem?

    /// OCR text extracted from imported screenshot
    @State private var importedOCRText: String = ""

    /// Show append/replace confirmation dialog
    @State private var showImportConfirmation: Bool = false

    /// Loading state for OCR processing
    @State private var isProcessingOCR: Bool = false

    // MARK: - Computed Properties

    /// Whether we have saved the thumbnail image
    private var hasImage: Bool {
        recipe.screenshotData != nil
    }

    /// Whether we have extracted the caption text
    private var hasText: Bool {
        !recipe.title.isEmpty || !recipe.bodyText.isEmpty
    }

    /// Whether both image and text are saved
    private var isFullySaved: Bool {
        hasImage && hasText
    }

    /// The label for the save button based on current state
    private var saveButtonLabel: String {
        if !hasImage {
            return "Save Image"
        } else if !hasText {
            return "Save Text"
        }
        return "Save"
    }

    /// Text to share via share sheet (title + body + URL)
    private var shareText: String {
        var parts: [String] = []
        if !recipe.title.isEmpty {
            parts.append(recipe.title)
        }
        if !recipe.bodyText.isEmpty {
            parts.append(recipe.bodyText)
        }
        parts.append(recipe.instagramURL)
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Toggle between WebView and saved content (only when fully saved)
            if isFullySaved {
                contentToggle
            }

            // Main content area
            if showWebView || !isFullySaved {
                webViewSection
            } else {
                savedContentSection
            }
        }
        .navigationTitle("Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Custom back button that always goes to main list
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }

            // Only show save button when recipe is not fully saved yet
            if !isFullySaved {
                ToolbarItem(placement: .primaryAction) {
                    if isExtracting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Saving...")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button(saveButtonLabel) {
                            isExtracting = true
                            shouldExtract = true
                        }
                    }
                }
            }

            // Share button (only when fully saved)
            if isFullySaved {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                // Import screenshot button
                ToolbarItem(placement: .primaryAction) {
                    if isProcessingOCR {
                        ProgressView()
                    } else {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Image(systemName: "text.viewfinder")
                        }
                    }
                }
            }
        }
        .onChange(of: selectedPhoto) { oldValue, newValue in
            if let newValue {
                processImportedPhoto(newValue)
            }
        }
        .confirmationDialog("Import Text", isPresented: $showImportConfirmation) {
            Button("Append to Recipe") {
                if !recipe.bodyText.isEmpty {
                    recipe.bodyText += "\n\n" + importedOCRText
                } else {
                    recipe.bodyText = importedOCRText
                }
                importedOCRText = ""
            }
            Button("Replace Recipe") {
                recipe.bodyText = importedOCRText
                importedOCRText = ""
            }
            Button("Cancel", role: .cancel) {
                importedOCRText = ""
            }
        } message: {
            Text("How would you like to add the extracted text?")
        }
    }

    // MARK: - Subviews

    /// Toggle between WebView and saved content
    private var contentToggle: some View {
        Picker("View Mode", selection: $showWebView) {
            Text("Live").tag(true)
            Text("Saved").tag(false)
        }
        .pickerStyle(.segmented)
        .padding()
    }

    /// The WebView showing the Instagram post
    private var webViewSection: some View {
        VStack {
            if let url = URL(string: recipe.instagramURL) {
                InstagramWebView(
                    url: url,
                    onContentLoaded: handleContentLoaded,
                    shouldExtract: $shouldExtract
                )
            } else {
                Text("Invalid URL")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Shows the saved screenshot and extracted text (editable)
    private var savedContentSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Screenshot - full width
                if let imageData = recipe.screenshotData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                }

                // Editable title
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Recipe title", text: $recipe.title, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }

                // Editable body text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recipe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $recipe.bodyText)
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }

                // Metadata
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved: \(recipe.dateSaved.formatted())")

                    // Tappable Instagram URL
                    if let url = URL(string: recipe.instagramURL) {
                        Link(recipe.instagramURL, destination: url)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(recipe.instagramURL)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    /// Called when the WebView has loaded and we have extracted content.
    ///
    /// The extraction process returns combined OCR + DOM text separated by a marker:
    /// Format: "[OCR text]\n\n{{BODY}}[DOM text]"
    /// - OCR text: Visual text recognized from the screenshot (used for title)
    /// - DOM text: Text extracted from Instagram's HTML (used for body/recipe)
    ///
    /// - Parameters:
    ///   - screenshot: The captured image (nil if only extracting text)
    ///   - extractedText: Combined OCR and DOM text with {{BODY}} separator
    private func handleContentLoaded(screenshot: UIImage?, extractedText: String) {
        // Save the screenshot as PNG (supports transparency for dark/light mode)
        if let screenshot = screenshot, recipe.screenshotData == nil {
            recipe.screenshotData = screenshot.pngData()
        }

        // Process extracted text (only if we don't have a title yet)
        if !extractedText.isEmpty && recipe.title.isEmpty {
            // Check if text contains the {{BODY}} marker that separates OCR from DOM text
            if extractedText.contains("{{BODY}}") {
                // Split into OCR title and DOM body
                let parts = extractedText.components(separatedBy: "\n\n{{BODY}}")

                // Safely get the OCR part (first element always exists after split)
                guard let ocrPart = parts.first else {
                    recipe.title = TextExtractionService.extractCaption(from: extractedText)
                    return
                }

                // DOM part may not exist if marker was at the end
                let domPart = parts.count > 1 ? parts[1] : ""

                // Extract a clean title from OCR text (filters Instagram UI elements)
                recipe.title = TextExtractionService.extractCaption(from: ocrPart)

                // Clean DOM body - removes username/Follow header and metadata
                recipe.bodyText = TextExtractionService.cleanDOMText(domPart)
            } else {
                // No DOM body available, just use OCR text as title
                recipe.title = TextExtractionService.extractCaption(from: extractedText)
            }
        }

        // Mark as fully extracted only when we have both image and text
        if recipe.screenshotData != nil && !recipe.title.isEmpty {
            recipe.isContentExtracted = true
        }

        isExtracting = false

        // Note: SwiftData automatically saves changes when properties are modified
    }

    /// Processes an imported photo: loads the image and extracts text via OCR
    private func processImportedPhoto(_ item: PhotosPickerItem) {
        isProcessingOCR = true
        selectedPhoto = nil

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else {
                    await MainActor.run {
                        isProcessingOCR = false
                    }
                    return
                }

                // Run OCR on the image
                TextExtractionService.shared.extractText(from: uiImage) { extractedText in
                    DispatchQueue.main.async {
                        isProcessingOCR = false

                        if extractedText.isEmpty {
                            errorMessage = "No text found in image"
                            return
                        }

                        // Clean the extracted text
                        let cleanedText = TextExtractionService.cleanDOMText(extractedText)
                        importedOCRText = cleanedText
                        showImportConfirmation = true
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessingOCR = false
                    errorMessage = "Failed to load image"
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: SavedRecipe(instagramURL: "https://www.instagram.com/p/test123/"))
    }
    .modelContainer(for: SavedRecipe.self, inMemory: true)
}
