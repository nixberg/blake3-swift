import EndianBytes

struct ChunkState {
    var chainingValue: KeyWords
    var counter: UInt64
    var block: [UInt8]
    var compressedBlocks: Int
    let flags: Flags
    
    var count: Int {
        compressedBlocks * BLAKE3.blockByteCount + block.count
    }
    
    var startFlag: Flags {
        compressedBlocks == 0 ? .chunkStart : []
    }
    
    init(_ key: KeyWords, counter: UInt64, flags: Flags) {
        chainingValue = key
        self.counter = counter
        block = []
        block.reserveCapacity(BLAKE3.blockByteCount)
        compressedBlocks = 0
        self.flags = flags
    }
    
    mutating func reset(key: KeyWords, counter: UInt64) {
        chainingValue = key
        self.counter = counter
        block.removeAll(keepingCapacity: true)
        compressedBlocks = 0
    }
    
    mutating func absorb(_ byte: UInt8) {
        assert((0...BLAKE3.blockByteCount).contains(block.count))
        
        if block.count == BLAKE3.blockByteCount {
            chainingValue = BlockWords(littleEndianBytes: block).compressed(
                with: chainingValue,
                blockLength: BLAKE3.blockByteCount,
                counter: counter,
                flags: flags.union(startFlag)
            ).lowHalf
            
            compressedBlocks += 1
            block.removeAll(keepingCapacity: true)
        }
        
        block.append(byte)
    }
    
    
    mutating func absorb<Bytes>(contentsOf bytes: Bytes)
    where Bytes: Collection, Bytes.Element == UInt8 {
        var bytes = bytes[...]
        
        while !bytes.isEmpty {
            if block.count == BLAKE3.blockByteCount {
                chainingValue = BlockWords(littleEndianBytes: block).compressed(
                    with: chainingValue,
                    blockLength: BLAKE3.blockByteCount,
                    counter: counter,
                    flags: flags.union(startFlag)
                ).lowHalf
                
                compressedBlocks += 1
                block.removeAll(keepingCapacity: true)
            }
            
            let bytesWanted = BLAKE3.blockByteCount - block.count
            block.append(contentsOf: bytes.prefix(bytesWanted))
            bytes = bytes.dropFirst(bytesWanted)
        }
    }
}
