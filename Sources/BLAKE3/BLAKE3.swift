import Foundation

typealias Key = SIMD8<UInt32>
typealias Block = SIMD16<UInt32>

public struct BLAKE3 {
    public static let keyLength = 32
    public static let outputLength = 32
    
    static let blockLength = 64
    private static let chunkLength = 1024
    private static let maximumDepth = 54
    
    static let initializationVector = Key(
        0x6a09e667,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19
    )
    
    private let key: Key
    private let flags: Flags
    private var currentChunk: ChunkState
    private var stack: [Key] = []
    
    private init(key: Key, flags: Flags) {
        self.key = key
        self.flags = flags
        currentChunk = ChunkState(key, counter: 0, flags: flags)
        stack.reserveCapacity(Self.maximumDepth)
    }
    
    public init() {
        self.init(key: Self.initializationVector, flags: [])
    }
    
    public init<D>(withKey key: D) where D: DataProtocol {
        precondition(key.count == Self.keyLength)
        self.init(key: Key(fromLittleEndianBytes: key), flags: .keyedHash)
    }
    
    public init<S>(derivingKeyWithContext context: S) where S: StringProtocol {
        var hash = Self(key: Self.initializationVector, flags: .deriveKeyContext)
        hash.update(with: ArraySlice(context.utf8))
        self.init(key: Key(fromLittleEndianBytes: hash.finalize()), flags: .deriveKeyMaterial)
    }
    
    public mutating func update<D>(with input: D) where D : DataProtocol {
        var input = input[...]
        
        while !input.isEmpty {
            if currentChunk.count == Self.chunkLength {
                let counter = currentChunk.counter + 1
                
                var chainingValue = currentChunk.output().chainingValue()
                for _ in 0..<counter.trailingZeroBitCount {
                    chainingValue = Output(key: key, left: stack.popLast()!, right: chainingValue, flags: flags).chainingValue()
                }
                stack.append(chainingValue)
                
                currentChunk.reset(key: key, counter: counter)
            }
            
            let bytesWanted = Self.chunkLength - currentChunk.count
            currentChunk.update(with: input.prefix(bytesWanted))
            input = input.dropFirst(bytesWanted)
        }
    }
    
    public func finalize<M>(to output: inout M, count: Int) where M: MutableDataProtocol {
        stack.reversed().reduce(currentChunk.output()) {
            Output(key: key, left: $1, right: $0.chainingValue(), flags: flags)
        }.writeRootBytes(to: &output, count: count)
    }
    
    public func finalize(count: Int = Self.outputLength) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(count)
        self.finalize(to: &output, count: count)
        return output
    }
}

struct Flags: OptionSet {
    let rawValue: UInt32
    
    static let chunkStart        = Flags(rawValue: 1 << 0)
    static let chunkEnd          = Flags(rawValue: 1 << 1)
    static let parent            = Flags(rawValue: 1 << 2)
    static let root              = Flags(rawValue: 1 << 3)
    static let keyedHash         = Flags(rawValue: 1 << 4)
    static let deriveKeyContext  = Flags(rawValue: 1 << 5)
    static let deriveKeyMaterial = Flags(rawValue: 1 << 6)
}

public extension BLAKE3 {
    static func hash<D, M>(_ input: D, to output: inout M, count: Int = BLAKE3.outputLength)
        where D: DataProtocol, M: MutableDataProtocol {
        var hash = BLAKE3()
        hash.update(with: input)
        hash.finalize(to: &output, count: count)
    }
    
    static func hash<D>(_ input: D, count: Int = BLAKE3.outputLength) -> [UInt8] where D: DataProtocol {
        var output: [UInt8] = []
        output.reserveCapacity(count)
        hash(input, to: &output, count: count)
        return output
    }
    
    static func hash<D, K, M>(_ input: D, withKey key: K, to output: inout M, count: Int = BLAKE3.outputLength)
        where D: DataProtocol, K: DataProtocol, M: MutableDataProtocol {
        var hash = BLAKE3(withKey: key)
        hash.update(with: input)
        hash.finalize(to: &output, count: count)
    }
    
    static func hash<D, K>(_ input: D, withKey key: K, count: Int = BLAKE3.outputLength) -> [UInt8] where D: DataProtocol, K: DataProtocol {
        var output: [UInt8] = []
        output.reserveCapacity(count)
        hash(input, withKey: key, to: &output, count: count)
        return output
    }
    
    static func deriveKey<D, S, M>(from input: D, withContext context: S, to output: inout M, count: Int = BLAKE3.outputLength)
        where D: DataProtocol, S: StringProtocol, M: MutableDataProtocol {
        var hash = BLAKE3(derivingKeyWithContext: context)
        hash.update(with: input)
        hash.finalize(to: &output, count: count)
    }
    
    static func deriveKey<D, S>(from input: D, withContext context: S, count: Int = BLAKE3.outputLength) -> [UInt8] where D: DataProtocol, S: StringProtocol {
        var output: [UInt8] = []
        output.reserveCapacity(count)
        deriveKey(from: input, withContext: context, to: &output, count: count)
        return output
    }
}

fileprivate struct ChunkState {
    private var chainingValue: Key
    var counter: UInt64
    private var block: [UInt8]
    private var compressedBlocks: Int
    private let flags: Flags
    
    var count: Int {
        compressedBlocks * BLAKE3.blockLength + block.count
    }
    
    private var startFlag: Flags {
        compressedBlocks == 0 ? .chunkStart : []
    }
    
    init(_ key: Key, counter: UInt64, flags: Flags) {
        chainingValue = key
        self.counter = counter
        block = []
        block.reserveCapacity(BLAKE3.blockLength)
        compressedBlocks = 0
        self.flags = flags
    }
    
    mutating func reset(key: Key, counter: UInt64) {
        chainingValue = key
        self.counter = counter
        block.removeAll(keepingCapacity: true)
        compressedBlocks = 0
    }
    
    mutating func update<D>(with input: D) where D: DataProtocol {
        var input = input[...]
        
        while !input.isEmpty {
            if block.count == BLAKE3.blockLength {
                chainingValue = Block(fromLittleEndianBytes: block).compressed(
                    with: chainingValue,
                    blockLength: BLAKE3.blockLength,
                    counter: counter,
                    flags: flags.union(startFlag)
                ).lowHalf
                
                compressedBlocks += 1
                block.removeAll(keepingCapacity: true)
            }
            
            let bytesWanted = BLAKE3.blockLength - block.count
            block.append(contentsOf: input.prefix(bytesWanted))
            input = input.dropFirst(bytesWanted)
        }
    }
    
    func output() -> Output {
        Output(
            inputChainingValue: chainingValue,
            block: Block(fromLittleEndianBytes: block),
            blockLength: block.count,
            counter: counter,
            flags: flags.union(startFlag).union(.chunkEnd)
        )
    }
}

fileprivate struct Output {
    private let inputChainingValue: Key
    private let block: Block
    private let blockLength: Int
    private let counter: UInt64
    private let flags: Flags
    
    init(inputChainingValue: Key, block: Block, blockLength: Int, counter: UInt64, flags: Flags) {
        self.inputChainingValue = inputChainingValue
        self.block = block
        self.blockLength = blockLength
        self.counter = counter
        self.flags = flags
    }
    
    init(key: Key, left leftChild: Key, right rightChild: Key, flags: Flags) {
        inputChainingValue = key
        block = Block(lowHalf: leftChild, highHalf: rightChild)
        blockLength = BLAKE3.blockLength
        counter = 0
        self.flags = flags.union(.parent)
    }
    
    func chainingValue() -> Key {
        block.compressed(with: inputChainingValue, blockLength: blockLength, counter: counter, flags: flags).lowHalf
    }
    
    func writeRootBytes<M>(to output: inout M, count: Int) where M: MutableDataProtocol {
        var count = count
        var outputBlockCounter: UInt64 = 0
        
        while count > 0 {
            let words = block.compressed(
                with: inputChainingValue,
                blockLength: blockLength,
                counter: outputBlockCounter,
                flags: flags.union(.root)
            )
            
            for index in 0..<min(count, BLAKE3.blockLength) {
                let (i, j) = index.quotientAndRemainder(dividingBy: 4)
                output.append(UInt8(truncatingIfNeeded: words[i] &>> (8 * j)))
            }
            
            count -= BLAKE3.blockLength
            outputBlockCounter += 1
        }
    }
}

fileprivate extension SIMD where Scalar: FixedWidthInteger & UnsignedInteger {
    init<D>(fromLittleEndianBytes data: D) where D: DataProtocol {
        assert(data.count <= MemoryLayout<Self>.size)
        self.init()
        for (index, byte) in data.enumerated() {
            let (i, j) = index.quotientAndRemainder(dividingBy: MemoryLayout<Scalar>.size)
            self[i] |= Scalar(byte) &<< (8 * j)
        }
    }
}
