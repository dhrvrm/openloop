import Foundation

enum TranscriptionContext {
    static func make(localUserName: String) -> String {
        let normalizedName = localUserName
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        let limitedName = String(normalizedName.prefix(80))
        let participantContext = limitedName.isEmpty
            ? ""
            : "Participants: \(limitedName). "

        return participantContext
            + "Multilingual conversation in English and Hindi (हिन्दी), including Hinglish code-switching. "
            + "Preserve names. Write Hindi speech in Devanagari and English speech in Latin; do not translate."
    }
}
