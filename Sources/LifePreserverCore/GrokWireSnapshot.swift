import Foundation

/// Subscription protobuf fields verified against Grok's web billing descriptor.
/// Parsing is bounded to known messages; unknown fields never become inferred usage.
public enum GrokWireSnapshot {
    public enum ParseError: Error { case invalid, authentication, noUsage }
    public static func window(_ data: Data, now: Date = Date()) throws -> UsageWindow {
        guard !data.isEmpty, data.count <= 4_194_304 else { throw ParseError.invalid }
        let bytes = [UInt8](data)
        var messages: [Data] = []
        if bytes[0] == 0 || bytes[0] == 128 {
            var i = 0
            while i < bytes.count {
                guard i + 5 <= bytes.count else { throw ParseError.invalid }
                let flags = bytes[i]
                let count = Int(bytes[i+1]) << 24 | Int(bytes[i+2]) << 16 | Int(bytes[i+3]) << 8 | Int(bytes[i+4])
                i += 5
                guard count <= bytes.count - i else { throw ParseError.invalid }
                let frame = Data(bytes[i..<i+count]); i += count
                if flags == 0 { messages.append(frame) }
                else if flags == 128 {
                    let trailer = String(decoding: frame, as: UTF8.self)
                    for line in trailer.components(separatedBy: .newlines) where line.lowercased().hasPrefix("grpc-status:") {
                        guard line.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) == "0" else { throw ParseError.authentication }
                    }
                } else { throw ParseError.invalid }
            }
        } else { messages = [data] }
        guard messages.count == 1 else { throw ParseError.invalid }
        var floats: [String: Double] = [:], integers: [String: UInt64] = [:]
        try scan([UInt8](messages[0]), path: "", floats: &floats, integers: &integers)
        let start = integers["1.8.2.1"].map { Date(timeIntervalSince1970: Double($0)) }
        let end = integers["1.8.3.1"].map { Date(timeIntervalSince1970: Double($0)) }
        let reset = end ?? integers["1.5.1"].map { Date(timeIntervalSince1970: Double($0)) }
        let period = integers["1.8.1"]
        var used = floats["1.1"]
        if used == nil, floats.isEmpty, [1, 2].contains(period),
           let start, let end, start <= now, end > now {
            // The descriptor declares this as a proto3 implicit-presence scalar.
            used = 0
        }
        guard let used, used.isFinite, (0...100).contains(used) else { throw ParseError.noUsage }
        let duration = start.flatMap { start in end.map { Int($0.timeIntervalSince(start) / 60) } }
        return UsageWindow(id: "grok-subscription", title: (duration ?? 0) > 20_000 ? "Monthly" : "Weekly",
            usedPercent: used, durationMinutes: duration, resetsAt: reset)
    }
    private static let messages: Set<String> = ["1", "1.5", "1.6", "1.8", "1.8.2", "1.8.3"]
    private static func scan(_ bytes: [UInt8], path: String, floats: inout [String: Double], integers: inout [String: UInt64]) throws {
        var i = 0
        while i < bytes.count {
            let key = try varint(bytes, index: &i)
            let field = key >> 3
            guard field > 0, field <= 536_870_911 else { throw ParseError.invalid }
            let full = path.isEmpty ? "\(field)" : "\(path).\(field)"
            switch key & 7 {
            case 0: integers[full] = try varint(bytes, index: &i)
            case 1:
                guard i + 8 <= bytes.count else { throw ParseError.invalid }; i += 8
            case 2:
                let count = try varint(bytes, index: &i)
                guard count <= UInt64(bytes.count - i) else { throw ParseError.invalid }
                if messages.contains(full) { try scan(Array(bytes[i..<i+Int(count)]), path: full, floats: &floats, integers: &integers) }
                i += Int(count)
            case 5:
                guard i + 4 <= bytes.count else { throw ParseError.invalid }
                let bits = UInt32(bytes[i]) | UInt32(bytes[i+1]) << 8 | UInt32(bytes[i+2]) << 16 | UInt32(bytes[i+3]) << 24
                floats[full] = Double(Float(bitPattern: bits)); i += 4
            default: throw ParseError.invalid
            }
        }
    }
    private static func varint(_ bytes: [UInt8], index: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard index < bytes.count else { throw ParseError.invalid }
            let byte = bytes[index]; index += 1
            if shift == 63 && byte > 1 { throw ParseError.invalid }
            result |= UInt64(byte & 127) << shift
            if byte & 128 == 0 { return result }
        }
        throw ParseError.invalid
    }
}
