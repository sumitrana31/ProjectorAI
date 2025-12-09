//
//  Secrets.template.swift
//  ProjectorAI
//
//  TEMPLATE FILE - Copy this to Secrets.swift and add your API keys
//  Secrets.swift is gitignored and won't be committed
//
//  Steps:
//  1. Copy this file: cp Secrets.template.swift Secrets.swift
//  2. Add your actual API keys in Secrets.swift
//  3. Build and run
//

import Foundation

struct Secrets {
    // OpenAI API Key - used for GPT-4o analysis, Realtime voice, and image generation
    // Get your key at: https://platform.openai.com/api-keys
    static let openAIKey = "YOUR_OPENAI_API_KEY_HERE"

    // Gemini API Key - backup image generation provider
    // Get your key at: https://aistudio.google.com/apikey
    static let geminiKey = "YOUR_GEMINI_API_KEY_HERE"
}
