//
//  EnkelGramApp.swift
//  EnkelGram
//
//  Main entry point for the EnkelGram app.
//  This file is marked with @main, which tells iOS where to start.
//

import SwiftUI
import SwiftData

/// The main app structure.
/// In SwiftUI, apps are declared as structs that conform to the `App` protocol.
@main
struct EnkelGramApp: App {

    /// The shared model container that uses App Group storage.
    /// This allows the Share Extension to access the same database.
    let modelContainer: ModelContainer

    /// Stores the recipe ID to navigate to (set by URL scheme or Share Extension)
    @State private var pendingRecipeID: UUID?

    init() {
        // Create a model container using the shared App Group location
        do {
            let schema = Schema([SavedRecipe.self])
            let config = ModelConfiguration(
                schema: schema,
                url: EnkelGramApp.sharedDatabaseURL,
                allowsSave: true
            )
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            // Schema changed - delete old database and create fresh one
            // This handles migration issues during development
            try? FileManager.default.removeItem(at: EnkelGramApp.sharedDatabaseURL)

            do {
                let schema = Schema([SavedRecipe.self])
                let config = ModelConfiguration(
                    schema: schema,
                    url: EnkelGramApp.sharedDatabaseURL,
                    allowsSave: true
                )
                modelContainer = try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    /// The body property defines the app's scene structure.
    /// A Scene is a container for your app's user interface.
    /// WindowGroup is used for typical iOS apps - it manages your main window.
    var body: some Scene {
        WindowGroup {
            ContentView(pendingRecipeID: $pendingRecipeID)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        // Use our custom model container with shared storage
        .modelContainer(modelContainer)
    }

    /// Handles incoming URLs from the Share Extension
    private func handleIncomingURL(_ url: URL) {
        // URL format: enkelgram://recipe/UUID
        guard url.scheme == "enkelgram",
              url.host == "recipe",
              let uuidString = url.pathComponents.last,
              let uuid = UUID(uuidString: uuidString) else {
            return
        }
        pendingRecipeID = uuid
    }

    // MARK: - Shared Storage

    /// The App Group identifier - must match the one in the Share Extension
    static let appGroupID = "group.com.enkel.EnkelGram"

    /// The URL for the shared database in the App Group container
    static var sharedDatabaseURL: URL {
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) {
            return containerURL.appendingPathComponent("EnkelGram.store")
        }

        // Fallback to documents directory (won't be shared with extension)
        return URL.documentsDirectory.appendingPathComponent("EnkelGram.store")
    }
}
