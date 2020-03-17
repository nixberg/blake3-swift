import Foundation

fileprivate extension FixedWidthInteger where Self: UnsignedInteger {
    @inline(__always)
    func rotated<T>(right count: T) -> Self where T: BinaryInteger {
        let right = Int(truncatingIfNeeded: count) & (Self.bitWidth - 1) // Assuming Self.bitWidth is a power of two.
        let left = Self.bitWidth - right
        return (self &<< left) | (self &>> right)
    }
}

fileprivate extension Block {
    @inline(__always)
    mutating func quarterRound(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt32, _ y: UInt32) {
        self[a] &+= self[b] &+ x
        self[d] = (self[d] ^ self[a]).rotated(right: 16)
        self[c] &+= self[d]
        self[b] = (self[b] ^ self[c]).rotated(right: 12)
        
        self[a] &+= self[b] &+ y
        self[d] = (self[d] ^ self[a]).rotated(right: 8)
        self[c] &+= self[d]
        self[b] = (self[b] ^ self[c]).rotated(right: 7)
    }
    
    mutating func round(with message: Block) {
        self.quarterRound(0, 4,  8, 12, message[ 0], message[ 1])
        self.quarterRound(1, 5,  9, 13, message[ 2], message[ 3])
        self.quarterRound(2, 6, 10, 14, message[ 4], message[ 5])
        self.quarterRound(3, 7, 11, 15, message[ 6], message[ 7])
        
        self.quarterRound(0, 5, 10, 15, message[ 8], message[ 9])
        self.quarterRound(1, 6, 11, 12, message[10], message[11])
        self.quarterRound(2, 7,  8, 13, message[12], message[13])
        self.quarterRound(3, 4,  9, 14, message[14], message[15])
    }
    
    @inline(__always)
    mutating func permute() {
        self = self[SIMD16(2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8)]
    }
}

extension Block {
    func compressed(with chainingValue: Key, blockLength: Int, counter: UInt64, flags: Flags) -> Self {
        var state = Block(
            lowHalf: chainingValue,
            highHalf: SIMD8(
                lowHalf: BLAKE3.initializationVector.lowHalf,
                highHalf: SIMD4(
                    UInt32(truncatingIfNeeded: counter),
                    UInt32(truncatingIfNeeded: counter &>> 32),
                    UInt32(blockLength),
                    flags.rawValue
                )
            )
        )
        var message = self
        
        state.round(with: message)
        message.permute()
        state.round(with: message)
        message.permute()
        state.round(with: message)
        message.permute()
        state.round(with: message)
        message.permute()
        state.round(with: message)
        message.permute()
        state.round(with: message)
        message.permute()
        state.round(with: message)
        
        state.lowHalf ^= state.highHalf
        state.highHalf ^= chainingValue
        
        return state
    }
}
