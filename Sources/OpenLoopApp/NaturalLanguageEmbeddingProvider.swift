import ADHDCore
import Foundation
@preconcurrency import NaturalLanguage

enum NaturalLanguageEmbeddingError: Error, Equatable {
    case unavailable
    case missingVector
}

actor NaturalLanguageEmbeddingProvider: EmbeddingProvider {
    private let embedding: NLEmbedding?
    private let revision: Int

    init(language: NLLanguage = .english) {
        embedding = NLEmbedding.sentenceEmbedding(for: language)
        revision = embedding.map { Int($0.revision) } ?? 0
    }

    var identifier: String {
        get async { "apple-natural-language-sentence-en-r\(revision)" }
    }

    func vectors(for texts: [String]) async throws -> [[Double]] {
        guard let embedding else { throw NaturalLanguageEmbeddingError.unavailable }
        return try texts.map { text in
            guard let vector = embedding.vector(for: text) else {
                throw NaturalLanguageEmbeddingError.missingVector
            }
            return vector
        }
    }
}
