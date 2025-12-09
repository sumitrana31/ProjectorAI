//
//  OpenAIService.swift
//  ProjectorAI
//
//  REST API client for OpenAI GPT-4o image analysis
//

import Foundation
import UIKit

class OpenAIService: ObservableObject {
    @Published var isAnalyzing = false
    @Published var lastResponse: String = ""
    @Published var lastError: String?

    private let apiKey = Secrets.openAIKey
    private let model = "gpt-4o"
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    private let systemPrompt = """
    You are ProjectorAI, an intelligent AI tutor that helps students learn by analyzing their whiteboard work.

    Your role:
    - Analyze what's written on the whiteboard (math problems, diagrams, text, code, etc.)
    - Identify the problem or topic being worked on
    - Provide helpful hints, explanations, and guidance
    - If there are errors, point them out gently and explain the correct approach
    - Offer step-by-step solutions when appropriate
    - Use clear, educational language suitable for students
    - Be encouraging and supportive

    Format your responses clearly with:
    - Brief problem identification
    - Key observations
    - Helpful hints or explanations
    - Step-by-step guidance if needed

    Keep responses concise but thorough - they will be projected on a whiteboard for easy reading.
    """

    func analyzeImage(_ image: UIImage, prompt: String = "What do you see on this whiteboard? Analyze and help.") async throws -> String {
        await MainActor.run {
            isAnalyzing = true
            lastError = nil
        }

        defer {
            Task { @MainActor in
                isAnalyzing = false
            }
        }

        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw OpenAIError.imageConversionFailed
        }
        let base64Image = imageData.base64EncodedString()

        // Build request
        guard let url = URL(string: baseURL) else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Build request body
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)",
                                "detail": "high"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 2048,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw OpenAIError.apiError(message)
            }
            throw OpenAIError.httpError(httpResponse.statusCode)
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.parseError
        }

        await MainActor.run {
            lastResponse = content
        }

        return content
    }

    func analyzeWithCustomPrompt(_ image: UIImage, customPrompt: String) async throws -> String {
        return try await analyzeImage(image, prompt: customPrompt)
    }
}

// MARK: - OpenAI Errors
enum OpenAIError: LocalizedError {
    case imageConversionFailed
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to JPEG"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .parseError:
            return "Failed to parse response"
        }
    }
}
