import ADHDCore
import Darwin
import Foundation
import LocalStore
import RuleClarifier

private enum CommandError: Error, LocalizedError {
    case invalidID(String)
    case missingArguments(String)
    case unknownCommand(String)

    var errorDescription: String? {
        switch self {
        case let .invalidID(value):
            "Invalid intention ID: \(value)"
        case let .missingArguments(usage):
            "Missing arguments. Usage: \(usage)"
        case let .unknownCommand(command):
            "Unknown command: \(command)"
        }
    }
}

@main
struct ThoughtLoopCommand {
    private static let usage = """
        Usage:
          thought-loop capture <text>
          thought-loop list
          thought-loop start <id>
          thought-loop interrupt <id> <next action>
          thought-loop resume <id>
          thought-loop close <id>
        """

    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            let message = "Error: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            print(usage)
            return
        }

        let repository = try JSONFileThoughtRepository(directory: dataDirectory())
        let loop = ThoughtLoop(
            repository: repository,
            clarifier: RuleClarificationProvider()
        )

        switch command {
        case "capture":
            let text = arguments.dropFirst().joined(separator: " ")
            guard text.isEmpty == false else {
                throw CommandError.missingArguments("thought-loop capture <text>")
            }
            let result = try await loop.capture(text: text, at: .now)
            print("Saved: \(result.capture.text)")
            print("Disposition: \(result.proposal.disposition.rawValue)")
            if let intention = result.intention {
                print("ID: \(intention.id.uuidString)")
                print("Next: \(intention.nextAction)")
            }

        case "list":
            let intentions = try await repository.openIntentions()
            if intentions.isEmpty {
                print("No open intentions.")
            } else {
                for intention in intentions {
                    print("\(intention.id.uuidString)\t\(intention.state.rawValue)\t\(intention.nextAction)")
                }
            }

        case "start":
            let id = try intentionID(from: arguments, usage: "thought-loop start <id>")
            let intention = try await loop.start(id)
            printState(intention)

        case "interrupt":
            let id = try intentionID(from: arguments, usage: "thought-loop interrupt <id> <next action>")
            let nextAction = arguments.dropFirst(2).joined(separator: " ")
            guard nextAction.isEmpty == false else {
                throw CommandError.missingArguments("thought-loop interrupt <id> <next action>")
            }
            let packet = try ReturnPacket(
                capturedAt: .now,
                justCompleted: nil,
                nextAction: nextAction,
                blocker: nil,
                references: []
            )
            let intention = try await loop.interrupt(id, with: packet)
            printState(intention)

        case "resume":
            let id = try intentionID(from: arguments, usage: "thought-loop resume <id>")
            let intention = try await loop.resume(id)
            printState(intention)

        case "close":
            let id = try intentionID(from: arguments, usage: "thought-loop close <id>")
            let intention = try await loop.close(id)
            printState(intention)

        default:
            throw CommandError.unknownCommand(command)
        }
    }

    private static func dataDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["OPENLOOP_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenLoopADHD", isDirectory: true)
    }

    private static func intentionID(from arguments: [String], usage: String) throws -> UUID {
        guard arguments.count >= 2 else { throw CommandError.missingArguments(usage) }
        guard let id = UUID(uuidString: arguments[1]) else {
            throw CommandError.invalidID(arguments[1])
        }
        return id
    }

    private static func printState(_ intention: Intention) {
        print("ID: \(intention.id.uuidString)")
        print("State: \(intention.state.rawValue)")
        print("Next: \(intention.returnPacket?.nextAction ?? intention.nextAction)")
    }
}
