//
//  NavigationTests.swift
//  EnkelGramTests
//
//  Tests for navigation functionality including URL scheme handling
//  and Share Extension communication.
//

import Testing
import Foundation
@testable import EnkelGram

/// Tests for navigation-related functionality.
struct NavigationTests {

    // MARK: - URL Scheme Parsing Tests

    @Test("Parse valid enkelgram URL with recipe ID")
    func testParseValidEnkelgramURL() {
        let uuidString = "550E8400-E29B-41D4-A716-446655440000"
        let url = URL(string: "enkelgram://recipe/\(uuidString)")!

        let parsedID = parseRecipeIDFromURL(url)

        #expect(parsedID != nil)
        #expect(parsedID?.uuidString == uuidString)
    }

    @Test("Parse enkelgram URL with lowercase UUID")
    func testParseLowercaseUUID() {
        let uuidString = "550e8400-e29b-41d4-a716-446655440000"
        let url = URL(string: "enkelgram://recipe/\(uuidString)")!

        let parsedID = parseRecipeIDFromURL(url)

        #expect(parsedID != nil)
    }

    @Test("Reject URL with wrong scheme")
    func testRejectWrongScheme() {
        let url = URL(string: "https://recipe/550E8400-E29B-41D4-A716-446655440000")!

        let parsedID = parseRecipeIDFromURL(url)

        #expect(parsedID == nil)
    }

    @Test("Reject URL with wrong host")
    func testRejectWrongHost() {
        let url = URL(string: "enkelgram://other/550E8400-E29B-41D4-A716-446655440000")!

        let parsedID = parseRecipeIDFromURL(url)

        #expect(parsedID == nil)
    }

    @Test("Reject URL with invalid UUID")
    func testRejectInvalidUUID() {
        let url = URL(string: "enkelgram://recipe/not-a-valid-uuid")!

        let parsedID = parseRecipeIDFromURL(url)

        #expect(parsedID == nil)
    }

    @Test("Reject URL with missing path")
    func testRejectMissingPath() {
        let url = URL(string: "enkelgram://recipe/")!

        let parsedID = parseRecipeIDFromURL(url)

        #expect(parsedID == nil)
    }

    // MARK: - Recipe ID Storage Tests

    @Test("Store and retrieve recipe ID from UserDefaults")
    func testStoreAndRetrieveRecipeID() {
        // Use a test suite name to avoid affecting real data
        let testSuiteName = "com.enkel.EnkelGram.tests"
        let defaults = UserDefaults(suiteName: testSuiteName)!

        // Clean up before test
        defaults.removeObject(forKey: "newRecipeID")

        // Store a recipe ID
        let recipeID = UUID()
        defaults.set(recipeID.uuidString, forKey: "newRecipeID")

        // Retrieve it
        let storedIDString = defaults.string(forKey: "newRecipeID")

        #expect(storedIDString == recipeID.uuidString)

        // Clean up
        defaults.removeObject(forKey: "newRecipeID")
    }

    @Test("Clear recipe ID after retrieval")
    func testClearRecipeIDAfterRetrieval() {
        let testSuiteName = "com.enkel.EnkelGram.tests"
        let defaults = UserDefaults(suiteName: testSuiteName)!

        // Store a recipe ID
        let recipeID = UUID()
        defaults.set(recipeID.uuidString, forKey: "newRecipeID")

        // Simulate retrieval and clearing (as done in ContentView)
        _ = defaults.string(forKey: "newRecipeID")
        defaults.removeObject(forKey: "newRecipeID")

        // Verify it's cleared
        let clearedID = defaults.string(forKey: "newRecipeID")

        #expect(clearedID == nil)
    }

    @Test("Handle missing recipe ID gracefully")
    func testMissingRecipeID() {
        let testSuiteName = "com.enkel.EnkelGram.tests"
        let defaults = UserDefaults(suiteName: testSuiteName)!

        // Ensure no recipe ID exists
        defaults.removeObject(forKey: "newRecipeID")

        let storedID = defaults.string(forKey: "newRecipeID")

        #expect(storedID == nil)
    }

    // MARK: - URL Construction Tests

    @Test("Construct valid enkelgram URL from recipe ID")
    func testConstructEnkelgramURL() {
        let recipeID = UUID()
        let urlString = "enkelgram://recipe/\(recipeID.uuidString)"
        let url = URL(string: urlString)

        #expect(url != nil)
        #expect(url?.scheme == "enkelgram")
        #expect(url?.host == "recipe")
        #expect(url?.pathComponents.last == recipeID.uuidString)
    }

    // MARK: - Helper Functions

    /// Parses a recipe ID from an enkelgram:// URL.
    /// This mirrors the logic in EnkelGramApp.handleIncomingURL
    private func parseRecipeIDFromURL(_ url: URL) -> UUID? {
        guard url.scheme == "enkelgram",
              url.host == "recipe",
              let uuidString = url.pathComponents.last,
              !uuidString.isEmpty,
              uuidString != "/" else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }
}

/// Tests for SavedRecipe navigation compatibility.
struct SavedRecipeNavigationTests {

    @Test("SavedRecipe conforms to Hashable for NavigationPath")
    func testRecipeIsHashable() {
        let recipe1 = SavedRecipe(instagramURL: "https://instagram.com/p/test1/")
        let recipe2 = SavedRecipe(instagramURL: "https://instagram.com/p/test2/")

        // Different recipes should have different hash values
        #expect(recipe1.hashValue != recipe2.hashValue)

        // Same recipe should have same hash
        #expect(recipe1.hashValue == recipe1.hashValue)
    }

    @Test("SavedRecipe can be used in Set (Hashable requirement)")
    func testRecipeInSet() {
        let recipe1 = SavedRecipe(instagramURL: "https://instagram.com/p/test1/")
        let recipe2 = SavedRecipe(instagramURL: "https://instagram.com/p/test2/")

        var recipeSet: Set<SavedRecipe> = []
        recipeSet.insert(recipe1)
        recipeSet.insert(recipe2)

        #expect(recipeSet.count == 2)
        #expect(recipeSet.contains(recipe1))
        #expect(recipeSet.contains(recipe2))
    }

    @Test("SavedRecipe equality based on ID")
    func testRecipeEquality() {
        let recipe1 = SavedRecipe(instagramURL: "https://instagram.com/p/test1/")
        let recipe2 = SavedRecipe(instagramURL: "https://instagram.com/p/test2/")

        // Different IDs means not equal
        #expect(recipe1 != recipe2)

        // Same reference means equal
        #expect(recipe1 == recipe1)
    }

    @Test("Recipe ID is unique for each instance")
    func testUniqueIDs() {
        let recipes = (0..<100).map { _ in
            SavedRecipe(instagramURL: "https://instagram.com/p/test/")
        }

        let uniqueIDs = Set(recipes.map { $0.id })

        #expect(uniqueIDs.count == 100)
    }
}
