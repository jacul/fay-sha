import Foundation
import CryptoKit

public enum Algorithm: String, CaseIterable, Sendable {
    case sha256 = "SHA-256"
    case sha384 = "SHA-384"
    case sha512 = "SHA-512"
    case sha1 = "SHA-1"
    case md5 = "MD5"

    public var isLegacy: Bool { self == .sha1 || self == .md5 }
}

public enum Checksum {
    public static func hash(
        file: URL,
        algorithm: Algorithm,
        progress: @Sendable (Double) -> Void = { _ in }
    ) throws -> String {
        switch algorithm {
        case .sha256: return try stream(file, using: SHA256.self, progress: progress)
        case .sha384: return try stream(file, using: SHA384.self, progress: progress)
        case .sha512: return try stream(file, using: SHA512.self, progress: progress)
        case .sha1: return try stream(file, using: Insecure.SHA1.self, progress: progress)
        case .md5: return try stream(file, using: Insecure.MD5.self, progress: progress)
        }
    }

    private static func stream<H: HashFunction>(
        _ url: URL, using: H.Type, progress: @Sendable (Double) -> Void
    ) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw NSError(domain: "FaySHA", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Drop a regular file. Folders and special files cannot be hashed."
            ])
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = Double(values.fileSize ?? 0)
        var processed = 0.0
        var hasher = H()
        var lastUpdate = Date.distantPast
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            processed += Double(chunk.count)
            if Date().timeIntervalSince(lastUpdate) >= 0.1 {
                progress(size > 0 ? min(processed / size, 1) : 0)
                lastUpdate = Date()
            }
        }
        try Task.checkCancellation()
        progress(1)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
