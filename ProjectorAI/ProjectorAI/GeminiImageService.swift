//
//  GeminiImageService.swift
//  ProjectorAI
//
//  Gemini 3 Pro Image API client for generating annotated whiteboard images
//

import Foundation
import UIKit

class GeminiImageService: ObservableObject {
    @Published var isGenerating = false
    @Published var lastError: String?
    @Published var generatedImage: UIImage?

    private let apiKey = Secrets.geminiKey
    // Using gemini-2.5-flash-image for free tier access (Nano Banana)
    // Change to "gemini-3-pro-image-preview" if you have billing enabled (Nano Banana Pro)
    private let model = "gemini-2.5-flash-image"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    // MARK: - Overlay Types

    enum OverlayType: String, CaseIterable, Identifiable {
        case hint = "Hint"
        case solve = "Solve Step"
        case label = "Label"
        case correct = "Correct Errors"
        case explain = "Explain"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .hint: return "lightbulb"
            case .solve: return "function"
            case .label: return "tag"
            case .correct: return "checkmark.circle"
            case .explain: return "text.bubble"
            }
        }

        var prompt: String {
            switch self {
            case .hint:
                return """
                Look at this whiteboard image. Create an annotated version that:
                1. Keeps ALL original content exactly as shown
                2. Adds a small hint arrow or indicator pointing to where to start
                3. Adds a brief hint text in blue color near the relevant area
                4. Uses clean, legible typography for any added text
                Do NOT solve the problem - only give a subtle hint about the approach.
                """

            case .solve:
                return """
                Look at this whiteboard image with a problem. Create an annotated version that:
                1. Keeps ALL original content exactly as shown
                2. Shows the NEXT step only (not the full solution)
                3. Adds the next step in a different color (blue or green)
                4. Adds a small explanation of what this step does
                5. Uses clean, legible handwriting or typography
                Only show ONE next step, not the complete solution.
                """

            case .label:
                return """
                Look at this whiteboard image. Create an annotated version that:
                1. Keeps ALL original content exactly as shown
                2. Identifies and labels key components, parts, or elements
                3. Uses arrows connecting labels to the items they describe
                4. Uses professional, clean typography for labels
                5. Places labels in empty spaces to avoid covering original content
                """

            case .correct:
                return """
                Review this whiteboard work carefully. Create an annotated version that:
                1. Keeps ALL original content exactly as shown
                2. Circles or highlights any errors in RED
                3. Shows the correct approach in GREEN nearby
                4. Adds a brief explanation of what went wrong
                5. Be encouraging - focus on the fix, not the mistake
                If there are no errors, add a green checkmark and "Looks good!"
                """

            case .explain:
                return """
                Look at this whiteboard content. Create an annotated version that:
                1. Keeps ALL original content exactly as shown
                2. Adds explanatory notes around the content
                3. Uses callout boxes or speech bubbles for explanations
                4. Explains what each part means or does
                5. Uses clean, readable typography
                Make it educational - like a tutor explaining the concept.
                """
            }
        }
    }

    // MARK: - Generate Annotated Image

    func generateAnnotatedImage(
        from image: UIImage,
        overlayType: OverlayType,
        additionalContext: String? = nil
    ) async throws -> UIImage {
        await MainActor.run {
            isGenerating = true
            lastError = nil
        }

        defer {
            Task { @MainActor in
                isGenerating = false
            }
        }

        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw GeminiError.imageConversionFailed
        }
        let base64Image = imageData.base64EncodedString()

        // Build prompt
        var fullPrompt = overlayType.prompt
        if let context = additionalContext, !context.isEmpty {
            fullPrompt += "\n\nAdditional context: \(context)"
        }

        // Build request body
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": fullPrompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "responseModalities": ["TEXT", "IMAGE"],
                "imageConfig": [
                    "aspectRatio": "16:9",
                    "imageSize": "2K"
                ]
            ]
        ]

        // Create request
        let urlString = "\(baseURL)/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // 2 minutes for image generation

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData

        print("GeminiImageService: Sending request to \(model)...")

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        print("GeminiImageService: Response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("GeminiImageService: Error response: \(errorText)")
            }
            throw GeminiError.apiError(statusCode: httpResponse.statusCode)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.parseError
        }

        // Extract image from response
        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GeminiError.noImageInResponse
        }

        // Find the image part
        for part in parts {
            if let inlineData = part["inlineData"] as? [String: Any],
               let imageBase64 = inlineData["data"] as? String,
               let imageData = Data(base64Encoded: imageBase64),
               let generatedImage = UIImage(data: imageData) {

                await MainActor.run {
                    self.generatedImage = generatedImage
                }

                print("GeminiImageService: Successfully generated annotated image")
                return generatedImage
            }
        }

        // Check if there's text response (for debugging)
        for part in parts {
            if let text = part["text"] as? String {
                print("GeminiImageService: Text response: \(text)")
            }
        }

        throw GeminiError.noImageInResponse
    }

    // MARK: - Custom Prompt Generation

    func generateWithCustomPrompt(
        from image: UIImage,
        prompt: String
    ) async throws -> UIImage {
        await MainActor.run {
            isGenerating = true
            lastError = nil
        }

        defer {
            Task { @MainActor in
                isGenerating = false
            }
        }

        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw GeminiError.imageConversionFailed
        }
        let base64Image = imageData.base64EncodedString()

        // Build request body
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "responseModalities": ["TEXT", "IMAGE"],
                "imageConfig": [
                    "aspectRatio": "16:9",
                    "imageSize": "2K"
                ]
            ]
        ]

        // Create request
        let urlString = "\(baseURL)/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GeminiError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GeminiError.parseError
        }

        // Find the image part
        for part in parts {
            if let inlineData = part["inlineData"] as? [String: Any],
               let imageBase64 = inlineData["data"] as? String,
               let imageData = Data(base64Encoded: imageBase64),
               let generatedImage = UIImage(data: imageData) {

                await MainActor.run {
                    self.generatedImage = generatedImage
                }

                return generatedImage
            }
        }

        throw GeminiError.noImageInResponse
    }
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case invalidURL
    case imageConversionFailed
    case invalidResponse
    case apiError(statusCode: Int)
    case parseError
    case noImageInResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .imageConversionFailed:
            return "Failed to convert image"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let statusCode):
            return "API error (status: \(statusCode))"
        case .parseError:
            return "Failed to parse response"
        case .noImageInResponse:
            return "No image in response"
        }
    }
}
