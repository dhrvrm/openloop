import ADHDCore
import Foundation

protocol MeetingTitleProviding: Sendable {
    func title(for transcript: MeetingTranscript) async -> String
}

struct DeterministicMeetingTitleProvider: MeetingTitleProviding {
    func title(for transcript: MeetingTranscript) async -> String {
        MeetingTitleNaming.fallbackTitle(for: transcript)
    }
}

enum MeetingTitleNaming {
    static func provisionalTitle(
        createdAt: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM, h:mm a")
        return "Voice note · \(formatter.string(from: createdAt))"
    }

    static func displayTitle(_ value: String) -> String {
        var title = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if title.lowercased().hasPrefix("title:") {
            title = String(title.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*_# "))
        title = title.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?—–- "))
        if title.count > 72 {
            let boundary = title.index(title.startIndex, offsetBy: 72)
            title = String(title[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title.isEmpty ? "Voice note" : title
    }

    static func fallbackTitle(for transcript: MeetingTranscript) -> String {
        let firstThought = transcript.text
            .split(whereSeparator: { ".!?।\n".contains($0) })
            .first
            .map(String.init) ?? transcript.text
        let words = firstThought.split(whereSeparator: \.isWhitespace)
        let concise = words.prefix(8).joined(separator: " ")
        return displayTitle(concise)
    }

    static func fileName(
        title: String,
        createdAt: Date,
        fileExtension: String,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let timestamp = formatter.string(from: createdAt)
        let normalizedExtension = fileExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let suffix = normalizedExtension.isEmpty ? "m4a" : normalizedExtension
        return "\(timestamp)-\(slug(title)).\(suffix)"
    }

    static func needsHumanTitle(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let base = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
        if UUID(uuidString: base) != nil { return true }
        let audioExtensions = Set(["wav", "mp3", "m4a", "mp4", "flac", "aiff", "aif", "caf"])
        return audioExtensions.contains(URL(fileURLWithPath: trimmed).pathExtension.lowercased())
    }

    private static func slug(_ title: String) -> String {
        let latin = title.applyingTransform(.toLatin, reverse: false) ?? title
        let folded = latin.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let parts = folded.split { !$0.isLetter && !$0.isNumber }
        let value = parts.joined(separator: "-").lowercased()
        return String((value.isEmpty ? "voice-note" : value).prefix(64))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
