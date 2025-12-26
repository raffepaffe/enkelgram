//
//  TextExtractionService.swift
//  EnkelGram
//
//  Service for extracting text from images using Vision OCR.
//  Separated into its own file for testability and reusability.
//

import UIKit
import Vision

/// A service that extracts text from images using Apple's Vision framework.
///
/// This is a "service" - a class focused on a single responsibility.
/// By separating this logic, we can:
/// - Test it independently
/// - Reuse it in different parts of the app
/// - Replace it with a different implementation if needed
///
final class TextExtractionService {

    // MARK: - Singleton

    /// Shared instance for convenience (optional pattern)
    static let shared = TextExtractionService()

    // MARK: - Public Methods

    /// Extracts text from an image using Vision OCR.
    ///
    /// - Parameters:
    ///   - image: The UIImage to extract text from
    ///   - completion: Called with the extracted text (may be empty if no text found)
    ///
    /// Example:
    /// ```swift
    /// TextExtractionService.shared.extractText(from: screenshot) { text in
    ///     print("Found text: \(text)")
    /// }
    /// ```
    func extractText(from image: UIImage, completion: @escaping (String) -> Void) {
        guard let cgImage = image.cgImage else {
            completion("")
            return
        }

        extractText(from: cgImage, completion: completion)
    }

    /// Extracts text from a CGImage (lower-level API).
    ///
    /// - Parameters:
    ///   - cgImage: The CGImage to process
    ///   - completion: Called with the extracted text
    func extractText(from cgImage: CGImage, completion: @escaping (String) -> Void) {
        // Create the request handler
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Create the text recognition request
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("Vision OCR error: \(error.localizedDescription)")
                completion("")
                return
            }

            // Process results
            let text = self.processResults(request.results)
            completion(text)
        }

        // Configure for best accuracy
        configureRequest(request)

        // Perform the request on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                print("Failed to perform Vision request: \(error)")
                DispatchQueue.main.async {
                    completion("")
                }
            }
        }
    }

    /// Synchronous version for testing (blocks until complete).
    ///
    /// - Warning: Do not use on main thread in production!
    /// - Parameter cgImage: The image to process
    /// - Returns: Extracted text
    func extractTextSync(from cgImage: CGImage) -> String {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        var extractedText = ""
        let request = VNRecognizeTextRequest { request, error in
            if error == nil {
                extractedText = self.processResults(request.results)
            }
        }

        configureRequest(request)

        do {
            try requestHandler.perform([request])
        } catch {
            print("Vision request failed: \(error)")
        }

        return extractedText
    }

    // MARK: - Private Methods

    /// Configures the text recognition request for optimal results.
    private func configureRequest(_ request: VNRecognizeTextRequest) {
        // Use accurate recognition (slower but better results)
        request.recognitionLevel = .accurate

        // Enable language correction (helps with spelling)
        request.usesLanguageCorrection = true

        // Recognize multiple languages
        request.recognitionLanguages = ["en-US", "sv-SE", "de-DE", "fr-FR", "es-ES", "it-IT"]
    }

    /// Processes Vision results into a single string.
    private func processResults(_ results: [Any]?) -> String {
        guard let observations = results as? [VNRecognizedTextObservation] else {
            return ""
        }

        // Extract the top candidate from each observation
        let recognizedStrings = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }

        // Join all lines with newlines
        return recognizedStrings.joined(separator: "\n")
    }
}

// MARK: - URL Validation Helper

extension TextExtractionService {

    /// Checks if a string looks like a valid Instagram URL.
    ///
    /// - Parameter urlString: The string to validate
    /// - Returns: True if it looks like an Instagram URL
    static func isValidInstagramURL(_ urlString: String) -> Bool {
        let patterns = [
            "instagram.com/p/",
            "instagram.com/reel/",
            "instagram.com/tv/",
            "instagr.am/"
        ]

        let lowercased = urlString.lowercased()
        return patterns.contains { lowercased.contains($0) }
    }
}

// MARK: - Caption Extraction Helper

extension TextExtractionService {

    /// Extracts the caption text from raw OCR output, filtering out Instagram UI elements.
    ///
    /// - Parameter rawText: The raw OCR text from a screenshot
    /// - Returns: The cleaned caption text
    static func extractCaption(from rawText: String) -> String {
        // Split into lines
        let lines = rawText.components(separatedBy: .newlines)

        // Strategy 1: Look for a line ending with "more" - this is typically the caption
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lowercased = trimmed.lowercased()

            // Caption lines typically end with "... more" or "…more"
            if lowercased.hasSuffix("more") || lowercased.hasSuffix("...") || lowercased.hasSuffix("…") {
                let cleaned = trimmed
                    .replacingOccurrences(of: "... more", with: "")
                    .replacingOccurrences(of: "...more", with: "")
                    .replacingOccurrences(of: "… more", with: "")
                    .replacingOccurrences(of: "…more", with: "")
                    .replacingOccurrences(of: "...", with: "")
                    .replacingOccurrences(of: "…", with: "")
                    .trimmingCharacters(in: .whitespaces)

                // Make sure it's substantial content (not just "more" or a short word)
                if cleaned.count > 5 && !isUIElement(cleaned) {
                    return cleaned
                }
            }
        }

        // Strategy 2: Look for lines that look like recipe content
        // (contains colon, bullet points, or is longer descriptive text)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip short lines and UI elements
            if trimmed.count < 10 { continue }
            if isUIElement(trimmed) { continue }

            // Lines with colons or bullet points are likely captions
            if trimmed.contains(":") || trimmed.contains("•") || trimmed.contains("·") {
                // Make sure it's not just "username • Follow"
                let lowercased = trimmed.lowercased()
                if !lowercased.contains("follow") && !lowercased.contains("sign up") {
                    return cleanCaption(trimmed)
                }
            }
        }

        // Strategy 3: Find the longest non-UI line (likely the caption)
        var bestLine = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.count > bestLine.count && trimmed.count > 15 && !isUIElement(trimmed) {
                bestLine = trimmed
            }
        }

        return cleanCaption(bestLine)
    }

    /// Checks if a line looks like Instagram UI rather than content
    private static func isUIElement(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        let uiPatterns = [
            "instagram", "log in", "sign up", "follow", "following",
            "open app", "continue on web", "see more from",
            "sign up for instagram", "see photos", "see videos",
            "watch this reel", "view all", "add a comment",
            "terms of use", "privacy policy", "report content",
            "liked by", "view all comments"
        ]

        // Check if the text IS a UI element or STARTS WITH a UI element
        for pattern in uiPatterns {
            if lowercased == pattern { return true }
            if lowercased.hasPrefix(pattern + " ") { return true }
            if lowercased == pattern + " •" { return true }
        }

        // Check for username patterns like "username • Follow" or "username •"
        // These typically are short and contain • followed by nothing or "Follow"
        if lowercased.contains(" • follow") { return true }
        if lowercased.hasSuffix(" •") && text.count < 20 { return true }

        return false
    }

    /// Cleans up a caption by removing trailing "more" and other artifacts
    private static func cleanCaption(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "... more", with: "")
            .replacingOccurrences(of: "...more", with: "")
            .replacingOccurrences(of: "… more", with: "")
            .replacingOccurrences(of: "…more", with: "")
            .replacingOccurrences(of: " more$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
