import Foundation

/// Reads the transaction identifier inside an App receipt. Apple's StoreKit verification
/// supplies the signature decision separately. A receipt from another purchase is insufficient.
enum WalletReceipt {
    private struct Field {
        let tag: UInt8
        let bytes: ArraySlice<UInt8>

        func children() -> [Field]? {
            var fields: [Field] = []
            var at = bytes.startIndex
            while at < bytes.endIndex {
                guard fields.count < 65_536, let field = Self.read(bytes, at: &at) else { return nil }
                fields.append(field)
            }
            return fields
        }

        static func read(_ input: ArraySlice<UInt8>, at index: inout Int, depth: Int = 0) -> Field? {
            guard depth < 16, index >= input.startIndex, input.endIndex - index >= 2 else { return nil }
            let tag = input[index]
            let size = input[index + 1]
            index += 2
            if size == 0x80 {
                // SignedData commonly uses BER containers with an end-of-contents marker.
                guard tag & 0x20 != 0 else { return nil }
                let begin = index
                while input.endIndex - index >= 2 {
                    if input[index] == 0, input[index + 1] == 0 {
                        let value = input[begin..<index]
                        index += 2
                        return Field(tag: tag, bytes: value)
                    }
                    guard Self.read(input, at: &index, depth: depth + 1) != nil else { return nil }
                }
                return nil
            }
            var length = Int(size)
            if size >= 128 {
                let width = Int(size & 127)
                guard (1...4).contains(width), input.endIndex - index >= width else { return nil }
                length = 0
                for _ in 0..<width { length = length * 256 + Int(input[index]); index += 1 }
            }
            guard input.endIndex - index >= length else { return nil }
            let contents = input[index..<(index + length)]
            index += length
            return Field(tag: tag, bytes: contents)
        }

        func octetContents(depth: Int = 0) -> ArraySlice<UInt8>? {
            if tag == 4 { return bytes }
            guard depth < 12, tag == 0x24, let segments = children() else { return nil }
            var joined: [UInt8] = []
            for segment in segments {
                guard let piece = segment.octetContents(depth: depth + 1) else { return nil }
                joined.append(contentsOf: piece)
            }
            return joined[...]
        }

        var integer: Int? {
            guard tag == 2, (1...4).contains(bytes.count) else { return nil }
            return bytes.reduce(0) { $0 * 256 + Int($1) }
        }

        func attribute(_ type: Int) -> Field? {
            guard tag == 0x30, let fields = children(), fields.count == 3, fields[0].integer == type,
                  fields[1].integer != nil, fields[2].tag == 4 else { return nil }
            return fields[2]
        }

        func single(_ tag: UInt8) -> Field? {
            guard let fields = children(), fields.count == 1, fields[0].tag == tag else { return nil }
            return fields[0]
        }
    }

    static func contains(_ transaction: String, in receipt: Data) -> Bool {
        guard !receipt.isEmpty, receipt.count <= 8_388_608 else { return false }
        let input = Array(receipt)[...]
        var at = input.startIndex
        guard let wrapper = Field.read(input, at: &at), at == input.endIndex, wrapper.tag == 0x30,
              let content = wrapper.children(), content.count == 2, content[1].tag == 0xa0,
              let signed = content[1].single(0x30)?.children(), signed.count >= 3, signed[2].tag == 0x30,
              let capsule = signed[2].children(), capsule.count == 2, capsule[1].tag == 0xa0,
              let segments = capsule[1].children(), segments.count == 1,
              let bytes = segments[0].octetContents(),
              let attributes = Field(tag: 4, bytes: bytes).single(0x31)?.children() else { return false }
        for attribute in attributes {
            guard let item = attribute.attribute(17)?.single(0x31)?.children() else { continue }
            for value in item {
                guard let id = value.attribute(1703)?.single(0x0c),
                      String(bytes: id.bytes, encoding: .utf8) == transaction else { continue }
                return true
            }
        }
        return false
    }
}
