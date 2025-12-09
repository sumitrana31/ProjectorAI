//
//  ProjectorAIApp.swift
//  ProjectorAI
//
//  AI-powered whiteboard collaboration system
//

import SwiftUI

@main
struct ProjectorAIApp: App {
    @StateObject private var externalDisplayManager = ExternalDisplayManager()
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var openAIService = OpenAIService()
    @StateObject private var openAIRealtimeService = OpenAIRealtimeService()
    @StateObject private var geminiImageService = GeminiImageService()
    @StateObject private var openAIImageService = OpenAIImageService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(externalDisplayManager)
                .environmentObject(cameraManager)
                .environmentObject(openAIService)
                .environmentObject(openAIRealtimeService)
                .environmentObject(geminiImageService)
                .environmentObject(openAIImageService)
        }
    }
}
