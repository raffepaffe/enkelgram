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
