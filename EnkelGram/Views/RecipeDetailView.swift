//
//  RecipeDetailView.swift
//  EnkelGram
//
//  Shows the full recipe detail with WebView and extracted content.
//  Handles loading Instagram post and extracting content via Vision OCR.
//

import SwiftUI
import WebKit

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

    /// Controls whether we show the WebView or the saved content
    @State private var showWebView: Bool = false

    /// Triggers screenshot extraction when set to true
    @State private var shouldExtract: Bool = false

    /// Loading state for content extraction
    @State private var isExtracting: Bool = false

    /// Error message if something goes wrong
    @State private var errorMessage: String?

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
        .toolbar {
            // Only show toolbar when recipe is not fully saved yet
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
            VStack(alignment: .leading, spacing: 16) {
                // Screenshot
                if let imageData = recipe.screenshotData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    Text("Post ID: \(recipe.postID)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    // MARK: - Actions

    /// Called when the WebView has loaded and we have extracted content
    private func handleContentLoaded(screenshot: UIImage?, extractedText: String) {
        // Save the screenshot (only if we got one and don't already have one)
        if let screenshot = screenshot, recipe.screenshotData == nil {
            recipe.screenshotData = screenshot.jpegData(compressionQuality: 0.8)
        }

        // Process extracted text
        if !extractedText.isEmpty && recipe.title.isEmpty {
            // Check if text contains DOM body marker
            if extractedText.contains("{{BODY}}") {
                // Split into OCR title and DOM body
                let parts = extractedText.components(separatedBy: "\n\n{{BODY}}")
                let ocrPart = parts[0]
                let domPart = parts.count > 1 ? parts[1] : ""

                // Extract title from OCR text
                recipe.title = TextExtractionService.extractCaption(from: ocrPart)

                // Clean DOM body - remove Instagram metadata lines
                recipe.bodyText = TextExtractionService.cleanDOMText(domPart)
            } else {
                // No DOM body, just use OCR text as title
                recipe.title = TextExtractionService.extractCaption(from: extractedText)
            }
        }

        // Mark as fully extracted only when we have both image and text
        if recipe.screenshotData != nil && !recipe.title.isEmpty {
            recipe.isContentExtracted = true
        }

        isExtracting = false

        // SwiftData automatically saves changes
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: SavedRecipe(instagramURL: "https://www.instagram.com/p/test123/"))
    }
    .modelContainer(for: SavedRecipe.self, inMemory: true)
}
