import XCTest
import BLAKE3

final class BLAKE3Tests: XCTestCase {
    func test() throws {
        struct Vector: Decodable {
            let inputLength: Int
            let hash: String
            let keyedHash: String
            let derivedKey: String
        }
        
        let data = try Data(contentsOf: URL(fileURLWithPath: #file)
            .deletingLastPathComponent().appendingPathComponent("vectors.json"))
        let vectors = try JSONDecoder().decode([Vector].self, from: data)
        
        let maxInputLength = vectors.max { $0.inputLength < $1.inputLength }!.inputLength
        let input = [UInt8](sequence(first: 0) { ($0 + 1) % 251 }.prefix(maxInputLength))
        
        let key = ArraySlice("whats the Elvish word for friend".utf8)
        let context = "BLAKE3 2019-12-27 16:29:52 test vectors context"
        
        for vector in vectors {
            let input = input.prefix(vector.inputLength)
            
            var expected = Array(hex: vector.hash)
            XCTAssertEqual(BLAKE3.hash(input, count: expected.count), expected)
            
            expected = Array(hex: vector.keyedHash)
            XCTAssertEqual(BLAKE3.hash(input, withKey: key, count: expected.count), expected)
            
            expected = Array(hex: vector.derivedKey)
            XCTAssertEqual(BLAKE3.deriveKey(from: input, withContext: context, count: expected.count), expected)
        }
    }
}

fileprivate extension Array where Element == UInt8 {
    init(hex: String) {
        precondition(hex.count.isMultiple(of: 2))
        var hex = hex[...]
        self = stride(from: 0, to: hex.count, by: 2).map { _ in
            defer { hex = hex.dropFirst(2) }
            return UInt8(hex.prefix(2), radix: 16)!
        }
    }
}
