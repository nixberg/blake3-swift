import BLAKE3
import HexString
import XCTest

final class BLAKE3Tests: XCTestCase {
    func test() throws {
        struct TestVectors: Decodable {
            let key: String
            let context: String
            let cases: [Case]
            
            enum CodingKeys: String, CodingKey {
                case key
                case context = "context_string"
                case cases
            }
        }
        
        struct Case: Decodable {
            let inputByteCount: Int
            @HexString var hash:       [UInt8]
            @HexString var keyedHash:  [UInt8]
            @HexString var derivedKey: [UInt8]
            
            enum CodingKeys: String, CodingKey {
                case inputByteCount = "input_len"
                case hash
                case keyedHash = "keyed_hash"
                case derivedKey = "derive_key"
            }
        }
        
        let url = Bundle.module.url(forResource: "test_vectors", withExtension: "json")!
        let testVectors = try JSONDecoder().decode(TestVectors.self, from: try Data(contentsOf: url))
        
        let input = sequence(first: 0, next: { UInt8(($0 + 1) % 251) })
            .prefix(testVectors.cases.map(\.inputByteCount).max()!)
        
        zip(testVectors.cases.map { input.prefix($0.inputByteCount) }, testVectors.cases).forEach {
            XCTAssertEqual(
                BLAKE3.hash(contentsOf: $0, outputByteCount: $1.hash.count),
                $1.hash)
            
            XCTAssertEqual(
                BLAKE3.hash(
                    contentsOf: $0,
                    withKey: testVectors.key.utf8,
                    outputByteCount: $1.keyedHash.count),
                $1.keyedHash)
            
            XCTAssertEqual(
                BLAKE3.deriveKey(
                    fromContentsOf: $0,
                    withContext: testVectors.context,
                    outputByteCount: $1.derivedKey.count),
                $1.derivedKey)
        }
    }
}
