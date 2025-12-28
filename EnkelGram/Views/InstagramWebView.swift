//
//  InstagramWebView.swift
//  EnkelGram
//
//  A WebView wrapper that loads Instagram posts and extracts content.
//  Uses WKWebView for web content and Vision framework for OCR.
//

import SwiftUI
import WebKit
import Vision

/// A SwiftUI wrapper around WKWebView that handles Instagram content extraction.
///
/// UIViewRepresentable is a protocol that allows you to wrap UIKit views
/// (like WKWebView) for use in SwiftUI. This is necessary because SwiftUI
/// doesn't have a built-in web view.
///
struct InstagramWebView: UIViewRepresentable {

    // MARK: - Properties

    /// The URL to load
    let url: URL

    /// Callback when content has been extracted
    /// Parameters: (screenshot image, extracted text)
    let onContentLoaded: (UIImage?, String) -> Void

    /// Binding to trigger extraction - set to true to capture screenshot
    @Binding var shouldExtract: Bool

    // MARK: - UIViewRepresentable

    /// Creates the WKWebView instance
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Allow inline media playback (for videos)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Store reference so we can trigger extraction later
        context.coordinator.webView = webView

        // Load the URL
        let request = URLRequest(url: url)
        webView.load(request)

        return webView
    }

    /// Called when SwiftUI wants to update the view
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Check if extraction was triggered
        if shouldExtract {
            context.coordinator.triggerExtraction()
            // Reset the flag on the main thread
            DispatchQueue.main.async {
                self.shouldExtract = false
            }
        }
    }

    /// Creates the coordinator that handles WKWebView delegate callbacks
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Coordinator

    /// The Coordinator handles WKWebView delegate methods.
    ///
    /// In UIKit, delegates are objects that receive callbacks.
    /// The Coordinator pattern bridges UIKit delegates to SwiftUI.
    ///
    class Coordinator: NSObject, WKNavigationDelegate {

        let parent: InstagramWebView

        /// Reference to the WebView for manual extraction
        weak var webView: WKWebView?

        /// Track if we've already extracted content (to avoid duplicates)
        private var hasExtractedContent = false

        init(parent: InstagramWebView) {
            self.parent = parent
        }

        /// Called when the page finishes loading - we don't auto-extract anymore
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Page loaded - user can now navigate and press Save when ready
        }

        /// Manually trigger content extraction (called when user taps Save)
        func triggerExtraction() {
            guard let webView = webView else { return }
            // Reset flag to allow multiple saves (first for image, second for text)
            hasExtractedContent = false
            extractContent(from: webView)
        }

        /// Called if the page fails to load
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView failed to load: \(error.localizedDescription)")
            parent.onContentLoaded(nil, "Failed to load: \(error.localizedDescription)")
        }

        // MARK: - Content Extraction

        /// Extracts screenshot and text from the loaded WebView
        private func extractContent(from webView: WKWebView) {
            guard !hasExtractedContent else { return }
            hasExtractedContent = true

            // Detect if we're on the interstitial page (has "Continue on web" link)
            // or the full post page (has video/content)
            let detectPageTypeJS = """
                (function() {
                    // Check for interstitial page markers
                    var continueLink = document.querySelector('a[href*="instagram.com"]');
                    var hasOpenInstagram = document.body.innerText.includes('Open Instagram');
                    var hasContinueOnWeb = document.body.innerText.includes('Continue on web');

                    if (hasContinueOnWeb || hasOpenInstagram) {
                        return 'interstitial';
                    }
                    return 'fullpost';
                })();
            """

            webView.evaluateJavaScript(detectPageTypeJS) { [weak self] result, error in
                guard let self = self else { return }

                let pageType = result as? String ?? "fullpost"

                if pageType == "interstitial" {
                    // On interstitial page: capture the thumbnail image
                    self.captureInterstitialImage(from: webView)
                } else {
                    // On full post: extract text via OCR (scroll down to caption area)
                    self.captureFullPostText(from: webView)
                }
            }
        }

        /// Captures the thumbnail image from the interstitial page (image only, no text)
        private func captureInterstitialImage(from webView: WKWebView) {
            // Hide play button and other overlay elements before screenshot
            let hideOverlaysJS = """
                (function() {
                    // Hide SVG elements (play button icons)
                    document.querySelectorAll('svg').forEach(el => el.style.visibility = 'hidden');
                    // Hide elements with play button roles
                    document.querySelectorAll('[aria-label*="Play"], [aria-label*="play"]').forEach(el => el.style.visibility = 'hidden');
                    // Hide common overlay containers
                    document.querySelectorAll('[role="button"]').forEach(el => {
                        if (el.querySelector('svg')) el.style.visibility = 'hidden';
                    });
                })();
            """

            webView.evaluateJavaScript(hideOverlaysJS) { [weak self] _, _ in
                guard let self = self else { return }

                // Small delay to ensure CSS changes are applied
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let config = WKSnapshotConfiguration()
                    webView.takeSnapshot(with: config) { [weak self] image, error in
                        guard let self = self else { return }

                        // Restore visibility after screenshot
                        let showOverlaysJS = """
                            document.querySelectorAll('svg, [aria-label*="Play"], [aria-label*="play"], [role="button"]').forEach(el => el.style.visibility = 'visible');
                        """
                        webView.evaluateJavaScript(showOverlaysJS, completionHandler: nil)

                        guard let screenshot = image else {
                            self.parent.onContentLoaded(nil, "")
                            return
                        }

                        // Crop to just the image area (roughly middle portion of screen)
                        let croppedImage = self.cropToThumbnail(screenshot)

                        // Return image only - text comes from second save after "Continue on web"
                        DispatchQueue.main.async {
                            self.parent.onContentLoaded(croppedImage, "")
                        }
                    }
                }
            }
        }

        /// Crops the screenshot to extract just the thumbnail area
        private func cropToThumbnail(_ image: UIImage) -> UIImage {
            guard let cgImage = image.cgImage else { return image }

            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)

            // The thumbnail is roughly in the upper-middle of the screen
            // Skip top ~18% (header/nav) and bottom ~48% (shared text + buttons)
            let topInset = height * 0.18
            let bottomInset = height * 0.48
            let sideInset = width * 0.1

            let cropRect = CGRect(
                x: sideInset,
                y: topInset,
                width: width - (sideInset * 2),
                height: height - topInset - bottomInset
            )

            guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
                return image
            }

            let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)

            // Make background transparent so it adapts to dark/light mode
            return makeBackgroundTransparent(croppedImage)
        }

        /// Makes the edge background color transparent so it adapts to dark/light mode
        private func makeBackgroundTransparent(_ image: UIImage) -> UIImage {
            guard let cgImage = image.cgImage else { return image }

            let width = cgImage.width
            let height = cgImage.height

            // Create a bitmap context with alpha channel
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return image }

            // Draw the original image
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            guard let pixelData = context.data else { return image }
            let data = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)

            // Sample edge pixels to find background color (sample from corners and edges)
            let samplePoints = [
                (0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1),  // corners
                (width / 2, 0), (width / 2, height - 1), (0, height / 2), (width - 1, height / 2)  // edge midpoints
            ]

            var totalR = 0, totalG = 0, totalB = 0
            for (x, y) in samplePoints {
                let offset = (y * width + x) * 4
                totalR += Int(data[offset])
                totalG += Int(data[offset + 1])
                totalB += Int(data[offset + 2])
            }

            let bgR = UInt8(totalR / samplePoints.count)
            let bgG = UInt8(totalG / samplePoints.count)
            let bgB = UInt8(totalB / samplePoints.count)

            // Tolerance for color matching (0-255 range)
            let tolerance: Int = 30

            // Process pixels - make background transparent
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let r = Int(data[offset])
                    let g = Int(data[offset + 1])
                    let b = Int(data[offset + 2])

                    // Check if pixel matches background color within tolerance
                    if abs(r - Int(bgR)) < tolerance &&
                       abs(g - Int(bgG)) < tolerance &&
                       abs(b - Int(bgB)) < tolerance {
                        // Make transparent
                        data[offset + 3] = 0  // Alpha = 0
                    }
                }
            }

            // Create new image from modified context
            guard let newCGImage = context.makeImage() else { return image }
            return UIImage(cgImage: newCGImage, scale: image.scale, orientation: image.imageOrientation)
        }

        /// Captures text from the full post page via OCR
        private func captureFullPostText(from webView: WKWebView) {
            // Scroll down to show caption area
            let scrollJS = "window.scrollBy(0, 400);"

            webView.evaluateJavaScript(scrollJS) { [weak self] _, _ in
                guard let self = self else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.takeScreenshotForText(from: webView)
                }
            }
        }

        /// Takes screenshot and extracts text via OCR, then also tries DOM extraction
        private func takeScreenshotForText(from webView: WKWebView) {
            let config = WKSnapshotConfiguration()
            webView.takeSnapshot(with: config) { [weak self] image, error in
                guard let self = self else { return }

                guard let screenshot = image else {
                    self.parent.onContentLoaded(nil, "")
                    return
                }

                // Extract text via OCR (for title)
                self.extractText(from: screenshot) { ocrText in
                    // Also try to extract body text from DOM
                    self.extractBodyFromDOM(webView: webView) { domText in
                        DispatchQueue.main.async {
                            // Combine OCR title with DOM body
                            var finalText = ocrText
                            if !domText.isEmpty {
                                // Append DOM body if it has substantial content not in OCR
                                finalText = ocrText + "\n\n{{BODY}}" + domText
                            }
                            self.parent.onContentLoaded(nil, finalText)
                        }
                    }
                }
            }
        }

        /// Extracts body text from DOM (the full caption)
        private func extractBodyFromDOM(webView: WKWebView, completion: @escaping (String) -> Void) {
            // JavaScript to extract full caption text from Instagram's DOM
            let extractJS = """
                (function() {
                    var bestText = '';

                    // Strategy: Find the longest text block that looks like content
                    var article = document.querySelector('article') || document.querySelector('main') || document.body;
                    var allElements = article.querySelectorAll('div, span, p');

                    for (var i = 0; i < allElements.length; i++) {
                        var el = allElements[i];
                        var text = el.innerText || '';

                        // Skip short text
                        if (text.length < 50) continue;

                        // Skip UI elements
                        var lower = text.toLowerCase();
                        if (lower.includes('sign up') ||
                            lower.includes('log in') ||
                            lower.includes('open app') ||
                            lower === 'follow' ||
                            lower === 'following') {
                            continue;
                        }

                        // Keep the longest text found
                        if (text.length > bestText.length) {
                            bestText = text;
                        }
                    }

                    // Try meta description as fallback
                    if (bestText.length < 100) {
                        var metaDesc = document.querySelector('meta[property="og:description"]');
                        if (metaDesc) {
                            var metaText = metaDesc.getAttribute('content') || '';
                            if (metaText.length > bestText.length) {
                                bestText = metaText;
                            }
                        }
                    }

                    return bestText;
                })();
            """

            webView.evaluateJavaScript(extractJS) { result, error in
                let text = result as? String ?? ""
                completion(text)
            }
        }

        /// Uses Vision framework to extract text from an image
        private func extractText(from image: UIImage, completion: @escaping (String) -> Void) {
            guard let cgImage = image.cgImage else {
                completion("")
                return
            }

            // Create a Vision request handler with our image
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            // Create the text recognition request
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("Vision OCR error: \(error.localizedDescription)")
                    completion("")
                    return
                }

                // Extract the recognized text from the results
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    completion("")
                    return
                }

                // Combine all recognized text
                let recognizedStrings = observations.compactMap { observation in
                    // Get the top candidate (most likely text)
                    observation.topCandidates(1).first?.string
                }

                let fullText = recognizedStrings.joined(separator: "\n")
                completion(fullText)
            }

            // Configure the request for best accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            // Perform the request on a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try requestHandler.perform([request])
                } catch {
                    print("Failed to perform Vision request: \(error)")
                    completion("")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var shouldExtract = false

        var body: some View {
            VStack {
                InstagramWebView(
                    url: URL(string: "https://www.instagram.com")!,
                    onContentLoaded: { image, text in
                        print("Got image: \(image != nil), text: \(text.prefix(100))")
                    },
                    shouldExtract: $shouldExtract
                )
                Button("Extract") {
                    shouldExtract = true
                }
            }
        }
    }
    return PreviewWrapper()
}
