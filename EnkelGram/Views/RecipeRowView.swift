//
//  RecipeRowView.swift
//  EnkelGram
//
//  Displays a single recipe row in the list.
//  Shows thumbnail (if available), caption preview, and date.
//

import SwiftUI

/// A row view for displaying a recipe in a list.
///
/// SwiftUI views are typically small, focused components.
/// This view only knows how to display one recipe row.
///
struct RecipeRowView: View {

    // MARK: - Properties

    /// The recipe to display
    let recipe: SavedRecipe

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail image
            thumbnailView

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                // Caption preview
                Text(recipe.captionPreview)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(recipe.isContentExtracted ? .primary : .secondary)

                // Date saved
                Text(recipe.dateSaved, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Subviews

    /// The thumbnail image view
    @ViewBuilder
    private var thumbnailView: some View {
        if let imageData = recipe.screenshotData,
           let uiImage = UIImage(data: imageData) {
            // Show the actual screenshot - no rounded corners to avoid white border issues
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 150)
                .clipped()
        } else {
            // Show a placeholder when no screenshot yet
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 100, height: 150)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        RecipeRowView(recipe: SavedRecipe(instagramURL: "https://instagram.com/p/test123/"))
    }
    .modelContainer(for: SavedRecipe.self, inMemory: true)
}
