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
    @State private var showWebView: Bool = true

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
        !recipe.captionText.isEmpty
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
            ToolbarItem(placement: .primaryAction) {
                if !isFullySaved {
                    // Show Save button or progress
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
                } else {
                    // Show checkmark when fully saved (image + text)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Saved")
                            .foregroundStyle(.secondary)
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

    /// Shows the saved screenshot and extracted text
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

                // Extracted caption
                if !recipe.captionText.isEmpty {
                    Text(recipe.captionText)
                        .font(.body)
                        .textSelection(.enabled)  // Allow copying text
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
        if !extractedText.isEmpty && recipe.captionText.isEmpty {
            // Check if text contains DOM body marker
            if extractedText.contains("{{BODY}}") {
                // Split into OCR title and DOM body
                let parts = extractedText.components(separatedBy: "\n\n{{BODY}}")
                let ocrPart = parts[0]
                var domPart = parts.count > 1 ? parts[1] : ""

                // Extract title from OCR text
                let cleanedTitle = TextExtractionService.extractCaption(from: ocrPart)

                // Clean DOM body - remove Instagram metadata lines
                domPart = cleanDOMText(domPart)

                // Combine title and body
                if !domPart.isEmpty {
                    recipe.captionText = cleanedTitle + "\n\n" + domPart
                } else {
                    recipe.captionText = cleanedTitle
                }
            } else {
                // No DOM body, just use OCR text
                let cleanedCaption = TextExtractionService.extractCaption(from: extractedText)
                recipe.captionText = cleanedCaption
            }
        }

        // Mark as fully extracted only when we have both image and text
        if recipe.screenshotData != nil && !recipe.captionText.isEmpty {
            recipe.isContentExtracted = true
        }

        isExtracting = false

        // SwiftData automatically saves changes
    }

    /// Cleans DOM extracted text by removing Instagram metadata
    private func cleanDOMText(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")

        // Filter out metadata lines
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()

            // Skip empty lines (will add back proper spacing later)
            if trimmed.isEmpty {
                return true
            }

            // Remove lines with likes/comments pattern: "X likes, Y comments"
            if lowercased.contains(" likes") || lowercased.contains(" like,") {
                if lowercased.contains(" comment") {
                    return false
                }
            }

            // Remove standalone likes count: "6,012 likes"
            if lowercased.hasSuffix(" likes") && trimmed.count < 20 {
                return false
            }

            // Remove lines with "username on Date:" pattern
            if lowercased.contains(" on ") && (
                lowercased.contains("january") ||
                lowercased.contains("february") ||
                lowercased.contains("march") ||
                lowercased.contains("april") ||
                lowercased.contains("may") ||
                lowercased.contains("june") ||
                lowercased.contains("july") ||
                lowercased.contains("august") ||
                lowercased.contains("september") ||
                lowercased.contains("october") ||
                lowercased.contains("november") ||
                lowercased.contains("december")
            ) {
                return false
            }

            return true
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: SavedRecipe(instagramURL: "https://www.instagram.com/p/test123/"))
    }
    .modelContainer(for: SavedRecipe.self, inMemory: true)
}
