# ProjectorAI

An AI-powered whiteboard tutoring system for iOS that captures whiteboard content, analyzes it with AI, and projects intelligent annotations back onto the whiteboard.

## Overview

ProjectorAI transforms any whiteboard into an intelligent tutoring surface. Point your iPhone at a whiteboard, and the AI can:

- **Analyze** - Understand what's written (math problems, diagrams, code, etc.)
- **Annotate** - Generate helpful overlays with hints, solutions, labels, or corrections
- **Talk** - Have voice conversations about the whiteboard content in real-time

The app uses a two-model architecture:
1. **Understanding Model** (GPT-4o) - Analyzes whiteboard content
2. **Generation Model** (OpenAI GPT-Image-1 / Gemini) - Creates annotated images with overlays baked in

## Features

### Core Capabilities

- **Camera Capture** - Real-time 1920x1080 camera feed with live preview
- **External Display Support** - Project content via HDMI/USB-C or AirPlay
- **AI Image Analysis** - Single-frame analysis using GPT-4o
- **AI Image Generation** - Generate annotated whiteboard images
- **Voice Interaction** - Real-time voice conversations using OpenAI Realtime API
- **Animated Projections** - Multiple animation styles for projector display

### Annotation Types

| Type | Description |
|------|-------------|
| **Hint** | Subtle hints about where to start, without giving away the answer |
| **Solve Step** | Shows the next step only (not the full solution) |
| **Label** | Identifies and labels key components with arrows |
| **Correct Errors** | Highlights mistakes in red, shows corrections in green |
| **Explain** | Adds educational explanations like a tutor would |

### Projector Animations

- Typewriter - Text appears character by character
- Fade In - Smooth fade-in effect
- Slide In - Content slides from the side
- Scale Up - Content grows from center
- Bounce - Playful bouncing entrance
- Glow - Pulsing glow effect

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iPhone Camera                        │
│                    (1920x1080)                          │
├─────────────────────────────────────────────────────────┤
│                         │                               │
│                         ▼                               │
│  ┌─────────────────────────────────────────────────┐   │
│  │              CameraManager                       │   │
│  │  • AVCaptureSession management                  │   │
│  │  • Frame capture & preview layer                │   │
│  └─────────────────────────────────────────────────┘   │
│                         │                               │
│           ┌─────────────┼─────────────┐                │
│           ▼             ▼             ▼                │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐      │
│  │ OpenAI      │ │ OpenAI      │ │ OpenAI      │      │
│  │ Service     │ │ Realtime    │ │ Image       │      │
│  │ (GPT-4o)    │ │ Service     │ │ Service     │      │
│  │             │ │ (Voice)     │ │ (GPT-Image) │      │
│  │ • Analyze   │ │ • Voice AI  │ │ • Annotate  │      │
│  └─────────────┘ └─────────────┘ └─────────────┘      │
│           │             │             │                │
│           └─────────────┼─────────────┘                │
│                         ▼                               │
│  ┌─────────────────────────────────────────────────┐   │
│  │         ExternalDisplayManager                   │   │
│  │  • Projector connection detection               │   │
│  │  • Content rendering & animations               │   │
│  │  • Generated image display                      │   │
│  └─────────────────────────────────────────────────┘   │
│                         │                               │
│                         ▼                               │
│              ┌───────────────────────┐                 │
│              │   External Display    │                 │
│              │   (Projector/Monitor) │                 │
│              └───────────────────────┘                 │
└─────────────────────────────────────────────────────────┘
```

## Project Structure

```
ProjectorAI/
├── ProjectorAI.xcodeproj/          # Xcode project
│   ├── project.pbxproj
│   └── xcshareddata/
│       └── xcschemes/
│           └── ProjectorAI.xcscheme
├── ProjectorAI/
│   ├── ProjectorAIApp.swift        # App entry point
│   ├── ContentView.swift           # Main UI
│   ├── CameraManager.swift         # Camera capture
│   ├── ExternalDisplayManager.swift # Projector display
│   ├── OpenAIService.swift         # GPT-4o analysis
│   ├── OpenAIRealtimeService.swift # Voice AI
│   ├── OpenAIImageService.swift    # Image generation (active)
│   ├── GeminiImageService.swift    # Image generation (backup)
│   ├── Assets.xcassets/            # App assets
│   └── Info.plist                  # App configuration
├── README.md                       # This file
├── PROJECT.md                      # Project management
└── .gitignore
```

## Requirements

- **Device**: iPhone with iOS 17.0+
- **Hardware**: Camera, microphone access
- **External Display**: Optional - HDMI adapter or AirPlay
- **APIs**: OpenAI API key (for GPT-4o, Realtime, and Image generation)

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/sumitrana31/ProjectorAI.git
   ```

2. Open in Xcode:
   ```bash
   cd ProjectorAI
   open ProjectorAI/ProjectorAI.xcodeproj
   ```

3. **Configure API Keys** (Required):

   Get your OpenAI API key from: https://platform.openai.com/api-keys

   Then replace `YOUR_OPENAI_API_KEY_HERE` in these files:
   - `ProjectorAI/OpenAIService.swift` (line 18)
   - `ProjectorAI/OpenAIRealtimeService.swift` (line 22)
   - `ProjectorAI/OpenAIImageService.swift` (line 19)

   (Optional) For Gemini backup, get key from: https://aistudio.google.com/apikey
   - `ProjectorAI/GeminiImageService.swift` (line 18)

4. Build and run on your iPhone

> **Note**: Never commit your actual API keys to git. The placeholder values are intentional for security.

## Usage

### Basic Workflow

1. **Connect Projector** (optional) - Connect external display via HDMI or AirPlay
2. **Point Camera** - Aim at whiteboard content
3. **Choose Action**:
   - **Analyze** - Get AI analysis of the content
   - **Annotate** - Generate annotated image with selected overlay type
   - **Talk** - Start voice conversation about the content

### Swapping Image Generation Provider

The app supports both OpenAI and Gemini for image generation. To swap:

In `ContentView.swift`, change:
```swift
// From OpenAI:
@State private var selectedOverlayType: OpenAIImageService.OverlayType = .hint
isLoading: openAIImageService.isGenerating
try await openAIImageService.generateAnnotatedImage(...)

// To Gemini:
@State private var selectedOverlayType: GeminiImageService.OverlayType = .hint
isLoading: geminiImageService.isGenerating
try await geminiImageService.generateAnnotatedImage(...)
```

## API Services

### OpenAI Services

| Service | Model | Purpose |
|---------|-------|---------|
| OpenAIService | gpt-4o | Image analysis, text responses |
| OpenAIRealtimeService | gpt-4o-realtime | Voice conversations |
| OpenAIImageService | gpt-image-1 | Annotated image generation |

### Gemini Services (Backup)

| Service | Model | Purpose |
|---------|-------|---------|
| GeminiImageService | gemini-2.5-flash-image | Annotated image generation |

## Hardware Optimization

Optimized for iPhone Pro models:
- **A18 Pro Neural Engine** - Fast on-device processing
- **48MP Camera** - High-resolution whiteboard capture
- **USB-C** - Direct HDMI output to projector
- **ProMotion Display** - Smooth 120Hz UI

## License

MIT License - See LICENSE file for details.

## Author

**Sumit Rana** ([@sumitrana31](https://github.com/sumitrana31))

---

Built with SwiftUI, AVFoundation, and OpenAI APIs.
