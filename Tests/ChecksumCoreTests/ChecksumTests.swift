import Foundation
import XCTest
@testable import ChecksumCore

final class ChecksumTests: XCTestCase {
    private func withFile(_ data: Data, body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    func testKnownABCChecksums() throws {
        let expected: [Algorithm: String] = [
            .sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            .sha384: "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7",
            .sha512: "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
            .sha1: "a9993e364706816aba3e25717850c26c9cd0d89d",
            .md5: "900150983cd24fb0d6963f7d28e17f72"
        ]
        try withFile(Data("abc".utf8)) { url in
            for algorithm in Algorithm.allCases {
                XCTAssertEqual(try Checksum.hash(file: url, algorithm: algorithm), expected[algorithm])
            }
        }
    }

    func testEmptyFile() throws {
        try withFile(Data()) { url in
            XCTAssertEqual(try Checksum.hash(file: url, algorithm: .sha256),
                           "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        }
    }

    func testMultipleReadChunks() throws {
        // Published SHA-256 vector for one million ASCII 'a' bytes, repeated
        // twice to cross the 1 MiB read boundary. Compare against the system tool.
        try withFile(Data(repeating: 97, count: 2_000_000)) { url in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
            process.arguments = ["-a", "256", url.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let expected = String(decoding: output, as: UTF8.self).split(separator: " ")[0]
            XCTAssertEqual(try Checksum.hash(file: url, algorithm: .sha256), String(expected))
        }
    }

    func testRejectsDirectoryAndMissingFile() {
        XCTAssertThrowsError(try Checksum.hash(file: FileManager.default.temporaryDirectory, algorithm: .sha256))
        XCTAssertThrowsError(try Checksum.hash(file: URL(fileURLWithPath: "/tmp/\(UUID())"), algorithm: .sha256))
    }
}
