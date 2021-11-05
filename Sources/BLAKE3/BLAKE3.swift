import Duplex
import EndianBytes

typealias KeyWords = SIMD8<UInt32>

typealias BlockWords = SIMD16<UInt32>

struct Flags: OptionSet {
    let rawValue: UInt32
    
    static let chunkStart        = Self(rawValue: 1 << 0)
    static let chunkEnd          = Self(rawValue: 1 << 1)
    static let parent            = Self(rawValue: 1 << 2)
    static let root              = Self(rawValue: 1 << 3)
    static let keyedHash         = Self(rawValue: 1 << 4)
    static let deriveKeyContext  = Self(rawValue: 1 << 5)
    static let deriveKeyMaterial = Self(rawValue: 1 << 6)
}

public struct BLAKE3: Duplex {
    public typealias Output = [UInt8]
    
    public static let defaultOutputByteCount = 32
    
    public static let keyByteCount = 32
    
    static let blockByteCount = 64
    private static let chunkByteCount = 1024
    private static let maxStackDepth = 54
    
    static let initializationVector = KeyWords(
        0x6a09e667,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19
    )
    
    private let key: KeyWords
    private let flags: Flags
    
    private var currentChunk: ChunkState
    private var stack: [KeyWords] = []
    
    private var isDone = false
    
    init(key: KeyWords, flags: Flags) {
        self.key = key
        self.flags = flags
        currentChunk = ChunkState(key, counter: 0, flags: flags)
    }
    
    public init() {
        self.init(key: Self.initializationVector, flags: [])
    }
    
    public mutating func absorb<Bytes>(contentsOf bytes: Bytes)
    where Bytes: Sequence, Bytes.Element == UInt8 {
        precondition(!isDone)
        
        for byte in bytes {
            if currentChunk.count == Self.chunkByteCount {
                let counter = currentChunk.counter + 1
                
                let chainingValue = stack
                    .reversed()
                    .prefix(counter.trailingZeroBitCount)
                    .reduce(TheOutput(currentChunk).chainingValue) {
                        TheOutput(key: key, left: $1, right: $0, flags: flags).chainingValue
                    }
                
                stack.removeLast(counter.trailingZeroBitCount)
                stack.append(chainingValue)
                
                currentChunk.reset(key: key, counter: counter)
            }
            
            currentChunk.absorb(byte)
        }
    }
    
    public mutating func squeeze<Output>(to output: inout Output, outputByteCount: Int)
    where Output: RangeReplaceableCollection, Output.Element == UInt8 {
        precondition(!isDone)
        precondition(outputByteCount > 0)
        
        stack
            .reversed()
            .reduce(TheOutput(currentChunk)) {
                TheOutput(key: key, left:  $1, right: $0.chainingValue, flags: flags)
            }
            .writeRootBytes(to: &output, outputByteCount: outputByteCount)
        
        stack.removeAll()
        isDone = true
    }
    
    public mutating func squeeze(outputByteCount: Int) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(outputByteCount)
        self.squeeze(to: &output, outputByteCount: outputByteCount)
        return output
    }
}

public extension BLAKE3 {
    init<Key>(key: Key) where Key: Collection, Key.Element == UInt8 {
        precondition(key.count == Self.keyByteCount, "TODO")
        self.init(key: KeyWords(littleEndianBytes: key)!, flags: .keyedHash)
    }
    
    init<Context>(derivingKeyWithContext context: Context) where Context: StringProtocol {
        var hash = Self(key: Self.initializationVector, flags: .deriveKeyContext)
        hash.absorb(contentsOf: context.utf8)
        self.init(key: KeyWords(littleEndianBytes: hash.squeeze())!, flags: .deriveKeyMaterial)
    }
    
    static func hash<Bytes, Key, Output>(
        contentsOf bytes: Bytes,
        withKey key: Key,
        to output: inout Output,
        outputByteCount: Int = Self.defaultOutputByteCount
    ) where
        Bytes: Sequence, Bytes.Element == UInt8,
        Key: Collection, Key.Element == UInt8,
        Output: RangeReplaceableCollection, Output.Element == UInt8
    {
        var hash = Self(key: key)
        hash.absorb(contentsOf: bytes)
        hash.squeeze(to: &output, outputByteCount: outputByteCount)
    }
    
    static func hash<Bytes, Key>(
        contentsOf bytes: Bytes,
        withKey key: Key,
        outputByteCount: Int = Self.defaultOutputByteCount
    ) -> Self.Output where
        Bytes: Sequence, Bytes.Element == UInt8,
        Key: Collection, Key.Element == UInt8
    {
        var output: [UInt8] = []
        output.reserveCapacity(outputByteCount)
        Self.hash(contentsOf: bytes, withKey: key, to: &output, outputByteCount: outputByteCount)
        return output
    }
    
    static func deriveKey<Bytes, Context, Output>(
        fromContentsOf bytes: Bytes,
        withContext context: Context,
        to output: inout Output,
        outputByteCount: Int = Self.defaultOutputByteCount
    ) where
        Bytes: Sequence, Bytes.Element == UInt8,
        Context: StringProtocol,
        Output: RangeReplaceableCollection, Output.Element == UInt8
    {
        var hash = Self(derivingKeyWithContext: context)
        hash.absorb(contentsOf: bytes)
        hash.squeeze(to: &output, outputByteCount: outputByteCount)
    }
    
    static func deriveKey<Bytes, Context>(
        fromContentsOf bytes: Bytes,
        withContext context: Context,
        outputByteCount: Int = Self.defaultOutputByteCount
    ) -> Self.Output where
        Bytes: Sequence, Bytes.Element == UInt8,
        Context: StringProtocol
    {
        var output: [UInt8] = []
        output.reserveCapacity(outputByteCount)
        Self.deriveKey(
            fromContentsOf: bytes,
            withContext: context,
            to: &output,
            outputByteCount: outputByteCount)
        return output
    }
}

extension BlockWords {
    func compressed(
        with chainingValue: KeyWords,
        blockLength: Int,
        counter: UInt64,
        flags: Flags
    ) -> Self {
        var state = BlockWords(
            lowHalf: chainingValue,
            highHalf: SIMD8(
                lowHalf: BLAKE3.initializationVector.lowHalf,
                highHalf: SIMD4(
                    UInt32(truncatingIfNeeded: counter),
                    UInt32(truncatingIfNeeded: counter >> 32),
                    UInt32(blockLength),
                    flags.rawValue
                )
            )
        )
        var message = self
        
        for _ in 1...7 {
            state.round(with: message)
            message.permute()
        }
        
        state.lowHalf ^= state.highHalf
        state.highHalf ^= chainingValue
        
        return state
    }
    
    @inline(__always)
    private mutating func round(with message: BlockWords) {
        self.quarterRound(00, 04, 08, 12, message[00], message[01])
        self.quarterRound(01, 05, 09, 13, message[02], message[03])
        self.quarterRound(02, 06, 10, 14, message[04], message[05])
        self.quarterRound(03, 07, 11, 15, message[06], message[07])
        
        self.quarterRound(00, 05, 10, 15, message[08], message[09])
        self.quarterRound(01, 06, 11, 12, message[10], message[11])
        self.quarterRound(02, 07, 08, 13, message[12], message[13])
        self.quarterRound(03, 04, 09, 14, message[14], message[15])
    }
    
    @inline(__always)
    private mutating func quarterRound(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt32, _ y: UInt32) {
        self[a] &+= self[b] &+ x
        self[d] = (self[d] ^ self[a]).rotated(right: 16)
        self[c] &+= self[d]
        self[b] = (self[b] ^ self[c]).rotated(right: 12)
        
        self[a] &+= self[b] &+ y
        self[d] = (self[d] ^ self[a]).rotated(right: 08)
        self[c] &+= self[d]
        self[b] = (self[b] ^ self[c]).rotated(right: 07)
    }
    
    @inline(__always)
    private mutating func permute() {
        self = self[SIMD16(2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8)]
    }
}

// TODO: Remove when availible in Numerics.
fileprivate extension UInt32 {
    @inline(__always)
    func rotated(right count: Int) -> Self {
        (self &<< (Self.bitWidth - count)) | (self &>> count)
    }
}
