//
//  OpenAIImageService.swift
//  ProjectorAI
//
//  OpenAI GPT Image API client for generating annotated whiteboard images
//  Alternative to GeminiImageService - can swap between them
//

import Foundation
import UIKit

class OpenAIImageService: ObservableObject {
    @Published var isGenerating = false
    @Published var lastError: String?
    @Published var generatedImage: UIImage?

    private let apiKey = Secrets.openAIKey
    private let model = "gpt-image-1"
    private let baseURL = "https://api.openai.com/v1/images"

    // MARK: - Overlay Types (same as Gemini for easy swapping)

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

        // Build prompt
        var fullPrompt = overlayType.prompt
        if let context = additionalContext, !context.isEmpty {
            fullPrompt += "\n\nAdditional context: \(context)"
        }

        // Convert image to PNG data for multipart form
        guard let imageData = image.pngData() else {
            throw OpenAIImageError.imageConversionFailed
        }

        // Create multipart form request
        let boundary = UUID().uuidString
        let urlString = "\(baseURL)/edits"
        guard let url = URL(string: urlString) else {
            throw OpenAIImageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180 // 3 minutes for image generation

        // Build multipart form body
        var body = Data()

        // Add model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Add prompt
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(fullPrompt)\r\n".data(using: .utf8)!)

        // Add image
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"whiteboard.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Add size (landscape for whiteboard)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"size\"\r\n\r\n".data(using: .utf8)!)
        body.append("1536x1024\r\n".data(using: .utf8)!)

        // Add quality
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"quality\"\r\n\r\n".data(using: .utf8)!)
        body.append("high\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        print("OpenAIImageService: Sending request to \(model)...")

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIImageError.invalidResponse
        }

        print("OpenAIImageService: Response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("OpenAIImageService: Error response: \(errorText)")
            }
            throw OpenAIImageError.apiError(statusCode: httpResponse.statusCode)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIImageError.parseError
        }

        // Extract image from response
        guard let dataArray = json["data"] as? [[String: Any]],
              let firstResult = dataArray.first,
              let base64Image = firstResult["b64_json"] as? String,
              let imageData = Data(base64Encoded: base64Image),
              let generatedImage = UIImage(data: imageData) else {
            throw OpenAIImageError.noImageInResponse
        }

        await MainActor.run {
            self.generatedImage = generatedImage
        }

        print("OpenAIImageService: Successfully generated annotated image")
        return generatedImage
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

        // Convert image to PNG data
        guard let imageData = image.pngData() else {
            throw OpenAIImageError.imageConversionFailed
        }

        // Create multipart form request
        let boundary = UUID().uuidString
        let urlString = "\(baseURL)/edits"
        guard let url = URL(string: urlString) else {
            throw OpenAIImageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        // Build multipart form body
        var body = Data()

        // Add model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Add prompt
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(prompt)\r\n".data(using: .utf8)!)

        // Add image
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"whiteboard.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Add size
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"size\"\r\n\r\n".data(using: .utf8)!)
        body.append("1536x1024\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenAIImageError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let firstResult = dataArray.first,
              let base64Image = firstResult["b64_json"] as? String,
              let imageData = Data(base64Encoded: base64Image),
              let generatedImage = UIImage(data: imageData) else {
            throw OpenAIImageError.parseError
        }

        await MainActor.run {
            self.generatedImage = generatedImage
        }

        return generatedImage
    }
}

// MARK: - Errors

enum OpenAIImageError: LocalizedError {
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
