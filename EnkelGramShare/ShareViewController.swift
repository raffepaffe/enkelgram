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
import Vision

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

    /// The image that was shared to us
    private var sharedImage: UIImage?

    /// OCR text extracted from shared image
    private var extractedOCRText: String?

    /// Loading indicator while we process
    private var activityIndicator: UIActivityIndicatorView?

    /// Status label for updating text
    private var statusLabel: UILabel?

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
        statusLabel.text = "Processing..."
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        self.statusLabel = statusLabel

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

    /// Extracts the shared URL or image from the extension context.
    private func extractSharedContent() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeWithError("No items shared")
            return
        }

        // Look through all shared items
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                // Check if this attachment contains an image
                if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    loadImage(from: attachment)
                    return
                }

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

        completeWithError("No content found")
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

    /// Loads an image from the attachment
    private func loadImage(from attachment: NSItemProvider) {
        statusLabel?.text = "Loading image..."

        attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.completeWithError("Failed to load image: \(error.localizedDescription)")
                    return
                }

                var image: UIImage?

                if let url = item as? URL {
                    // Image shared as file URL
                    if let data = try? Data(contentsOf: url) {
                        image = UIImage(data: data)
                    }
                } else if let data = item as? Data {
                    // Image shared as data
                    image = UIImage(data: data)
                } else if let uiImage = item as? UIImage {
                    // Image shared directly
                    image = uiImage
                }

                if let image = image {
                    self?.sharedImage = image
                    self?.performOCR(on: image)
                } else {
                    self?.completeWithError("Could not load image")
                }
            }
        }
    }

    /// Performs OCR on the image and shows recipe picker
    private func performOCR(on image: UIImage) {
        statusLabel?.text = "Extracting text..."

        guard let cgImage = image.cgImage else {
            completeWithError("Invalid image format")
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { [weak self] request, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.completeWithError("OCR failed: \(error.localizedDescription)")
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    self?.completeWithError("No text found in image")
                    return
                }

                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")

                if text.isEmpty {
                    self?.completeWithError("No text found in image")
                    return
                }

                // Clean the text
                self?.extractedOCRText = TextExtractionService.cleanDOMText(text)
                self?.showRecipePicker()
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    self.completeWithError("OCR failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Shows a picker to choose which recipe to add the OCR text to
    private func showRecipePicker() {
        activityIndicator?.stopAnimating()
        statusLabel?.text = "Select recipe"

        // Fetch recent recipes
        let recipes = fetchRecentRecipes()

        let alert = UIAlertController(
            title: "Add to Recipe",
            message: "Choose a recipe to add the extracted text to",
            preferredStyle: .actionSheet
        )

        // Add recent recipes as options
        for recipe in recipes.prefix(5) {
            let title = recipe.title.isEmpty ? "Untitled Recipe" : recipe.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.addTextToRecipe(recipe)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: NSError(
                domain: "EnkelGramShare",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cancelled"]
            ))
        })

        // For iPad
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }

    /// Fetches recent recipes from the shared database
    private func fetchRecentRecipes() -> [SavedRecipe] {
        do {
            let schema = Schema([SavedRecipe.self])
            let config = ModelConfiguration(
                schema: schema,
                url: getSharedDatabaseURL(),
                allowsSave: false
            )
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)

            var descriptor = FetchDescriptor<SavedRecipe>(
                sortBy: [SortDescriptor(\.dateSaved, order: .reverse)]
            )
            descriptor.fetchLimit = 5

            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch recipes: \(error)")
            return []
        }
    }

    /// Shows append/replace choice for adding text to a recipe
    private func addTextToRecipe(_ recipe: SavedRecipe) {
        let alert = UIAlertController(
            title: "Add Text",
            message: "How would you like to add the extracted text?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Append", style: .default) { [weak self] _ in
            self?.saveTextToRecipe(recipe, replace: false)
        })

        alert.addAction(UIAlertAction(title: "Replace", style: .destructive) { [weak self] _ in
            self?.saveTextToRecipe(recipe, replace: true)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            // Go back to recipe picker
            self?.showRecipePicker()
        })

        present(alert, animated: true)
    }

    /// Saves the OCR text to the recipe (append or replace)
    private func saveTextToRecipe(_ recipe: SavedRecipe, replace: Bool) {
        guard let ocrText = extractedOCRText else {
            completeWithError("No text to add")
            return
        }

        let recipeID = recipe.id

        do {
            let schema = Schema([SavedRecipe.self])
            let config = ModelConfiguration(
                schema: schema,
                url: getSharedDatabaseURL(),
                allowsSave: true
            )
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)

            // Fetch the recipe again in this context
            var descriptor = FetchDescriptor<SavedRecipe>(
                predicate: #Predicate<SavedRecipe> { $0.id == recipeID }
            )
            descriptor.fetchLimit = 1

            guard let existingRecipe = try context.fetch(descriptor).first else {
                completeWithError("Recipe not found")
                return
            }

            // Append or replace the body text
            if replace {
                existingRecipe.bodyText = ocrText
            } else if existingRecipe.bodyText.isEmpty {
                existingRecipe.bodyText = ocrText
            } else {
                existingRecipe.bodyText += "\n\n" + ocrText
            }

            try context.save()

            // Open main app to the recipe
            completeSuccessfully(recipeID: recipeID)

        } catch {
            completeWithError("Failed to update recipe: \(error.localizedDescription)")
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
