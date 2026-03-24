import Foundation

enum PredefinedModels {
    static func getLanguageDictionary(isMultilingual: Bool, provider: ModelProvider = .local) -> [String: String] {
        if !isMultilingual {
            return ["en": "English"]
        }
        return allLanguages
    }

    static var models: [any TranscriptionModel] {
        return predefinedModels
    }

    private static let predefinedModels: [any TranscriptionModel] = [
        // Parakeet Model (on-device ML)
        ParakeetModel(
            name: "parakeet-tdt-0.6b",
            displayName: "Parakeet V3",
            description: "NVIDIA's ASR model V3 for lightning-fast transcription with multi-lingual support.",
            size: "500 MB",
            speed: 0.99,
            accuracy: 0.94,
            ramUsage: 0.8,
            supportedLanguages: getLanguageDictionary(isMultilingual: true, provider: .parakeet)
        ),

        // Local Whisper Models
        LocalModel(
            name: "ggml-tiny",
            displayName: "Tiny",
            size: "75 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true),
            description: "Tiny model, fastest, least accurate",
            speed: 0.95,
            accuracy: 0.6,
            ramUsage: 0.3
        ),
        LocalModel(
            name: "ggml-tiny.en",
            displayName: "Tiny (English)",
            size: "75 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: false),
            description: "Tiny model optimized for English",
            speed: 0.95,
            accuracy: 0.65,
            ramUsage: 0.3
        ),
        LocalModel(
            name: "ggml-base",
            displayName: "Base",
            size: "142 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true),
            description: "Base model, good balance between speed and accuracy",
            speed: 0.85,
            accuracy: 0.72,
            ramUsage: 0.5
        ),
        LocalModel(
            name: "ggml-base.en",
            displayName: "Base (English)",
            size: "142 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: false),
            description: "Base model optimized for English",
            speed: 0.85,
            accuracy: 0.75,
            ramUsage: 0.5
        ),
        LocalModel(
            name: "ggml-large-v2",
            displayName: "Large v2",
            size: "2.9 GB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true),
            description: "Large model v2, slower but very accurate",
            speed: 0.3,
            accuracy: 0.96,
            ramUsage: 3.8
        ),
        LocalModel(
            name: "ggml-large-v3",
            displayName: "Large v3",
            size: "2.9 GB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true),
            description: "Large model v3, most accurate",
            speed: 0.3,
            accuracy: 0.98,
            ramUsage: 3.9
        ),
        LocalModel(
            name: "ggml-large-v3-turbo",
            displayName: "Large v3 Turbo",
            size: "1.5 GB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true),
            description: "Large model v3 Turbo, fast with high accuracy",
            speed: 0.75,
            accuracy: 0.97,
            ramUsage: 1.8
        ),
        LocalModel(
            name: "ggml-large-v3-turbo-q5_0",
            displayName: "Large v3 Turbo (Quantized)",
            size: "547 MB",
            supportedLanguages: getLanguageDictionary(isMultilingual: true),
            description: "Quantized version of Large v3 Turbo, faster with slightly lower accuracy",
            speed: 0.75,
            accuracy: 0.95,
            ramUsage: 1.0
        ),
    ]

    static let allLanguages = [
        "auto": "Auto-detect",
        "af": "Afrikaans",
        "ar": "Arabic",
        "bg": "Bulgarian",
        "bn": "Bengali",
        "ca": "Catalan",
        "cs": "Czech",
        "da": "Danish",
        "de": "German",
        "el": "Greek",
        "en": "English",
        "es": "Spanish",
        "et": "Estonian",
        "fi": "Finnish",
        "fr": "French",
        "hi": "Hindi",
        "hr": "Croatian",
        "hu": "Hungarian",
        "id": "Indonesian",
        "it": "Italian",
        "ja": "Japanese",
        "ko": "Korean",
        "nl": "Dutch",
        "no": "Norwegian",
        "pl": "Polish",
        "pt": "Portuguese",
        "ro": "Romanian",
        "ru": "Russian",
        "sk": "Slovak",
        "sv": "Swedish",
        "th": "Thai",
        "tr": "Turkish",
        "uk": "Ukrainian",
        "vi": "Vietnamese",
        "zh": "Chinese",
    ]
}
