//
//  ExternalDisplayManager.swift
//  ProjectorAI
//
//  Handles external display (projector/HDMI) with animated content
//

import SwiftUI
import UIKit

// MARK: - Animation Types
enum ProjectorAnimation: String, CaseIterable, Identifiable {
    case none = "None"
    case typewriter = "Typewriter"
    case fadeIn = "Fade In"
    case slideUp = "Slide Up"
    case drawCircle = "Draw Circle"
    case drawArrow = "Draw Arrow"
    case pulsingDot = "Pulsing Dot"
    case mathSteps = "Math Steps"
    case spotlight = "Spotlight"
    case particles = "Particles"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none: return "xmark.circle"
        case .typewriter: return "keyboard"
        case .fadeIn: return "sun.max"
        case .slideUp: return "arrow.up.square"
        case .drawCircle: return "circle.dashed"
        case .drawArrow: return "arrow.right"
        case .pulsingDot: return "circle.circle"
        case .mathSteps: return "function"
        case .spotlight: return "flashlight.on.fill"
        case .particles: return "sparkles"
        }
    }
}

// MARK: - Projector Content Model
class ProjectorContent: ObservableObject {
    // Basic content
    @Published var text: String = "ProjectorAI"
    @Published var color: Color = .white
    @Published var fontSize: CGFloat = 48

    // AI Response
    @Published var aiResponse: String = ""
    @Published var showAIResponse: Bool = false
    @Published var isLiveMode: Bool = false

    // Animation system
    @Published var currentAnimation: ProjectorAnimation = .none
    @Published var isAnimating: Bool = false
    @Published var showDemo: Bool = false
    @Published var animationTrigger: UUID = UUID() // Triggers re-animation

    // Generated image display
    @Published var generatedImage: UIImage?
    @Published var showGeneratedImage: Bool = false
}

// MARK: - External Display Manager
class ExternalDisplayManager: ObservableObject {
    @Published var isExternalDisplayConnected = false
    @Published var externalScreenBounds: CGRect = .zero
    @Published var content = ProjectorContent()

    private var externalWindow: UIWindow?
    private var hostingController: UIHostingController<ProjectorView>?

    init() {
        setupNotifications()
        checkForExternalDisplay()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidConnect),
            name: UIScreen.didConnectNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidDisconnect),
            name: UIScreen.didDisconnectNotification,
            object: nil
        )
    }

    private func checkForExternalDisplay() {
        if UIScreen.screens.count > 1 {
            setupExternalDisplay(UIScreen.screens[1])
        }
    }

    @objc private func screenDidConnect(_ notification: Notification) {
        guard let screen = notification.object as? UIScreen else { return }
        setupExternalDisplay(screen)
    }

    @objc private func screenDidDisconnect(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.tearDownExternalDisplay()
        }
    }

    private func setupExternalDisplay(_ screen: UIScreen) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.externalScreenBounds = screen.bounds
            self.isExternalDisplayConnected = true

            let projectorView = ProjectorView(content: self.content)
            self.hostingController = UIHostingController(rootView: projectorView)

            let window = UIWindow(frame: screen.bounds)
            window.windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.screen == screen }

            window.rootViewController = self.hostingController
            window.isHidden = false
            self.externalWindow = window

            print("ExternalDisplayManager: External display connected - \(screen.bounds)")
        }
    }

    private func tearDownExternalDisplay() {
        externalWindow?.isHidden = true
        externalWindow = nil
        hostingController = nil
        isExternalDisplayConnected = false
        externalScreenBounds = .zero
        print("ExternalDisplayManager: External display disconnected")
    }

    // MARK: - Public Methods

    func updateAIResponse(_ response: String) {
        DispatchQueue.main.async { [weak self] in
            self?.content.aiResponse = response
            self?.content.showAIResponse = true
            self?.content.showDemo = false
        }
    }

    func clearAIResponse() {
        DispatchQueue.main.async { [weak self] in
            self?.content.aiResponse = ""
            self?.content.showAIResponse = false
        }
    }

    func setLiveMode(_ isLive: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.content.isLiveMode = isLive
        }
    }

    // MARK: - Animation Methods

    func playAnimation(_ animation: ProjectorAnimation) {
        DispatchQueue.main.async { [weak self] in
            self?.content.currentAnimation = animation
            self?.content.showAIResponse = false
            self?.content.showDemo = true
            self?.content.isAnimating = true
            self?.content.animationTrigger = UUID() // Trigger re-animation
        }
    }

    func stopAnimation() {
        DispatchQueue.main.async { [weak self] in
            self?.content.isAnimating = false
            self?.content.showDemo = false
            self?.content.currentAnimation = .none
        }
    }

    // MARK: - Generated Image Display

    func displayGeneratedImage(_ image: UIImage) {
        DispatchQueue.main.async { [weak self] in
            self?.content.generatedImage = image
            self?.content.showGeneratedImage = true
            self?.content.showAIResponse = false
            self?.content.showDemo = false
            self?.content.isAnimating = false
        }
    }

    func clearGeneratedImage() {
        DispatchQueue.main.async { [weak self] in
            self?.content.generatedImage = nil
            self?.content.showGeneratedImage = false
        }
    }
}

// MARK: - Projector View (Main External Display View)
struct ProjectorView: View {
    @ObservedObject var content: ProjectorContent

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black

                // Corner markers for calibration
                CornerMarkers()

                // Content based on mode
                if content.showGeneratedImage, let image = content.generatedImage {
                    // Generated annotated image from Gemini
                    GeneratedImageView(image: image, size: geometry.size)
                } else if content.showDemo && content.currentAnimation != .none {
                    AnimatedDemoView(content: content, size: geometry.size)
                        .id(content.animationTrigger) // Force re-render on trigger
                } else if content.showAIResponse {
                    AIResponseView(
                        response: content.aiResponse,
                        isLive: content.isLiveMode
                    )
                } else {
                    // Default: show app name
                    Text(content.text)
                        .font(.system(size: content.fontSize, weight: .bold))
                        .foregroundColor(content.color)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Generated Image View
struct GeneratedImageView: View {
    let image: UIImage
    let size: CGSize

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: size.width, maxHeight: size.height)
    }
}

// MARK: - Animated Demo View
struct AnimatedDemoView: View {
    @ObservedObject var content: ProjectorContent
    let size: CGSize

    var body: some View {
        ZStack {
            switch content.currentAnimation {
            case .none:
                EmptyView()

            case .typewriter:
                TypewriterDemo()

            case .fadeIn:
                FadeInDemo()

            case .slideUp:
                SlideUpDemo()

            case .drawCircle:
                DrawCircleDemo()

            case .drawArrow:
                DrawArrowDemo(size: size)

            case .pulsingDot:
                PulsingDotDemo()

            case .mathSteps:
                MathStepsDemo()

            case .spotlight:
                SpotlightDemo(size: size)

            case .particles:
                ParticlesDemo(size: size)
            }

            // Animation label
            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: content.currentAnimation.icon)
                        Text(content.currentAnimation.rawValue)
                    }
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .padding()
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

// MARK: - Typewriter Animation
struct TypewriterDemo: View {
    @State private var displayedText = ""
    let fullText = "Hello! I'm ProjectorAI.\n\nI can help you solve problems\non your whiteboard.\n\nJust point the camera and ask!"

    var body: some View {
        VStack {
            Text(displayedText)
                .font(.system(size: 52, weight: .medium, design: .monospaced))
                .foregroundColor(.green)
                .multilineTextAlignment(.center)
                .shadow(color: .green.opacity(0.5), radius: 10)
        }
        .padding(60)
        .onAppear {
            animateText()
        }
    }

    func animateText() {
        displayedText = ""
        for (index, char) in fullText.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.04) {
                displayedText += String(char)
            }
        }
    }
}

// MARK: - Fade In Animation
struct FadeInDemo: View {
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.5
    @State private var rotation: Double = -10

    var body: some View {
        VStack(spacing: 40) {
            Image(systemName: "lightbulb.max.fill")
                .font(.system(size: 150))
                .foregroundStyle(
                    LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .yellow.opacity(0.8), radius: 30)

            Text("Great idea!")
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(.white)

            Text("Let's work through this together")
                .font(.system(size: 36))
                .foregroundColor(.gray)
        }
        .opacity(opacity)
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                opacity = 1
                scale = 1
                rotation = 0
            }
        }
    }
}

// MARK: - Slide Up Animation
struct SlideUpDemo: View {
    @State private var items: [Bool] = [false, false, false, false]

    let content = [
        ("1", "Identify the problem", Color.blue, "magnifyingglass"),
        ("2", "Break it down", Color.green, "square.grid.2x2"),
        ("3", "Solve step by step", Color.orange, "list.number"),
        ("4", "Verify your answer", Color.purple, "checkmark.seal")
    ]

    var body: some View {
        VStack(spacing: 32) {
            Text("Problem Solving Steps")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 20)

            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(content[index].2)
                            .frame(width: 80, height: 80)

                        Text(content[index].0)
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: content[index].2.opacity(0.5), radius: 10)

                    Image(systemName: content[index].3)
                        .font(.system(size: 36))
                        .foregroundColor(content[index].2)

                    Text(content[index].1)
                        .font(.system(size: 42, weight: .medium))
                        .foregroundColor(.white)

                    Spacer()
                }
                .padding(.horizontal, 80)
                .offset(y: items[index] ? 0 : 150)
                .opacity(items[index] ? 1 : 0)
            }
        }
        .onAppear {
            for i in 0..<4 {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(i) * 0.25)) {
                    items[i] = true
                }
            }
        }
    }
}

// MARK: - Draw Circle Animation
struct DrawCircleDemo: View {
    @State private var progress: CGFloat = 0
    @State private var showCheckmark = false

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 12)
                .frame(width: 350, height: 350)

            // Animated circle
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [.cyan, .blue, .purple, .pink, .cyan], center: .center),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .frame(width: 350, height: 350)
                .rotationEffect(.degrees(-90))
                .shadow(color: .purple.opacity(0.5), radius: 15)

            // Center content
            VStack(spacing: 10) {
                if showCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Text(showCheckmark ? "Complete!" : "Progress")
                    .font(.system(size: 28))
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5)) {
                progress = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.spring()) {
                    showCheckmark = true
                }
            }
        }
    }
}

// MARK: - Draw Arrow Animation
struct DrawArrowDemo: View {
    let size: CGSize
    @State private var arrowProgress: CGFloat = 0
    @State private var showLabels: Bool = false
    @State private var bounceEnd: Bool = false

    var body: some View {
        ZStack {
            // Start point
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 60, height: 60)
                    Image(systemName: "flag.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                Text("Start")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.green)
            }
            .position(x: size.width * 0.15, y: size.height * 0.5)

            // Arrow path
            Path { path in
                path.move(to: CGPoint(x: size.width * 0.2, y: size.height * 0.5))
                path.addLine(to: CGPoint(x: size.width * 0.2 + (size.width * 0.6 * arrowProgress), y: size.height * 0.5))
            }
            .stroke(
                LinearGradient(colors: [.green, .yellow, .orange], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: [20, 10])
            )

            // Arrow head
            if arrowProgress > 0.9 {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                    .position(x: size.width * 0.8, y: size.height * 0.5)
                    .scaleEffect(bounceEnd ? 1.2 : 1)
            }

            // End point
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 60, height: 60)
                        .scaleEffect(bounceEnd ? 1.1 : 1)
                    Image(systemName: "star.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                Text("Goal!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.red)
            }
            .position(x: size.width * 0.85, y: size.height * 0.5)
            .opacity(showLabels ? 1 : 0.3)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2)) {
                arrowProgress = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    showLabels = true
                    bounceEnd = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring()) {
                        bounceEnd = false
                    }
                }
            }
        }
    }
}

// MARK: - Pulsing Dot Animation
struct PulsingDotDemo: View {
    @State private var pulse = false
    @State private var ringScale: [CGFloat] = [1, 1, 1]

    var body: some View {
        ZStack {
            // Outer rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.cyan.opacity(0.4 - Double(i) * 0.1), lineWidth: 3)
                    .frame(width: 150 + CGFloat(i) * 80, height: 150 + CGFloat(i) * 80)
                    .scaleEffect(ringScale[i])
            }

            // Glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.cyan.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .scaleEffect(pulse ? 1.2 : 0.8)

            // Center dot
            Circle()
                .fill(
                    RadialGradient(colors: [.white, .cyan], center: .center, startRadius: 0, endRadius: 50)
                )
                .frame(width: 100, height: 100)
                .shadow(color: .cyan, radius: 30)
                .scaleEffect(pulse ? 1.1 : 1)

            // Label
            VStack {
                Spacer()
                Text("Look Here!")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 100)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }

            for i in 0..<3 {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(Double(i) * 0.2)) {
                    ringScale[i] = 1.3
                }
            }
        }
    }
}

// MARK: - Math Steps Animation
struct MathStepsDemo: View {
    @State private var currentStep = -1

    let steps: [(String, String, Color)] = [
        ("Problem:", "2x + 5 = 15", .white),
        ("Subtract 5:", "2x + 5 - 5 = 15 - 5", .yellow),
        ("Simplify:", "2x = 10", .orange),
        ("Divide by 2:", "2x ÷ 2 = 10 ÷ 2", .cyan),
        ("Solution:", "x = 5 ✓", .green)
    ]

    var body: some View {
        VStack(spacing: 36) {
            Text("Solving Linear Equations")
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.purple)
                .padding(.bottom, 20)

            ForEach(0..<steps.count, id: \.self) { index in
                HStack(spacing: 20) {
                    Text(steps[index].0)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(width: 200, alignment: .trailing)

                    Text(steps[index].1)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(steps[index].2)
                        .shadow(color: steps[index].2.opacity(0.5), radius: index == currentStep ? 10 : 0)
                }
                .opacity(index <= currentStep ? 1 : 0.2)
                .scaleEffect(index == currentStep ? 1.05 : 1)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
            }
        }
        .padding(40)
        .onAppear {
            animateSteps()
        }
    }

    func animateSteps() {
        for i in 0..<steps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.5) {
                withAnimation {
                    currentStep = i
                }
            }
        }
    }
}

// MARK: - Spotlight Animation
struct SpotlightDemo: View {
    let size: CGSize
    @State private var spotlightX: CGFloat = 0.3
    @State private var spotlightY: CGFloat = 0.5

    var body: some View {
        ZStack {
            // Hidden content (revealed by spotlight)
            VStack(spacing: 30) {
                Text("🎯 Important!")
                    .font(.system(size: 64, weight: .bold))

                Text("Focus on what matters")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }

            // Spotlight mask
            Canvas { context, canvasSize in
                // Fill with dark overlay
                context.fill(
                    Path(CGRect(origin: .zero, size: canvasSize)),
                    with: .color(.black.opacity(0.85))
                )

                // Cut out spotlight circle
                let spotX = canvasSize.width * spotlightX
                let spotY = canvasSize.height * spotlightY
                let radius: CGFloat = 180

                context.blendMode = .destinationOut
                context.fill(
                    Path(ellipseIn: CGRect(x: spotX - radius, y: spotY - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.white)
                )
            }

            // Spotlight glow ring
            Circle()
                .stroke(
                    RadialGradient(colors: [.yellow.opacity(0.8), .clear], center: .center, startRadius: 150, endRadius: 200),
                    lineWidth: 4
                )
                .frame(width: 360, height: 360)
                .position(x: size.width * spotlightX, y: size.height * spotlightY)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                spotlightX = 0.7
            }
        }
    }
}

// MARK: - Particles Animation
struct ParticlesDemo: View {
    let size: CGSize
    @State private var particles: [ParticleData] = []

    struct ParticleData: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var scale: CGFloat
        var opacity: Double
        var color: Color
        var rotation: Double
    }

    let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]
    let emojis = ["✨", "⭐️", "💫", "🌟", "✦", "★"]

    var body: some View {
        ZStack {
            // Particles
            ForEach(particles) { particle in
                Text(emojis.randomElement()!)
                    .font(.system(size: 30 * particle.scale))
                    .opacity(particle.opacity)
                    .rotationEffect(.degrees(particle.rotation))
                    .position(x: particle.x, y: particle.y)
            }

            // Center text
            VStack(spacing: 20) {
                Text("✨ Magic! ✨")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .pink, .orange], startPoint: .leading, endPoint: .trailing)
                    )

                Text("Something amazing is happening")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .onAppear {
            startParticles()
        }
    }

    func startParticles() {
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            let newParticle = ParticleData(
                x: CGFloat.random(in: 50...(size.width - 50)),
                y: CGFloat.random(in: 50...(size.height - 50)),
                scale: CGFloat.random(in: 0.5...2),
                opacity: Double.random(in: 0.3...1),
                color: colors.randomElement()!,
                rotation: Double.random(in: 0...360)
            )

            withAnimation(.easeOut(duration: 0.3)) {
                particles.append(newParticle)
            }

            // Fade out and remove
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let index = particles.firstIndex(where: { $0.id == newParticle.id }) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        particles.remove(at: index)
                    }
                }
            }

            // Limit particles
            if particles.count > 40 {
                particles.removeFirst()
            }
        }
    }
}

// MARK: - AI Response View
struct AIResponseView: View {
    let response: String
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 36))
                    .foregroundColor(.purple)

                Text("ProjectorAI")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                if isLive {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text("LIVE")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)

            Rectangle()
                .fill(LinearGradient(
                    colors: [.purple, .blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(height: 4)
                .padding(.horizontal, 40)

            ScrollView {
                Text(response)
                    .font(.system(size: 32))
                    .foregroundColor(.white)
                    .lineSpacing(12)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
            }

            Spacer()
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Corner Markers
struct CornerMarkers: View {
    let markerSize: CGFloat = 40

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.red)
                .frame(width: markerSize, height: markerSize)
                .position(x: markerSize / 2, y: markerSize / 2)

            Rectangle()
                .fill(Color.green)
                .frame(width: markerSize, height: markerSize)
                .position(x: geometry.size.width - markerSize / 2, y: markerSize / 2)

            Rectangle()
                .fill(Color.blue)
                .frame(width: markerSize, height: markerSize)
                .position(x: markerSize / 2, y: geometry.size.height - markerSize / 2)

            Rectangle()
                .fill(Color.yellow)
                .frame(width: markerSize, height: markerSize)
                .position(x: geometry.size.width - markerSize / 2, y: geometry.size.height - markerSize / 2)
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
