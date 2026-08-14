import Darwin
import Foundation

public final class DevelopmentStoreLock: @unchecked Sendable {
    private let descriptor: Int32

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("thought-loop.json.lock")
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    deinit { Darwin.close(descriptor) }

    public func lockExclusive() throws {
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    public func unlock() { flock(descriptor, LOCK_UN) }
}
