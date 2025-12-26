//
//  SavedRecipe.swift
//  EnkelGram
//
//  The data model for a saved recipe from Instagram.
//  Uses SwiftData for automatic persistence (saving to disk).
//

import Foundation
import SwiftData

/// Represents a recipe saved from Instagram.
///
/// The @Model macro tells SwiftData to:
/// - Automatically save this to a local database
/// - Track changes and sync them
/// - Generate code for querying/filtering
///
@Model
final class SavedRecipe {

    // MARK: - Properties

    /// Unique identifier for this recipe
    var id: UUID

    /// The original Instagram URL (e.g., "https://www.instagram.com/p/ABC123/")
    var instagramURL: String

    /// The recipe title (extracted via OCR)
    var title: String

    /// The recipe body text (extracted via DOM)
    var bodyText: String

    /// When this recipe was saved
    var dateSaved: Date

    /// Screenshot of the Instagram post (stored as binary data)
    /// Optional because we might not have captured it yet
    @Attribute(.externalStorage)  // Store large data outside the main database
    var screenshotData: Data?

    /// Has the content been extracted from the WebView yet?
    var isContentExtracted: Bool

    // MARK: - Initialization

    /// Creates a new SavedRecipe with the given Instagram URL.
    /// Initially, only the URL is known. Caption and screenshot are extracted later.
    ///
    /// - Parameter instagramURL: The Instagram post URL
    init(instagramURL: String) {
        self.id = UUID()
        self.instagramURL = instagramURL
        self.title = ""
        self.bodyText = ""
        self.dateSaved = Date()
        self.screenshotData = nil
        self.isContentExtracted = false
    }

    // MARK: - Computed Properties

    /// Returns a preview of the title (first 100 characters)
    var captionPreview: String {
        if title.isEmpty {
            return "Tap to load content..."
        }
        if title.count <= 100 {
            return title
        }
        return String(title.prefix(100)) + "..."
    }

    /// Extracts the post ID from the Instagram URL for display
    /// e.g., "instagram.com/p/ABC123" -> "ABC123"
    var postID: String {
        // Instagram URLs look like: https://www.instagram.com/p/ABC123/
        // or https://www.instagram.com/reel/ABC123/
        if let range = instagramURL.range(of: "/p/") ?? instagramURL.range(of: "/reel/") {
            let afterPrefix = instagramURL[range.upperBound...]
            if let endRange = afterPrefix.range(of: "/") {
                return String(afterPrefix[..<endRange.lowerBound])
            }
            return String(afterPrefix)
        }
        return "Unknown"
    }
}
