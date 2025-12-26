//
//  ShareViewController.swift
//  EnkelGramShare
//
//  Share Extension that receives URLs from Instagram and other apps.
//  Saves the URL to the shared SwiftData database.
//

import UIKit
import SwiftUI
import Social
import UniformTypeIdentifiers
import SwiftData

/// The main view controller for the Share Extension.
///
/// Share Extensions have a limited UI and runtime. They should:
/// - Quickly process the shared content
/// - Save it to shared storage
/// - Dismiss themselves
///
class ShareViewController: UIViewController {

    // MARK: - Properties

    /// The URL that was shared to us
    private var sharedURL: String?

    /// Loading indicator while we process
    private var activityIndicator: UIActivityIndicatorView?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        extractSharedContent()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Set background
        view.backgroundColor = UIColor.systemBackground

        // Add a simple UI with app name and loading indicator
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // App icon/name
        let titleLabel = UILabel()
        titleLabel.text = "EnkelGram"
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label

        // Status label
        let statusLabel = UILabel()
        statusLabel.text = "Saving recipe..."
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel

        // Activity indicator
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        self.activityIndicator = indicator

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(indicator)
        stackView.addArrangedSubview(statusLabel)

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Content Extraction

    /// Extracts the shared URL from the extension context.
    private func extractSharedContent() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeWithError("No items shared")
            return
        }

        // Look through all shared items
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                // Check if this attachment contains a URL
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    loadURL(from: attachment)
                    return
                }

                // Also check for plain text (some apps share URLs as text)
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    loadText(from: attachment)
                    return
                }
            }
        }

        completeWithError("No URL found in shared content")
    }

    /// Loads a URL from the attachment
    private func loadURL(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.completeWithError("Failed to load URL: \(error.localizedDescription)")
                    return
                }

                if let url = item as? URL {
                    self?.sharedURL = url.absoluteString
                    self?.saveAndComplete()
                } else {
                    self?.completeWithError("Invalid URL format")
                }
            }
        }
    }

    /// Loads text from the attachment (might contain a URL)
    private func loadText(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.completeWithError("Failed to load text: \(error.localizedDescription)")
                    return
                }

                if let text = item as? String {
                    // Check if the text contains an Instagram URL
                    if TextExtractionService.isValidInstagramURL(text) {
                        // Extract the URL from the text
                        self?.sharedURL = self?.extractInstagramURL(from: text)
                        self?.saveAndComplete()
                    } else {
                        self?.completeWithError("No Instagram URL found")
                    }
                } else {
                    self?.completeWithError("Invalid text format")
                }
            }
        }
    }

    /// Extracts an Instagram URL from text that might contain other content
    private func extractInstagramURL(from text: String) -> String? {
        // Simple regex to find Instagram URLs
        let patterns = [
            "https?://(?:www\\.)?instagram\\.com/(?:p|reel|tv)/[A-Za-z0-9_-]+/?",
            "https?://instagr\\.am/[A-Za-z0-9_-]+/?"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                return String(text[range])
            }
        }

        // If no match, return the whole text if it looks like a URL
        if text.contains("instagram.com") {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    // MARK: - Save and Complete

    /// Saves the URL to the shared database and dismisses
    private func saveAndComplete() {
        guard let urlString = sharedURL else {
            completeWithError("No URL to save")
            return
        }

        // Save to SwiftData
        do {
            // Create a model container that uses the App Group
            let schema = Schema([SavedRecipe.self])
            let config = ModelConfiguration(
                schema: schema,
                url: getSharedDatabaseURL(),
                allowsSave: true
            )
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)

            // Create and save the recipe
            let recipe = SavedRecipe(instagramURL: urlString)
            context.insert(recipe)
            try context.save()

            // Save the recipe ID so the main app can navigate to it
            let defaults = UserDefaults(suiteName: "group.com.enkel.EnkelGram")
            defaults?.set(recipe.id.uuidString, forKey: "newRecipeID")

            // Success! Dismiss the extension and open main app
            completeSuccessfully(recipeID: recipe.id)

        } catch {
            completeWithError("Failed to save: \(error.localizedDescription)")
        }
    }

    /// Returns the URL for the shared database (in the App Group container)
    private func getSharedDatabaseURL() -> URL {
        // App Group identifier - must match what's in the main app
        let appGroupID = "group.com.enkel.EnkelGram"

        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return containerURL.appendingPathComponent("EnkelGram.store")
        }

        // Fallback to default location (won't be shared with main app)
        return URL.documentsDirectory.appendingPathComponent("EnkelGram.store")
    }

    // MARK: - Completion

    /// Completes the extension successfully and opens the main app
    private func completeSuccessfully(recipeID: UUID) {
        activityIndicator?.stopAnimating()

        // Open the main app using URL scheme
        let urlString = "enkelgram://recipe/\(recipeID.uuidString)"
        if let url = URL(string: urlString) {
            openURL(url)
        }

        // Complete the extension request
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Opens a URL using the responder chain (required for extensions)
    private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if let application = r as? UIApplication {
                application.open(url)
                return
            }
            responder = r.next
        }
        // Fallback: use selector-based approach
        let selector = sel_registerName("openURL:")
        responder = self
        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }

    /// Completes the extension with an error
    private func completeWithError(_ message: String) {
        activityIndicator?.stopAnimating()

        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.extensionContext?.cancelRequest(withError: NSError(
                domain: "EnkelGramShare",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))
        })

        present(alert, animated: true)
    }
}
