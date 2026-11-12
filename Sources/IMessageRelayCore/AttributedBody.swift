import Foundation

/// Decodes `message.attributedBody` into plain text.
///
/// On macOS, NSKeyedUnarchiver / NSUnarchiver run first for bplist and
/// typedstream blobs. Every platform then falls back to the length-prefixed
/// NSString scan used by Messages typedstream archives.
public enum AttributedBodyDecoder {
    public static func decode(_ data: Data) -> String? {
        #if os(macOS)
        if let text = AppleTypedStreamDecoder.decode(data), !text.isEmpty {
            return text
        }
        #endif
        return decodeFallback(data)
    }

    /// Byte scan: find `NSString` / `NSMutableString`, then a nearby `+`
    /// typedstream string tag and its length-prefixed UTF-8 payload.
    public static func decodeFallback(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        let markers: [[UInt8]] = [
            Array("NSString".utf8),
            Array("NSMutableString".utf8),
        ]
        var search = 0
        while search < bytes.count {
            guard let found = earliestMarker(in: bytes, markers: markers, from: search) else {
                return nil
            }
            if let text = stringPayload(in: bytes, markerEnd: found.end), !text.isEmpty {
                return text
            }
            search = found.start + 1
        }
        return nil
    }
}

#if os(macOS)
enum AppleTypedStreamDecoder {
    static func decode(_ data: Data) -> String? {
        if data.starts(with: Data("bplist".utf8)) {
            if let attributed = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSAttributedString.self,
                from: data
            ), !attributed.string.isEmpty {
                return attributed.string
            }
            if let object = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) {
                if let attributed = object as? NSAttributedString, !attributed.string.isEmpty {
                    return attributed.string
                }
                if let text = object as? String, !text.isEmpty {
                    return text
                }
            }
        }
        if data.starts(with: Data("streamtyped".utf8)) {
            let object = NSUnarchiver.unarchiveObject(with: data)
            if let attributed = object as? NSAttributedString, !attributed.string.isEmpty {
                return attributed.string
            }
            if let text = object as? String, !text.isEmpty {
                return text
            }
        }
        return nil
    }
}
#endif

private struct MarkerMatch {
    var start: Int
    var end: Int
}

private func earliestMarker(in bytes: [UInt8], markers: [[UInt8]], from start: Int) -> MarkerMatch? {
    var best: MarkerMatch?
    for marker in markers {
        guard let index = indexOf(marker, in: bytes, from: start) else { continue }
        if best == nil || index < best!.start {
            best = MarkerMatch(start: index, end: index + marker.count)
        }
    }
    return best
}

private func indexOf(_ needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int? {
    guard !needle.isEmpty, start >= 0, haystack.count >= needle.count else { return nil }
    var index = start
    let last = haystack.count - needle.count
    while index <= last {
        if Array(haystack[index..<(index + needle.count)]) == needle {
            return index
        }
        index += 1
    }
    return nil
}

private func stringPayload(in bytes: [UInt8], markerEnd: Int) -> String? {
    let windowEnd = min(bytes.count, markerEnd + 24)
    guard markerEnd < windowEnd else { return nil }
    guard let plus = bytes[markerEnd..<windowEnd].firstIndex(of: 0x2B) else { return nil }
    guard let (length, payloadStart) = typedstreamLength(bytes, index: plus + 1) else { return nil }
    guard length > 0, payloadStart <= bytes.count, length <= bytes.count - payloadStart else {
        return nil
    }
    return String(bytes: bytes[payloadStart..<(payloadStart + length)], encoding: .utf8)
}

/// Typedstream integer used as a string length.
/// A byte below 0x80 is the length. 0x81 / 0x82 / 0x83 introduce a
/// little-endian 2 / 4 / 8 byte length. Negative lengths are rejected.
private func typedstreamLength(_ bytes: [UInt8], index: Int) -> (Int, Int)? {
    guard index < bytes.count else { return nil }
    let tag = bytes[index]
    if tag < 0x80 {
        return (Int(tag), index + 1)
    }
    let width: Int
    switch tag {
    case 0x81: width = 2
    case 0x82: width = 4
    case 0x83: width = 8
    default: return nil
    }
    guard index + 1 + width <= bytes.count else { return nil }
    var value: UInt64 = 0
    for offset in 0..<width {
        value |= UInt64(bytes[index + 1 + offset]) << (UInt64(offset) * 8)
    }
    let signBit = UInt64(1) << (UInt64(width) * 8 - 1)
    if value & signBit != 0 { return nil }
    guard value <= 1_000_000, value <= UInt64(Int.max) else { return nil }
    return (Int(value), index + 1 + width)
}
