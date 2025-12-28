# EnkelGram

An iOS app for saving Instagram recipes offline. Share a recipe from Instagram, capture the thumbnail image, and extract the recipe text automatically.

## Features

- **Share Extension**: Share recipes directly from Instagram (URLs and images)
- **Two-Step Save**: Capture image and text separately for reliable results
- **Screenshot Import with OCR**: Import screenshots to extract additional recipe text
- **WebView Display**: View the original Instagram post (Live/Saved toggle)
- **OCR + DOM Extraction**: Extracts recipe title (Vision OCR) and body text (JavaScript DOM)
- **Offline Storage**: Saves images and text locally using SwiftData
- **Search**: Filter recipes by title, body text, or URL
- **Share**: Share recipes via iOS share sheet
- **Editable Content**: Edit title and body text after saving
- **Swipe to Delete**: Remove recipes from the list

## How It Works

### Two-Step Save Process

Due to iOS limitations with video content in WKWebView, the app uses a two-step save:

1. **Save Image** (on interstitial page)
   - Tap before clicking "Continue on web"
   - Captures the thumbnail image (play button automatically hidden)

2. **Save Text** (on full post)
   - Tap after the post loads
   - Extracts title via OCR + body text via DOM

### Screenshot Import

If Instagram doesn't show all the recipe text, you can import a screenshot:

**From Detail View:**
1. Open a saved recipe
2. Tap the scan icon in the toolbar (text.viewfinder)
3. Select a screenshot from Photos
4. Choose "Append" or "Replace"

**From Share Extension:**
1. Take a screenshot in Instagram
2. Share the image to EnkelGram
3. Select which recipe to add text to
4. Choose "Append" or "Replace"

### Why Two Steps?

On physical iOS devices, `WKWebView.takeSnapshot()` cannot capture video content - it renders as black. The interstitial page shows a static thumbnail that CAN be captured.

## Architecture

```
EnkelGram/
├── EnkelGramApp.swift           # App entry point, URL scheme handling
├── ContentView.swift            # Main list view with search and navigation
├── Info.plist                   # URL scheme registration (enkelgram://)
├── EnkelGram.entitlements       # App Groups entitlement
├── Models/
│   └── SavedRecipe.swift        # SwiftData model (title, bodyText, screenshot)
├── Views/
│   ├── RecipeRowView.swift      # List row component (thumbnail + title)
│   ├── RecipeDetailView.swift   # Detail view with Live/Saved toggle, editing
│   └── InstagramWebView.swift   # WKWebView wrapper with extraction
├── Services/
│   └── TextExtractionService.swift  # Vision OCR + text cleaning

EnkelGramShare/
├── ShareViewController.swift    # Handles URLs and images from Share sheet
├── Info.plist                   # Activation rules for URLs and images
```

## Technical Details

### Text Extraction

- **Title**: Vision OCR from screenshot (reliable)
- **Body**: JavaScript DOM extraction (finds longest text block)
- **Cleaning**: Filters out Instagram UI text (username, Follow, likes, comments, dates)

### Screenshot Capture

- Play button and overlays are hidden via JavaScript before capture
- Image is cropped to remove Instagram header and footer
- Supports both interstitial and full post pages

### Data Flow

```
Share from Instagram → Interstitial page loads
        ↓
"Save Image" → Captures & crops thumbnail (play button hidden)
        ↓
"Continue on web" → Full post loads
        ↓
"Save Text" → OCR title + DOM body extraction
        ↓
Recipe saved with image + combined text
        ↓
(Optional) Import screenshot for additional text
```

### Key Technologies

| Technology | Purpose |
|------------|---------|
| SwiftUI | Declarative UI |
| SwiftData | Persistence (iOS 17+) |
| WKWebView | Display Instagram posts |
| Vision | OCR text extraction |
| PhotosUI | Screenshot import picker |
| App Groups | Share data with extension |
| URL Schemes | Deep linking |

### App Groups

Both targets share: `group.com.enkel.EnkelGram`

### URL Scheme

```
enkelgram://recipe/{UUID}
```

Used by Share Extension to open the main app and navigate to the saved recipe.

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Setup

1. Open `EnkelGram.xcodeproj` in Xcode
2. Configure signing for both targets:
   - Select project → EnkelGram target → Signing & Capabilities
   - Select your Team
   - Repeat for EnkelGramShare target
3. Ensure App Groups is configured:
   - Both targets should have `group.com.enkel.EnkelGram`
4. Build and run (Cmd + R)

**Note**: With a free Apple Developer account, the app expires after 7 days and needs to be reinstalled.

## Testing

### On Simulator

Works fully - both image and text extraction.

### On Physical Device

Use the two-step save process for video posts.

### Unit Tests

Run with Cmd + U in Xcode. Tests cover:
- URL validation
- Caption extraction
- DOM text cleaning

## Known Limitations

1. **Video Screenshots**: Black on physical devices (iOS limitation) - use two-step save
2. **Caption Truncation**: DOM extraction gets what Instagram loads
3. **"More" Button**: Cannot click programmatically (opens Instagram app)
4. **Free Developer Account**: App expires after 7 days
