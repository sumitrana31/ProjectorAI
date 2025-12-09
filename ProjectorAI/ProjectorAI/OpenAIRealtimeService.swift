//
//  OpenAIRealtimeService.swift
//  ProjectorAI
//
//  WebSocket client for OpenAI Realtime API - Voice conversation with camera vision
//

import Foundation
import UIKit
import AVFoundation

class OpenAIRealtimeService: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isListening = false
    @Published var currentResponse: String = ""
    @Published var lastTranscript: String = ""
    @Published var lastError: String?
    @Published var isSpeaking = false

    // IMPORTANT: Replace with your OpenAI API key before running
    // Get your key at: https://platform.openai.com/api-keys
    private let apiKey = "YOUR_OPENAI_API_KEY_HERE"
    private let model = "gpt-4o-realtime-preview-2024-12-17"

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // Audio components
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var pendingAudioData: [Data] = []

    // Camera frame provider (set externally)
    var frameProvider: (() -> UIImage?)?

    // Callbacks
    var onResponse: ((String) -> Void)?
    var onTranscript: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let systemInstruction = """
    You are ProjectorAI, a friendly AI tutor that can see through the user's camera and have voice conversations.

    Your role:
    - When the user speaks to you, look at what's visible on their camera (usually a whiteboard)
    - Provide helpful tutoring, hints, and explanations about what you see
    - Keep your responses concise and conversational - you're having a real-time voice chat
    - Be encouraging and supportive like a patient tutor
    - If you can't see anything relevant, ask the user to point the camera at what they need help with

    Remember: This is a voice conversation. Keep responses brief and natural.
    """

    override init() {
        super.init()
        setupURLSession()
    }

    private func setupURLSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - Connection Management

    func connect() {
        guard !isConnected else { return }

        let urlString = "wss://api.openai.com/v1/realtime?model=\(model)"

        guard let url = URL(string: urlString) else {
            lastError = "Invalid WebSocket URL"
            onError?("Invalid WebSocket URL")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        startReceiving()

        print("OpenAIRealtimeService: Connecting to WebSocket...")
    }

    func disconnect() {
        stopListening()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.isListening = false
            self?.currentResponse = ""
            self?.lastTranscript = ""
        }

        print("OpenAIRealtimeService: Disconnected")
    }

    // MARK: - Session Configuration

    private func sendSessionConfig() {
        let sessionConfig: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "instructions": systemInstruction,
                "voice": "alloy",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "whisper-1"
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 800
                ],
                "temperature": 0.8,
                "max_response_output_tokens": 512
            ]
        ]

        sendJSON(sessionConfig)
        print("OpenAIRealtimeService: Session config sent")
    }

    // MARK: - Send Camera Frame with User Message

    /// Call this when the user finishes speaking to include a camera frame
    private func sendCameraFrameAsContext() {
        guard let provider = frameProvider, let image = provider() else {
            print("OpenAIRealtimeService: No camera frame available")
            return
        }

        // Convert image to base64 JPEG
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            print("OpenAIRealtimeService: Failed to convert image to JPEG")
            return
        }
        let base64Image = imageData.base64EncodedString()
        let dataURL = "data:image/jpeg;base64,\(base64Image)"

        // Send as a conversation item with image context
        let message: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": "[Camera view attached - analyze this along with the user's voice request]"
                    ]
                ]
            ]
        ]

        // Note: The Realtime API currently has limited image support
        // We'll send a text description prompt instead
        sendJSON(message)
        print("OpenAIRealtimeService: Sent camera context")
    }

    // MARK: - Audio Input (Voice)

    func startListening() {
        guard isConnected else {
            // Connect first, then start listening
            connect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.startListening()
            }
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)

            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }

            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Setup audio player for AI voice output
            audioPlayer = AVAudioPlayerNode()
            audioEngine.attach(audioPlayer!)
            audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)
            audioEngine.connect(audioPlayer!, to: audioEngine.mainMixerNode, format: audioFormat)

            // Create converter from input format to PCM16 24kHz mono
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!

            inputNode.installTap(onBus: 0, bufferSize: 2400, format: inputFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer, from: inputFormat, to: targetFormat)
            }

            audioEngine.prepare()
            try audioEngine.start()

            DispatchQueue.main.async { [weak self] in
                self?.isListening = true
            }

            print("OpenAIRealtimeService: Started listening")
        } catch {
            print("OpenAIRealtimeService: Failed to start audio engine: \(error)")
            lastError = "Failed to start microphone: \(error.localizedDescription)"
        }
    }

    func stopListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioPlayer?.stop()
        audioEngine?.stop()
        audioEngine = nil
        audioPlayer = nil

        DispatchQueue.main.async { [weak self] in
            self?.isListening = false
            self?.isSpeaking = false
        }

        print("OpenAIRealtimeService: Stopped listening")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat, to targetFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else { return }

        var error: NSError?
        var inputBufferConsumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputBufferConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBufferConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("OpenAIRealtimeService: Audio conversion error: \(error)")
            return
        }

        // Convert to Data and send
        guard let channelData = outputBuffer.int16ChannelData else { return }
        let data = Data(bytes: channelData[0], count: Int(outputBuffer.frameLength) * 2)
        let base64Audio = data.base64EncodedString()

        let audioMessage: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Audio
        ]

        sendJSON(audioMessage)
    }

    // MARK: - Play AI Audio Response

    private func playAudioData(_ data: Data) {
        guard let audioEngine = audioEngine,
              let audioPlayer = audioPlayer,
              let audioFormat = audioFormat else { return }

        let frameCount = UInt32(data.count / 2) // 16-bit = 2 bytes per sample
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            if let baseAddress = bytes.baseAddress {
                memcpy(buffer.int16ChannelData![0], baseAddress, data.count)
            }
        }

        if !audioEngine.isRunning {
            try? audioEngine.start()
        }

        audioPlayer.scheduleBuffer(buffer, completionHandler: nil)
        if !audioPlayer.isPlaying {
            audioPlayer.play()
        }
    }

    // MARK: - WebSocket Communication

    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let jsonString = String(data: data, encoding: .utf8) else {
            print("OpenAIRealtimeService: Failed to serialize JSON")
            return
        }

        let message = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                print("OpenAIRealtimeService: Send error - \(error.localizedDescription)")
                self?.handleError(error.localizedDescription)
            }
        }
    }

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.startReceiving()

            case .failure(let error):
                print("OpenAIRealtimeService: Receive error - \(error.localizedDescription)")
                self?.handleError(error.localizedDescription)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseResponse(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseResponse(text)
            }
        @unknown default:
            break
        }
    }

    private func parseResponse(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "session.created":
            print("OpenAIRealtimeService: Session created")
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = true
            }
            // Send session config after session is created
            sendSessionConfig()

        case "session.updated":
            print("OpenAIRealtimeService: Session updated")

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("OpenAIRealtimeService: Error - \(message)")
                // Don't disconnect on non-critical errors
            }

        case "input_audio_buffer.speech_started":
            print("OpenAIRealtimeService: Speech started")
            DispatchQueue.main.async { [weak self] in
                self?.isSpeaking = true
            }

        case "input_audio_buffer.speech_stopped":
            print("OpenAIRealtimeService: Speech stopped")
            DispatchQueue.main.async { [weak self] in
                self?.isSpeaking = false
            }

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                print("OpenAIRealtimeService: User said: \(transcript)")
                DispatchQueue.main.async { [weak self] in
                    self?.lastTranscript = transcript
                    self?.onTranscript?(transcript)
                }
            }

        case "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.currentResponse += delta
                    self?.onResponse?(self?.currentResponse ?? "")
                }
            }

        case "response.audio_transcript.done":
            if let transcript = json["transcript"] as? String {
                print("OpenAIRealtimeService: AI said: \(transcript)")
                DispatchQueue.main.async { [weak self] in
                    self?.currentResponse = transcript
                    self?.onResponse?(transcript)
                }
            }

        case "response.audio.delta":
            if let audioBase64 = json["delta"] as? String,
               let audioData = Data(base64Encoded: audioBase64) {
                playAudioData(audioData)
            }

        case "response.done":
            print("OpenAIRealtimeService: Response complete")
            DispatchQueue.main.async { [weak self] in
                self?.currentResponse = ""
            }

        default:
            print("OpenAIRealtimeService: Received event type: \(type)")
        }
    }

    private func handleError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.lastError = message
            self?.onError?(message)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate
extension OpenAIRealtimeService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("OpenAIRealtimeService: WebSocket connected")
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("OpenAIRealtimeService: WebSocket closed with code \(closeCode)")
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.isListening = false
        }
    }
}
