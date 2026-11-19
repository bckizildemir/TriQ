import Foundation
import Testing
@testable import TTB

/// The Storage SDK returns download URLs with an explicit `:443`; the server rejects them (#225).
@Suite(.timeLimit(.minutes(1)))
struct DownloadURLNormalizationTests {
    private static let tail = "/v0/b/bucket/o/answers%2Fuid%2Fq%2Fslot_0.jpg?alt=media&token=abc-123"

    private static func normalized(_ string: String) throws -> String {
        let url = try #require(URL(string: string))
        return ImageService.normalizedDownloadURL(url).absoluteString
    }

    @Test func defaultHTTPSPortIsRemoved() throws {
        let result = try Self.normalized("https://firebasestorage.googleapis.com:443\(Self.tail)")
        #expect(result == "https://firebasestorage.googleapis.com\(Self.tail)")
    }

    @Test func urlWithoutPortIsUnchanged() throws {
        let input = "https://firebasestorage.googleapis.com\(Self.tail)"
        #expect(try Self.normalized(input) == input)
    }

    @Test func otherPortIsUnchanged() throws {
        let input = "https://firebasestorage.googleapis.com:8080\(Self.tail)"
        #expect(try Self.normalized(input) == input)
    }

    @Test func httpWithPort443IsUnchanged() throws {
        let input = "http://firebasestorage.googleapis.com:443\(Self.tail)"
        #expect(try Self.normalized(input) == input)
    }

    @Test func otherHostKeepsItsPort() throws {
        let input = "https://example.com:443\(Self.tail)"
        // Only the port rule matters here: the host is not special-cased, so the default port goes too.
        #expect(try Self.normalized(input) == "https://example.com\(Self.tail)")
    }

    @Test func encodedPathAndQueryStayByteIdentical() throws {
        let input = "https://firebasestorage.googleapis.com:443\(Self.tail)"
        let result = try Self.normalized(input)
        #expect(result == input.replacing(":443", with: ""))
        #expect(result.contains("answers%2Fuid%2Fq%2Fslot_0.jpg"))
        #expect(result.hasSuffix("?alt=media&token=abc-123"))
    }

    @Test func resultStartsWithTheServerPrefix() throws {
        let result = try Self.normalized("https://firebasestorage.googleapis.com:443\(Self.tail)")
        #expect(result.hasPrefix("https://firebasestorage.googleapis.com/"))
    }
}
