import Algorithms
import EndianBytes

struct TheOutput {
    private let inputChainingValue: KeyWords
    private let block: BlockWords
    private let blockLength: Int
    private let counter: UInt64
    private let flags: Flags
    
    init(_ chunkState: ChunkState) {
        inputChainingValue = chunkState.chainingValue
        block = BlockWords(littleEndianBytes:
                            chunkState.block.paddingEnd(with: 0, toCount: BLAKE3.blockByteCount))
        blockLength = chunkState.block.count
        counter = chunkState.counter
        flags = chunkState.flags.union(chunkState.startFlag).union(.chunkEnd)
    }
    
    init(key: KeyWords, left leftChild: KeyWords, right rightChild: KeyWords, flags: Flags) {
        inputChainingValue = key
        block = BlockWords(lowHalf: leftChild, highHalf: rightChild)
        blockLength = BLAKE3.blockByteCount
        counter = 0
        self.flags = flags.union(.parent)
    }
    
    var chainingValue: KeyWords {
        block.compressed(
            with: inputChainingValue,
            blockLength: blockLength,
            counter: counter,
            flags: flags
        ).lowHalf
    }
    
    func writeRootBytes<Output>(to output: inout Output, outputByteCount: Int)
    where Output: RangeReplaceableCollection, Output.Element == UInt8 {
        var count = outputByteCount
        var outputBlockCounter: UInt64 = 0
        
        while count > 0 {
            let words = block.compressed(
                with: inputChainingValue,
                blockLength: blockLength,
                counter: outputBlockCounter,
                flags: flags.union(.root)
            )
            
            output.append(contentsOf: words
                                        .indices
                                        .lazy
                                        .map { words[$0].littleEndianBytes() }
                                        .joined()
                                        .prefix(count))
            
            count -= BLAKE3.blockByteCount
            outputBlockCounter += 1
        }
    }
}

// TODO: Remove when/if available in Algorithms.
fileprivate extension Collection {
    func paddingEnd(
        with element: Element,
        toCount paddedCount: Int
    ) -> Chain2Sequence<Self, Repeated<Self.Element>> {
        chain(self, repeatElement(element, count: Swift.max(paddedCount - count, 0)))
    }
}
