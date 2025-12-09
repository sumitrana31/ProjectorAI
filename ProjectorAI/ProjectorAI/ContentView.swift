//
//  ContentView.swift
//  ProjectorAI
//
//  Main UI with camera preview, controls, and AI response display
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var externalDisplayManager: ExternalDisplayManager
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var openAIService: OpenAIService
    @EnvironmentObject var openAIRealtimeService: OpenAIRealtimeService
    @EnvironmentObject var geminiImageService: GeminiImageService
    @EnvironmentObject var openAIImageService: OpenAIImageService

    @State private var aiResponse: String = ""
    @State private var isVoiceActive: Bool = false
    @State private var userTranscript: String = ""
    @State private var aiTranscript: String = ""
    @State private var showSettings: Bool = false
    @State private var selectedAnimation: ProjectorAnimation = .typewriter
    @State private var showAnimationPicker: Bool = false

    // Annotation states - using OpenAI now (can swap to Gemini)
    @State private var selectedOverlayType: OpenAIImageService.OverlayType = .hint
    @State private var showAnnotationPreview: Bool = false
    @State private var annotationError: String?

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black, Color(hex: "1a1a2e")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerView

                    // Camera Preview Card
                    cameraPreviewCard

                    // Control Buttons
                    controlButtonsSection

                    // Projector Animation Controls
                    if externalDisplayManager.isExternalDisplayConnected {
                        projectorAnimationSection
                    } else {
                        projectorDisconnectedHint
                    }

                    // Voice Conversation Card (when voice is active)
                    if isVoiceActive {
                        voiceConversationCard
                    }

                    // AI Response Card (Single Analysis)
                    if !aiResponse.isEmpty && !isVoiceActive {
                        aiResponseCard
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
        }
        .onAppear {
            cameraManager.requestCameraPermission { granted in
                if granted {
                    cameraManager.startSession()
                }
            }

            // Setup callbacks
            openAIRealtimeService.onTranscript = { transcript in
                userTranscript = transcript
            }

            openAIRealtimeService.onResponse = { response in
                aiTranscript = response
                if externalDisplayManager.isExternalDisplayConnected {
                    externalDisplayManager.updateAIResponse(response)
                }
            }

            // Provide camera frame access to realtime service
            openAIRealtimeService.frameProvider = { [weak cameraManager] in
                return cameraManager?.captureCurrentFrame()
            }
        }
        .onDisappear {
            cameraManager.stopSession()
            openAIRealtimeService.disconnect()
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("ProjectorAI")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("AI Whiteboard Tutor")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Status badges
            VStack(alignment: .trailing, spacing: 4) {
                // External display status
                HStack(spacing: 8) {
                    Circle()
                        .fill(externalDisplayManager.isExternalDisplayConnected ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)

                    Text(externalDisplayManager.isExternalDisplayConnected ? "Projector" : "No Display")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "2d2d44"))
                .cornerRadius(20)

                // OpenAI connection status
                if openAIRealtimeService.isConnected {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }

            // Settings button
            Button(action: { showSettings.toggle() }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .padding(.leading, 8)
        }
        .padding(.top, 8)
    }

    // MARK: - Camera Preview Card
    private var cameraPreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Camera Feed")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                // Live indicator
                if cameraManager.isRunning {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                }

                // Resolution badge
                Text(cameraManager.currentResolution)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "3d3d54"))
                    .cornerRadius(4)
            }

            // Camera preview
            ZStack {
                if cameraManager.previewLayer != nil {
                    CameraPreviewView(cameraManager: cameraManager)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(12)
                } else {
                    Rectangle()
                        .fill(Color(hex: "2d2d44"))
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(12)
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("Camera Loading...")
                                    .foregroundColor(.gray)
                            }
                        )
                }

                // Speaking indicator overlay
                if openAIRealtimeService.isSpeaking {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Image(systemName: "waveform")
                                    .foregroundColor(.white)
                                Text("Listening...")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(20)
                            .padding(12)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(hex: "2d2d44").opacity(0.5))
        .cornerRadius(16)
    }

    // MARK: - Control Buttons Section
    private var controlButtonsSection: some View {
        VStack(spacing: 16) {
            // Three main buttons
            HStack(spacing: 12) {
                // Analyze button - single frame analysis
                ActionButton(
                    title: "Analyze",
                    subtitle: "Capture & analyze",
                    icon: "camera.viewfinder",
                    color: .purple,
                    isLoading: openAIService.isAnalyzing,
                    size: .medium
                ) {
                    analyzeBoard()
                }

                // Annotate button - AI image generation (OpenAI)
                ActionButton(
                    title: "Annotate",
                    subtitle: "AI overlay",
                    icon: "pencil.tip.crop.circle.badge.plus",
                    color: .orange,
                    isLoading: openAIImageService.isGenerating,
                    size: .medium
                ) {
                    generateAnnotation()
                }

                // Talk button - voice conversation
                ActionButton(
                    title: isVoiceActive ? "End" : "Talk",
                    subtitle: isVoiceActive ? "Stop" : "Voice AI",
                    icon: isVoiceActive ? "stop.fill" : "mic.fill",
                    color: isVoiceActive ? .red : .green,
                    size: .medium
                ) {
                    toggleVoiceMode()
                }
            }

            // Overlay type selector (when projector connected)
            if externalDisplayManager.isExternalDisplayConnected {
                overlayTypeSelector
            }
        }
    }

    // MARK: - Overlay Type Selector
    private var overlayTypeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Annotation Type")
                .font(.caption)
                .foregroundColor(.gray)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(OpenAIImageService.OverlayType.allCases) { type in
                        OverlayTypeButton(
                            type: type,
                            isSelected: selectedOverlayType == type
                        ) {
                            selectedOverlayType = type
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(hex: "2d2d44").opacity(0.3))
        .cornerRadius(12)
    }

    // MARK: - Voice Conversation Card
    private var voiceConversationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(openAIRealtimeService.isListening ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(openAIRealtimeService.isListening ? "Voice Active" : "Connecting...")
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Spacer()

                // Pulsing mic indicator when speaking
                if openAIRealtimeService.isSpeaking {
                    Image(systemName: "waveform")
                        .foregroundColor(.green)
                        .font(.title2)
                }
            }

            // User's transcript
            if !userTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.cyan)
                        Text("You:")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Text(userTranscript)
                        .font(.body)
                        .foregroundColor(.white)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cyan.opacity(0.1))
                .cornerRadius(12)
            }

            // AI's response
            if !aiTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        Text("AI:")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Text(aiTranscript)
                        .font(.body)
                        .foregroundColor(.white)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(12)
            }

            // Hint text
            if userTranscript.isEmpty && aiTranscript.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Start speaking...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("Point camera at whiteboard and ask questions")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            }
        }
        .padding()
        .background(Color(hex: "2d2d44").opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Projector Disconnected Hint
    private var projectorDisconnectedHint: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "rectangle.on.rectangle.slash")
                    .foregroundColor(.orange)
                Text("Projector Not Connected")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }

            Text("Connect an external display via HDMI or AirPlay to see animation controls and project content to your whiteboard.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color(hex: "2d2d44").opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Projector Animation Section
    private var projectorAnimationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundColor(.cyan)
                Text("Projector Animations")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                // Stop button if animating
                if externalDisplayManager.content.isAnimating {
                    Button(action: {
                        externalDisplayManager.stopAnimation()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(8)
                    }
                }
            }

            // Animation picker grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(ProjectorAnimation.allCases.filter { $0 != .none }) { animation in
                    AnimationPickerButton(
                        animation: animation,
                        isSelected: selectedAnimation == animation,
                        isPlaying: externalDisplayManager.content.currentAnimation == animation && externalDisplayManager.content.isAnimating
                    ) {
                        selectedAnimation = animation
                        externalDisplayManager.playAnimation(animation)
                    }
                }
            }

            // Currently playing indicator
            if externalDisplayManager.content.isAnimating {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Playing: \(externalDisplayManager.content.currentAnimation.rawValue)")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(hex: "2d2d44").opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - AI Response Card
    private var aiResponseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Analysis")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                // Project button
                Button(action: {
                    externalDisplayManager.updateAIResponse(aiResponse)
                    externalDisplayManager.setLiveMode(false)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                        Text("Project")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple)
                    .cornerRadius(8)
                }
                .disabled(!externalDisplayManager.isExternalDisplayConnected)
                .opacity(externalDisplayManager.isExternalDisplayConnected ? 1 : 0.5)
            }

            ScrollView {
                Text(aiResponse)
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .background(Color(hex: "2d2d44").opacity(0.5))
        .cornerRadius(16)
    }

    // MARK: - Actions

    private func analyzeBoard() {
        guard let frame = cameraManager.captureCurrentFrame() else {
            aiResponse = "Could not capture camera frame"
            return
        }

        Task {
            do {
                let response = try await openAIService.analyzeImage(frame)
                await MainActor.run {
                    aiResponse = response
                }
            } catch {
                await MainActor.run {
                    aiResponse = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func toggleVoiceMode() {
        if isVoiceActive {
            // Stop voice mode
            openAIRealtimeService.stopListening()
            openAIRealtimeService.disconnect()
            isVoiceActive = false
            userTranscript = ""
            aiTranscript = ""
        } else {
            // Start voice mode
            isVoiceActive = true
            userTranscript = ""
            aiTranscript = ""
            openAIRealtimeService.startListening()
        }
    }

    private func generateAnnotation() {
        guard let frame = cameraManager.captureCurrentFrame() else {
            annotationError = "Could not capture camera frame"
            return
        }

        annotationError = nil

        Task {
            do {
                // Using OpenAI for image generation (swap to geminiImageService if needed)
                let annotatedImage = try await openAIImageService.generateAnnotatedImage(
                    from: frame,
                    overlayType: selectedOverlayType
                )

                await MainActor.run {
                    // Display on projector if connected
                    if externalDisplayManager.isExternalDisplayConnected {
                        externalDisplayManager.displayGeneratedImage(annotatedImage)
                    }
                    showAnnotationPreview = true
                }
            } catch {
                await MainActor.run {
                    annotationError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Action Button Component
struct ActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var isLoading: Bool = false
    var size: ButtonSize = .medium
    var isDisabled: Bool = false
    let action: () -> Void

    enum ButtonSize {
        case medium, large

        var iconSize: CGFloat {
            switch self {
            case .medium: return 24
            case .large: return 32
            }
        }

        var titleSize: CGFloat {
            switch self {
            case .medium: return 16
            case .large: return 20
            }
        }

        var padding: CGFloat {
            switch self {
            case .medium: return 16
            case .large: return 20
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: size.iconSize, height: size.iconSize)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: size.titleSize, weight: .semibold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                if size == .large {
                    Spacer()
                }
            }
            .padding(size.padding)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
        }
        .disabled(isLoading || isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: - Animation Picker Button Component
struct AnimationPickerButton: View {
    let animation: ProjectorAnimation
    let isSelected: Bool
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isPlaying ? Color.cyan.opacity(0.3) : Color(hex: "3d3d54"))
                        .frame(height: 60)

                    Image(systemName: animation.icon)
                        .font(.system(size: 24))
                        .foregroundColor(isPlaying ? .cyan : .white)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isPlaying ? Color.cyan : Color.clear, lineWidth: 2)
                )

                Text(animation.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isPlaying ? .cyan : .gray)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Overlay Type Button Component
struct OverlayTypeButton: View {
    let type: OpenAIImageService.OverlayType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 14))
                Text(type.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .white : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.orange : Color(hex: "3d3d54"))
            .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(ExternalDisplayManager())
        .environmentObject(CameraManager())
        .environmentObject(OpenAIService())
        .environmentObject(OpenAIRealtimeService())
        .environmentObject(GeminiImageService())
        .environmentObject(OpenAIImageService())
}
