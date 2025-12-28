//
//  InstagramWebView.swift
//  EnkelGram
//
//  A WebView wrapper that loads Instagram posts and extracts content.
//  Uses WKWebView for web content. OCR is delegated to TextExtractionService.
//

import SwiftUI
import WebKit

/// A SwiftUI wrapper around WKWebView that handles Instagram content extraction.
///
/// UIViewRepresentable is a protocol that allows you to wrap UIKit views
/// (like WKWebView) for use in SwiftUI. This is necessary because SwiftUI
/// doesn't have a built-in web view.
///
struct InstagramWebView: UIViewRepresentable {

    // MARK: - Constants

    /// Cropping percentages for extracting the thumbnail from Instagram's interstitial page.
    /// These values are calibrated for Instagram's current layout (as of 2024).
    private enum CropInsets {
        /// Skip top 18% - removes Instagram header and navigation bar
        static let top: CGFloat = 0.18
        /// Skip bottom 48% - removes "shared this reel" text and action buttons
        static let bottom: CGFloat = 0.48
        /// Skip 10% from each side - removes page margins
        static let sides: CGFloat = 0.10
    }

    /// Settings for making the image background transparent
    private enum BackgroundRemoval {
        /// Color tolerance for matching background pixels (0-255 range).
        /// Higher values = more aggressive removal, but may affect actual content.
        /// 30 works well for Instagram's grey/white backgrounds.
        static let colorTolerance: Int = 30
    }

    /// Scroll distance in pixels when loading the full post page.
    /// This scrolls past the image to show the caption area for OCR.
    private static let captionScrollDistance: Int = 400

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

        /// Crops the screenshot to extract just the thumbnail area from Instagram's page.
        ///
        /// Instagram's interstitial page has this layout:
        /// ```
        /// ┌─────────────────────┐
        /// │  Instagram header   │ ← Skip (CropInsets.top)
        /// │                     │
        /// │    ┌───────────┐    │
        /// │    │ Thumbnail │    │ ← Keep this area
        /// │    └───────────┘    │
        /// │                     │
        /// │ "Shared this reel"  │ ← Skip (CropInsets.bottom)
        /// │  [Open Instagram]   │
        /// └─────────────────────┘
        /// ```
        private func cropToThumbnail(_ image: UIImage) -> UIImage {
            guard let cgImage = image.cgImage else { return image }

            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)

            // Calculate crop area using our calibrated inset values
            let topInset = height * CropInsets.top
            let bottomInset = height * CropInsets.bottom
            let sideInset = width * CropInsets.sides

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

        /// Makes the edge background color transparent so the image adapts to dark/light mode.
        ///
        /// ## Why This Is Needed
        /// Instagram screenshots have a solid background color (grey in dark mode, white in light mode).
        /// When the user switches modes, this baked-in background looks wrong. By making it transparent,
        /// the app's actual background shows through and adapts naturally.
        ///
        /// ## How It Works (Algorithm)
        /// ```
        /// 1. Sample 8 edge pixels (corners + midpoints)
        ///    ┌──────┬──────┐
        ///    │ •    •    • │ ← sample points
        ///    │             │
        ///    │ •         • │
        ///    │             │
        ///    │ •    •    • │
        ///    └──────┴──────┘
        ///
        /// 2. Average their RGB values to get the background color
        ///
        /// 3. Loop through every pixel in the image:
        ///    - If pixel color ≈ background color (within tolerance), make it transparent
        ///    - Otherwise, keep the pixel as-is
        /// ```
        ///
        /// ## Memory Layout
        /// Each pixel is 4 bytes: [Red, Green, Blue, Alpha]
        /// - Offset + 0 = Red (0-255)
        /// - Offset + 1 = Green (0-255)
        /// - Offset + 2 = Blue (0-255)
        /// - Offset + 3 = Alpha (0 = transparent, 255 = opaque)
        ///
        private func makeBackgroundTransparent(_ image: UIImage) -> UIImage {
            guard let cgImage = image.cgImage else { return image }

            let width = cgImage.width
            let height = cgImage.height

            // Create a bitmap context (an in-memory canvas) with alpha channel support.
            // CGContext lets us read and modify individual pixels.
            guard let context = CGContext(
                data: nil,                                              // Let system allocate memory
                width: width,
                height: height,
                bitsPerComponent: 8,                                    // 8 bits per color channel
                bytesPerRow: width * 4,                                 // 4 bytes per pixel (RGBA)
                space: CGColorSpaceCreateDeviceRGB(),                   // RGB color space
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue // RGBA format with alpha at end
            ) else { return image }

            // Draw the original image into our bitmap context
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            // Get raw pixel data as a byte array
            guard let pixelData = context.data else { return image }
            let data = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)

            // Step 1: Sample edge pixels to detect the background color
            // We sample 8 points: 4 corners + 4 edge midpoints
            let samplePoints = [
                (0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1),  // corners
                (width / 2, 0), (width / 2, height - 1), (0, height / 2), (width - 1, height / 2)  // edge midpoints
            ]

            // Step 2: Calculate average color from sample points
            var totalR = 0, totalG = 0, totalB = 0
            for (x, y) in samplePoints {
                let offset = (y * width + x) * 4  // Calculate byte position for this pixel
                totalR += Int(data[offset])       // Red
                totalG += Int(data[offset + 1])   // Green
                totalB += Int(data[offset + 2])   // Blue
            }

            // Average RGB values = our detected background color
            let bgR = UInt8(totalR / samplePoints.count)
            let bgG = UInt8(totalG / samplePoints.count)
            let bgB = UInt8(totalB / samplePoints.count)

            // Use the calibrated tolerance from our constants
            let tolerance = BackgroundRemoval.colorTolerance

            // Step 3: Process every pixel - make background-colored pixels transparent
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let r = Int(data[offset])
                    let g = Int(data[offset + 1])
                    let b = Int(data[offset + 2])

                    // Check if this pixel matches the background color (within tolerance)
                    // If all RGB values are close to the background, it's a background pixel
                    if abs(r - Int(bgR)) < tolerance &&
                       abs(g - Int(bgG)) < tolerance &&
                       abs(b - Int(bgB)) < tolerance {
                        // Make this pixel transparent by setting alpha to 0
                        data[offset + 3] = 0
                    }
                }
            }

            // Step 4: Create new image from modified pixel data
            guard let newCGImage = context.makeImage() else { return image }
            return UIImage(cgImage: newCGImage, scale: image.scale, orientation: image.imageOrientation)
        }

        /// Captures text from the full post page via OCR
        private func captureFullPostText(from webView: WKWebView) {
            // Scroll down to show caption area (uses calibrated distance)
            let scrollJS = "window.scrollBy(0, \(InstagramWebView.captionScrollDistance));"

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

        /// Extracts text from an image using the shared TextExtractionService.
        /// This ensures consistent OCR configuration (languages, accuracy) across the app.
        private func extractText(from image: UIImage, completion: @escaping (String) -> Void) {
            TextExtractionService.shared.extractText(from: image, completion: completion)
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
