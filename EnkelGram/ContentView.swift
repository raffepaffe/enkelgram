//
//  ContentView.swift
//  EnkelGram
//
//  The main view showing a list of saved recipes.
//

import SwiftUI
import SwiftData

/// The main content view - displays a list of all saved recipes.
///
/// Key SwiftUI concepts used here:
/// - @Query: Automatically fetches data from SwiftData and updates when it changes
/// - @Environment: Accesses shared resources (like the database context)
/// - NavigationStack: Provides navigation (back buttons, titles, etc.)
/// - List: A scrollable list of items
/// - NavigationLink: Tapping an item navigates to another screen
///
struct ContentView: View {

    // MARK: - Properties

    /// Fetches all saved recipes from the database, sorted by date (newest first).
    /// The @Query property wrapper automatically:
    /// - Loads data when the view appears
    /// - Updates the view when data changes
    @Query(sort: \SavedRecipe.dateSaved, order: .reverse)
    private var recipes: [SavedRecipe]

    /// Access to the SwiftData model context (needed for saving/deleting).
    /// Think of this as a connection to the database.
    @Environment(\.modelContext) private var modelContext

    /// Controls whether the "Add URL" dialog is shown
    @State private var showingAddDialog = false

    /// The URL text entered by the user
    @State private var urlText = ""

    /// Navigation path for programmatic navigation
    @State private var navigationPath = NavigationPath()

    /// Recipe ID passed from Share Extension via URL scheme
    @Binding var pendingRecipeID: UUID?

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if recipes.isEmpty {
                    // Show a helpful message when there are no recipes yet
                    emptyStateView
                } else {
                    // Show the list of recipes
                    recipeListView
                }
            }
            .navigationTitle("EnkelGram")
            .toolbar {
                // Add a button to manually add a URL
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddDialog = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Add Instagram URL", isPresented: $showingAddDialog) {
                TextField("Paste Instagram URL", text: $urlText)
                Button("Cancel", role: .cancel) {
                    urlText = ""
                }
                Button("Add") {
                    addRecipe()
                }
            } message: {
                Text("Paste an Instagram post, reel, or TV URL")
            }
            .navigationDestination(for: SavedRecipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .onAppear {
                checkForNewRecipeFromShareExtension()
            }
            .onChange(of: pendingRecipeID) { oldValue, newValue in
                if let recipeID = newValue {
                    navigateToRecipe(id: recipeID)
                    pendingRecipeID = nil
                }
            }
        }
    }

    // MARK: - Subviews

    /// View shown when there are no saved recipes yet
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "fork.knife")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Recipes Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Share a recipe from Instagram\nto save it here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    /// The list of saved recipes
    private var recipeListView: some View {
        List {
            ForEach(recipes) { recipe in
                NavigationLink(value: recipe) {
                    RecipeRowView(recipe: recipe)
                }
            }
            .onDelete(perform: deleteRecipes)
        }
    }

    // MARK: - Actions

    /// Adds a recipe with the URL from the text field and navigates to it
    private func addRecipe() {
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            urlText = ""
            return
        }

        let recipe = SavedRecipe(instagramURL: trimmedURL)
        modelContext.insert(recipe)
        urlText = ""

        // Navigate to the new recipe
        navigationPath.append(recipe)
    }

    /// Checks if the Share Extension added a new recipe and navigates to it
    private func checkForNewRecipeFromShareExtension() {
        let defaults = UserDefaults(suiteName: EnkelGramApp.appGroupID)

        // Check if there's a new recipe ID from the Share Extension
        guard let newRecipeID = defaults?.string(forKey: "newRecipeID"),
              let uuid = UUID(uuidString: newRecipeID) else {
            return
        }

        // Clear the flag so we don't navigate again
        defaults?.removeObject(forKey: "newRecipeID")

        // Navigate to the recipe
        navigateToRecipe(id: uuid)
    }

    /// Navigates to a recipe by its ID
    private func navigateToRecipe(id: UUID) {
        // Find the recipe and navigate to it
        if let recipe = recipes.first(where: { $0.id == id }) {
            // Small delay to ensure the view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                navigationPath.append(recipe)
            }
        }
    }

    /// Deletes recipes at the specified indices
    /// This is called when user swipes to delete
    private func deleteRecipes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(recipes[index])
        }
    }
}

// MARK: - Preview

/// This allows you to see the view in Xcode's preview canvas
/// without running the full app.
#Preview {
    ContentView(pendingRecipeID: .constant(nil))
        .modelContainer(for: SavedRecipe.self, inMemory: true)
}
