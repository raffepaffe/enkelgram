//
//  TextExtractionServiceTests.swift
//  EnkelGramTests
//
//  Tests for the TextExtractionService.
//

import Testing
import Foundation
@testable import EnkelGram

/// Tests for TextExtractionService.
struct TextExtractionServiceTests {

    // MARK: - URL Validation Tests

    @Test("Valid Instagram post URL is recognized")
    func testValidPostURL() {
        let url = "https://www.instagram.com/p/ABC123/"
        #expect(TextExtractionService.isValidInstagramURL(url) == true)
    }

    @Test("Valid Instagram reel URL is recognized")
    func testValidReelURL() {
        let url = "https://www.instagram.com/reel/XYZ789/"
        #expect(TextExtractionService.isValidInstagramURL(url) == true)
    }

    @Test("Valid Instagram TV URL is recognized")
    func testValidTVURL() {
        let url = "https://www.instagram.com/tv/VIDEO123/"
        #expect(TextExtractionService.isValidInstagramURL(url) == true)
    }

    @Test("Short Instagram URL is recognized")
    func testShortURL() {
        let url = "https://instagr.am/p/SHORT/"
        #expect(TextExtractionService.isValidInstagramURL(url) == true)
    }

    @Test("URL without https is still recognized")
    func testURLWithoutHTTPS() {
        let url = "instagram.com/p/NOHTTPS/"
        #expect(TextExtractionService.isValidInstagramURL(url) == true)
    }

    @Test("Case insensitive URL matching")
    func testCaseInsensitiveURL() {
        let url = "HTTPS://WWW.INSTAGRAM.COM/P/UPPERCASE/"
        #expect(TextExtractionService.isValidInstagramURL(url) == true)
    }

    @Test("Non-Instagram URL is rejected")
    func testNonInstagramURL() {
        let url = "https://www.example.com/page/"
        #expect(TextExtractionService.isValidInstagramURL(url) == false)
    }

    @Test("Instagram profile URL is rejected (not a post)")
    func testProfileURLRejected() {
        // Profile URLs don't have /p/, /reel/, or /tv/
        let url = "https://www.instagram.com/username/"
        #expect(TextExtractionService.isValidInstagramURL(url) == false)
    }

    @Test("Empty string is rejected")
    func testEmptyString() {
        #expect(TextExtractionService.isValidInstagramURL("") == false)
    }

    @Test("Random text is rejected")
    func testRandomText() {
        #expect(TextExtractionService.isValidInstagramURL("not a url at all") == false)
    }
}

// MARK: - Post ID Extraction Tests

struct PostIDExtractionTests {

    @Test("Extract post ID from standard post URL")
    func testExtractPostID() {
        let url = "https://www.instagram.com/p/ABC123/"
        #expect(TextExtractionService.extractPostID(from: url) == "ABC123")
    }

    @Test("Extract post ID from reel URL")
    func testExtractReelPostID() {
        let url = "https://www.instagram.com/reel/XYZ789/"
        #expect(TextExtractionService.extractPostID(from: url) == "XYZ789")
    }

    @Test("Extract post ID from TV URL")
    func testExtractTVPostID() {
        let url = "https://www.instagram.com/tv/VIDEO123/"
        #expect(TextExtractionService.extractPostID(from: url) == "VIDEO123")
    }

    @Test("Extract post ID without trailing slash")
    func testExtractPostIDNoSlash() {
        let url = "https://www.instagram.com/p/ABC123"
        #expect(TextExtractionService.extractPostID(from: url) == "ABC123")
    }

    @Test("Extract post ID with query parameters")
    func testExtractPostIDWithParams() {
        // Instagram sometimes adds tracking params - we should still get the ID
        let url = "https://www.instagram.com/p/ABC123/?utm_source=ig_web"
        // The current implementation will include the query string after the slash
        // This test documents current behavior
        #expect(TextExtractionService.extractPostID(from: url) == "ABC123")
    }

    @Test("Return nil for profile URL")
    func testProfileURLReturnsNil() {
        let url = "https://www.instagram.com/username/"
        #expect(TextExtractionService.extractPostID(from: url) == nil)
    }

    @Test("Return nil for empty string")
    func testEmptyStringReturnsNil() {
        #expect(TextExtractionService.extractPostID(from: "") == nil)
    }

    @Test("Return nil for non-Instagram URL")
    func testNonInstagramReturnsNil() {
        let url = "https://www.example.com/p/ABC123/"
        #expect(TextExtractionService.extractPostID(from: url) == nil)
    }

    @Test("Same post ID from different URL formats")
    func testSamePostIDDifferentFormats() {
        let postID = "DDBKjNSxnWF"
        let urls = [
            "https://www.instagram.com/p/\(postID)/",
            "https://instagram.com/p/\(postID)",
            "http://www.instagram.com/p/\(postID)/",
            "instagram.com/p/\(postID)/"
        ]

        for url in urls {
            #expect(TextExtractionService.extractPostID(from: url) == postID, "Failed for URL: \(url)")
        }
    }
}

// MARK: - Caption Extraction Tests

struct CaptionExtractionTests {

    @Test("Extract caption ending with 'more'")
    func testExtractCaptionWithMore() {
        let rawText = """
        Instagram
        username • Follow
        This is my delicious recipe for pasta... more
        View all 50 comments
        """
        let caption = TextExtractionService.extractCaption(from: rawText)
        #expect(caption == "This is my delicious recipe for pasta")
    }

    @Test("Extract caption ending with ellipsis")
    func testExtractCaptionWithEllipsis() {
        let rawText = """
        username •
        Amazing chocolate cake recipe with secret ingredient...
        Liked by user1 and others
        """
        let caption = TextExtractionService.extractCaption(from: rawText)
        #expect(caption == "Amazing chocolate cake recipe with secret ingredient")
    }

    @Test("Extract caption with colon (recipe format)")
    func testExtractCaptionWithColon() {
        let rawText = """
        Instagram
        Follow
        Ingredients: flour, sugar, eggs, butter
        Sign up
        """
        let caption = TextExtractionService.extractCaption(from: rawText)
        #expect(caption.contains("Ingredients"))
    }

    @Test("Filter out Instagram UI elements")
    func testFilterUIElements() {
        let rawText = """
        Log in
        Sign up
        Follow
        Continue on web
        Open app
        """
        let caption = TextExtractionService.extractCaption(from: rawText)
        #expect(caption.isEmpty)
    }

    @Test("Filter out 'username • Follow' pattern")
    func testFilterUsernameFollowPattern() {
        let rawText = """
        chef_mike • Follow
        Best soup recipe ever shared here today
        """
        let caption = TextExtractionService.extractCaption(from: rawText)
        #expect(!caption.contains("Follow"))
        #expect(caption.contains("soup recipe") || caption.contains("Best"))
    }

    @Test("Extract longest non-UI line as fallback")
    func testExtractLongestLine() {
        let rawText = """
        Short
        This is a much longer line that should be selected as the caption
        Also short
        """
        let caption = TextExtractionService.extractCaption(from: rawText)
        #expect(caption.contains("longer line"))
    }

    @Test("Handle empty input")
    func testEmptyInput() {
        let caption = TextExtractionService.extractCaption(from: "")
        #expect(caption.isEmpty)
    }

    @Test("Handle input with only UI elements")
    func testOnlyUIElements() {
        let rawText = """
        Instagram
        Log in
        Sign up for Instagram
        Terms of use
        Privacy Policy
        """
        let caption = TextExtractionService.extractCaption(from: rawText)
        #expect(caption.isEmpty)
    }

    @Test("Clean trailing 'more' variations")
    func testCleanMoreVariations() {
        let inputs = [
            "Recipe text... more",
            "Recipe text...more",
            "Recipe text… more",
            "Recipe text…more"
        ]
        for input in inputs {
            let caption = TextExtractionService.extractCaption(from: input)
            #expect(!caption.contains("more"), "Failed for input: \(input)")
        }
    }

    @Test("Skip short lines under 10 characters")
    func testSkipShortLines() {
        let rawText = """
        Hi
        Short
        This is a proper recipe description that should be extracted
        Bye
        """
        let caption = TextExtractionService.extractCaption(from: rawText)
        #expect(caption.contains("proper recipe"))
    }
}

// MARK: - DOM Text Cleaning Tests

struct DOMTextCleaningTests {

    @Test("Remove likes and comments line")
    func testRemoveLikesComments() {
        let rawText = """
        Recipe content here
        1,234 likes, 56 comments
        More recipe content
        """
        let cleaned = TextExtractionService.cleanDOMText(rawText)
        #expect(!cleaned.contains("likes"))
        #expect(!cleaned.contains("comments"))
        #expect(cleaned.contains("Recipe content"))
    }

    @Test("Remove standalone likes count")
    func testRemoveStandaloneLikes() {
        let rawText = """
        Delicious pasta recipe
        6,012 likes
        Add the sauce slowly
        """
        let cleaned = TextExtractionService.cleanDOMText(rawText)
        #expect(!cleaned.contains("likes"))
        #expect(cleaned.contains("pasta recipe"))
        #expect(cleaned.contains("sauce"))
    }

    @Test("Remove date attribution line")
    func testRemoveDateLine() {
        let rawText = """
        Best chocolate cake
        chef_mike on December 25, 2024:
        Mix all ingredients
        """
        let cleaned = TextExtractionService.cleanDOMText(rawText)
        #expect(!cleaned.contains("December"))
        #expect(!cleaned.contains("chef_mike on"))
        #expect(cleaned.contains("chocolate cake"))
        #expect(cleaned.contains("Mix all"))
    }

    @Test("Remove various month formats")
    func testRemoveVariousMonths() {
        let months = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
        for month in months {
            let rawText = "user on \(month) 1, 2024:\nRecipe text"
            let cleaned = TextExtractionService.cleanDOMText(rawText)
            #expect(!cleaned.lowercased().contains(month.lowercased()), "Failed for \(month)")
        }
    }

    @Test("Preserve recipe content")
    func testPreserveContent() {
        let rawText = """
        Ingredients:
        - 2 cups flour
        - 1 cup sugar
        - 3 eggs

        Instructions:
        Mix well and bake at 350F
        """
        let cleaned = TextExtractionService.cleanDOMText(rawText)
        #expect(cleaned.contains("Ingredients"))
        #expect(cleaned.contains("flour"))
        #expect(cleaned.contains("Instructions"))
        #expect(cleaned.contains("350F"))
    }

    @Test("Handle empty input")
    func testEmptyInput() {
        let cleaned = TextExtractionService.cleanDOMText("")
        #expect(cleaned.isEmpty)
    }

    @Test("Preserve empty lines for formatting")
    func testPreserveEmptyLines() {
        let rawText = """
        First paragraph

        Second paragraph
        """
        let cleaned = TextExtractionService.cleanDOMText(rawText)
        #expect(cleaned.contains("First"))
        #expect(cleaned.contains("Second"))
    }

    @Test("Keep longer lines with 'likes' in content")
    func testKeepLikesInContent() {
        let rawText = "Everyone likes this recipe because it's so easy to make"
        let cleaned = TextExtractionService.cleanDOMText(rawText)
        #expect(cleaned.contains("likes"))
    }

    @Test("Remove username header pattern")
    func testRemoveUsernameHeader() {
        let rawText = """
        chefjoshadamo
        •
        Follow
        How to make a Michelin star, Steak Au Poivre sauce #chef
        """
        let cleaned = TextExtractionService.cleanDOMText(rawText)
        #expect(!cleaned.contains("chefjoshadamo"))
        #expect(!cleaned.contains("Follow"))
        #expect(cleaned.contains("Michelin star"))
    }

    @Test("Keep all body text after header")
    func testKeepBodyText() {
        let rawText = """
        chef_mike
        •
        Follow
        This is the full recipe text
        with multiple lines
        and all the details #cooking #food
        """
        let cleaned = TextExtractionService.cleanDOMText(rawText)
        #expect(cleaned.contains("full recipe text"))
        #expect(cleaned.contains("multiple lines"))
        #expect(cleaned.contains("#cooking"))
    }

    @Test("Keep hashtags in content")
    func testKeepHashtags() {
        let rawText = "Best pasta recipe #italian #food #cooking"
        let cleaned = TextExtractionService.cleanDOMText(rawText)
        #expect(cleaned.contains("#italian"))
        #expect(cleaned.contains("#food"))
    }
}
