import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum HighWaterError: Error, Equatable, CustomStringConvertible {
    case corrupt(String)
    case io(String)

    public var description: String {
        switch self {
        case .corrupt(let path):
            return "state file is corrupt at \(path); refusing to reset it. Restore last_rowid from the log, or remove the file only if skipping every message already in chat.db is acceptable."
        case .io(let message):
            return message
        }
    }
}

public protocol HighWaterStoring: AnyObject {
    func load() throws -> Int64?
    func save(_ rowID: Int64) throws
}

public final class FileHighWaterStore: HighWaterStoring {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> Int64? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(HighWaterFile.self, from: data).last_rowid
        } catch {
            throw HighWaterError.corrupt(url.path)
        }
    }

    public func save(_ rowID: Int64) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(HighWaterFile(last_rowid: rowID))
        do {
            try atomicWrite(data, to: url)
        } catch let error as HighWaterError {
            throw error
        } catch {
            throw HighWaterError.io("could not save state")
        }
    }
}

private struct HighWaterFile: Codable {
    var last_rowid: Int64
}

func atomicWrite(_ data: Data, to url: URL) throws {
    let fileManager = FileManager.default
    let directory = url.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    try data.write(to: temporary)
    try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: temporary.path)
    let renamed = temporary.path.withCString { source in
        url.path.withCString { destination in
            rename(source, destination)
        }
    }
    if renamed != 0 {
        try? fileManager.removeItem(at: temporary)
        throw HighWaterError.io("could not replace state file")
    }
}
