//
//  SavedRecipeTests.swift
//  EnkelGramTests
//
//  Unit tests for the SavedRecipe model.
//  These tests verify that our data model works correctly.
//

import Testing
import Foundation
@testable import EnkelGram

/// Tests for the SavedRecipe model.
///
/// Swift Testing is Apple's modern testing framework (introduced 2023).
/// Tests are functions marked with @Test that verify expected behavior.
///
struct SavedRecipeTests {

    // MARK: - Initialization Tests

    @Test("Recipe initializes with correct default values")
    func testInitialization() {
        // Arrange & Act
        let url = "https://www.instagram.com/p/ABC123/"
        let recipe = SavedRecipe(instagramURL: url)

        // Assert
        #expect(recipe.instagramURL == url)
        #expect(recipe.title.isEmpty)
        #expect(recipe.bodyText.isEmpty)
        #expect(recipe.screenshotData == nil)
        #expect(recipe.isContentExtracted == false)
        #expect(recipe.id != UUID()) // Has a unique ID
    }

    @Test("Recipe dateSaved is set to current time")
    func testDateSaved() {
        // Arrange
        let beforeCreation = Date()

        // Act
        let recipe = SavedRecipe(instagramURL: "https://instagram.com/p/test/")
        let afterCreation = Date()

        // Assert
        #expect(recipe.dateSaved >= beforeCreation)
        #expect(recipe.dateSaved <= afterCreation)
    }

    // MARK: - Post ID Extraction Tests

    @Test("PostID extracts correctly from standard post URL")
    func testPostIDFromStandardURL() {
        let recipe = SavedRecipe(instagramURL: "https://www.instagram.com/p/ABC123XYZ/")
        #expect(recipe.postID == "ABC123XYZ")
    }

    @Test("PostID extracts correctly from reel URL")
    func testPostIDFromReelURL() {
        let recipe = SavedRecipe(instagramURL: "https://www.instagram.com/reel/REEL456/")
        #expect(recipe.postID == "REEL456")
    }

    @Test("PostID handles URL without trailing slash")
    func testPostIDWithoutTrailingSlash() {
        let recipe = SavedRecipe(instagramURL: "https://www.instagram.com/p/NoSlash")
        #expect(recipe.postID == "NoSlash")
    }

    @Test("PostID returns Unknown for invalid URL")
    func testPostIDForInvalidURL() {
        let recipe = SavedRecipe(instagramURL: "https://example.com/something")
        #expect(recipe.postID == "Unknown")
    }

    // MARK: - Caption Preview Tests

    @Test("Caption preview shows placeholder when empty")
    func testCaptionPreviewWhenEmpty() {
        let recipe = SavedRecipe(instagramURL: "https://instagram.com/p/test/")
        #expect(recipe.captionPreview == "Tap to load content...")
    }

    @Test("Caption preview shows full text when short")
    func testCaptionPreviewShortText() {
        let recipe = SavedRecipe(instagramURL: "https://instagram.com/p/test/")
        recipe.title = "Short caption"
        #expect(recipe.captionPreview == "Short caption")
    }

    @Test("Caption preview truncates long text")
    func testCaptionPreviewLongText() {
        let recipe = SavedRecipe(instagramURL: "https://instagram.com/p/test/")
        recipe.title = String(repeating: "A", count: 150) // 150 characters

        #expect(recipe.captionPreview.count == 103) // 100 chars + "..."
        #expect(recipe.captionPreview.hasSuffix("..."))
    }

    @Test("Caption preview handles exactly 100 characters")
    func testCaptionPreviewExactly100Chars() {
        let recipe = SavedRecipe(instagramURL: "https://instagram.com/p/test/")
        recipe.title = String(repeating: "B", count: 100)

        #expect(recipe.captionPreview == recipe.title)
        #expect(!recipe.captionPreview.hasSuffix("..."))
    }
}
