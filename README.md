# EnkelGram

An iOS app for saving Instagram recipes offline. Share a recipe from Instagram, capture the thumbnail image, and extract the recipe text automatically.

## Features

- **Share Extension**: Share recipes directly from Instagram
- **Two-Step Save**: Capture image and text separately for reliable results
- **WebView Display**: View the original Instagram post
- **OCR + DOM Extraction**: Extracts recipe title (Vision OCR) and body text (JavaScript DOM)
- **Offline Storage**: Saves images and text locally using SwiftData
- **Swipe to Delete**: Remove recipes from the list

## How It Works

### Two-Step Save Process

Due to iOS limitations with video content in WKWebView, the app uses a two-step save:

1. **Save Image** (on interstitial page)
   - Tap before clicking "Continue on web"
   - Captures the thumbnail image

2. **Save Text** (on full post)
   - Tap after the post loads
   - Extracts title via OCR + body text via DOM

### Why Two Steps?

On physical iOS devices, `WKWebView.takeSnapshot()` cannot capture video content - it renders as black. The interstitial page shows a static thumbnail that CAN be captured.

## Architecture

```
EnkelGram/
├── EnkelGramApp.swift           # App entry point, URL scheme handling
├── ContentView.swift            # Main list view with navigation
├── Info.plist                   # URL scheme registration (enkelgram://)
├── EnkelGram.entitlements       # App Groups entitlement
├── Models/
│   └── SavedRecipe.swift        # SwiftData model
├── Views/
│   ├── RecipeRowView.swift      # List row component
│   ├── RecipeDetailView.swift   # Detail view with Save buttons
│   └── InstagramWebView.swift   # WKWebView wrapper with extraction
├── Services/
│   └── TextExtractionService.swift  # Vision OCR + text cleaning
```

## Technical Details

### Text Extraction

- **Title**: Vision OCR from screenshot (reliable)
- **Body**: JavaScript DOM extraction (finds longest text block)
- **Cleaning**: Filters out Instagram UI text (likes, comments, dates)

### Data Flow

```
Share from Instagram → Interstitial page loads
        ↓
"Save Image" → Captures & crops thumbnail
        ↓
"Continue on web" → Full post loads
        ↓
"Save Text" → OCR title + DOM body extraction
        ↓
Recipe saved with image + combined text
```

### Key Technologies

| Technology | Purpose |
|------------|---------|
| SwiftUI | Declarative UI |
| SwiftData | Persistence (iOS 17+) |
| WKWebView | Display Instagram posts |
| Vision | OCR text extraction |
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

## Testing

### On Simulator

Works fully - both image and text extraction.

### On Physical Device

Use the two-step save process for video posts. See [../TESTING_ON_DEVICE.md](../TESTING_ON_DEVICE.md) for detailed instructions.

### Unit Tests

Run with Cmd + U in Xcode.

## Known Limitations

1. **Video Screenshots**: Black on physical devices (iOS limitation)
2. **Caption Truncation**: DOM extraction gets what Instagram loads
3. **"More" Button**: Cannot click programmatically (opens Instagram app)
