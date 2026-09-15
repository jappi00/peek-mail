import Foundation

/// Minimal reader for Microsoft Compound File Binary (OLE2) containers, as used by Outlook .msg files.
final class CompoundFile {
    struct Entry {
        var name: String
        var type: UInt8 // 1 = storage, 2 = stream, 5 = root
        var left: UInt32
        var right: UInt32
        var child: UInt32
        var start: UInt32
        var size: Int
    }

    private static let maxRegular: UInt32 = 0xFFFF_FFFA
    private static let noStream: UInt32 = 0xFFFF_FFFF

    private let bytes: [UInt8]
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniCutoff: Int
    private var fat: [UInt32] = []
    private var miniFat: [UInt32] = []
    private var miniStream: [UInt8] = []
    private(set) var entries: [Entry] = []

    init(_ data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count >= 512, bytes.starts(with: MailParser.oleSignature) else {
            throw MailParserError.invalidFile("Not an Outlook message file.")
        }
        sectorSize = 1 << Int(Self.u16(bytes, 0x1E))
        miniSectorSize = 1 << Int(Self.u16(bytes, 0x20))
        guard sectorSize == 512 || sectorSize == 4096 else {
            throw MailParserError.invalidFile("Unsupported compound file sector size.")
        }
        let firstDir = Self.u32(bytes, 0x30)
        miniCutoff = Int(Self.u32(bytes, 0x38))
        let firstMiniFat = Self.u32(bytes, 0x3C)
        let firstDifat = Self.u32(bytes, 0x44)

        var fatSectors: [UInt32] = []
        for k in 0..<109 {
            let v = Self.u32(bytes, 0x4C + k * 4)
            if v < Self.maxRegular { fatSectors.append(v) }
        }
        var difat = firstDifat
        var hops = 0
        while difat < Self.maxRegular, hops < 100_000 {
            let off = offset(difat)
            guard off + sectorSize <= bytes.count else { break }
            let perSector = sectorSize / 4 - 1
            for k in 0..<perSector {
                let v = Self.u32(bytes, off + k * 4)
                if v < Self.maxRegular { fatSectors.append(v) }
            }
            difat = Self.u32(bytes, off + perSector * 4)
            hops += 1
        }
        for s in fatSectors {
            let off = offset(s)
            guard off + sectorSize <= bytes.count else { continue }
            for k in 0..<(sectorSize / 4) { fat.append(Self.u32(bytes, off + k * 4)) }
        }

        let dir = readChain(firstDir)
        var off = 0
        while off + 128 <= dir.count {
            let nameLen = min(Int(Self.u16(dir, off + 64)), 64)
            let nameBytes = Array(dir[off..<(off + max(0, nameLen - 2))])
            let name = String(bytes: nameBytes, encoding: .utf16LittleEndian) ?? ""
            var size = Int(Self.u32(dir, off + 120))
            if sectorSize == 4096 { size |= Int(Self.u32(dir, off + 124)) << 32 }
            entries.append(Entry(
                name: name, type: dir[off + 66],
                left: Self.u32(dir, off + 68), right: Self.u32(dir, off + 72), child: Self.u32(dir, off + 76),
                start: Self.u32(dir, off + 116), size: size))
            off += 128
        }
        guard let root = entries.first, root.type == 5 else {
            throw MailParserError.invalidFile("Compound file has no root entry.")
        }

        let miniFatBytes = readChain(firstMiniFat)
        miniFat = stride(from: 0, to: miniFatBytes.count - 3, by: 4).map { Self.u32(miniFatBytes, $0) }
        miniStream = readChain(root.start, size: root.size)
    }

    func children(of index: Int) -> [Int] {
        guard index < entries.count else { return [] }
        var result: [Int] = []
        var visited = Set<Int>()
        var stack = [entries[index].child]
        while let node = stack.popLast() {
            guard node != Self.noStream, Int(node) < entries.count, visited.insert(Int(node)).inserted else { continue }
            result.append(Int(node))
            stack.append(entries[Int(node)].left)
            stack.append(entries[Int(node)].right)
        }
        return result
    }

    func data(of index: Int) -> [UInt8] {
        let entry = entries[index]
        if entry.size < miniCutoff {
            return readMiniChain(entry.start, size: entry.size)
        }
        return readChain(entry.start, size: entry.size)
    }

    private func offset(_ sector: UInt32) -> Int { (Int(sector) + 1) * sectorSize }

    private func readChain(_ start: UInt32, size: Int? = nil) -> [UInt8] {
        var out: [UInt8] = []
        var sector = start
        var hops = 0
        while sector < Self.maxRegular, Int(sector) < fat.count, hops <= fat.count {
            let off = offset(sector)
            guard off < bytes.count else { break }
            out.append(contentsOf: bytes[off..<min(off + sectorSize, bytes.count)])
            if let size, out.count >= size { break }
            sector = fat[Int(sector)]
            hops += 1
        }
        if let size, out.count > size { out.removeLast(out.count - size) }
        return out
    }

    private func readMiniChain(_ start: UInt32, size: Int) -> [UInt8] {
        var out: [UInt8] = []
        var sector = start
        var hops = 0
        while sector < Self.maxRegular, Int(sector) < miniFat.count, hops <= miniFat.count, out.count < size {
            let off = Int(sector) * miniSectorSize
            guard off < miniStream.count else { break }
            out.append(contentsOf: miniStream[off..<min(off + miniSectorSize, miniStream.count)])
            sector = miniFat[Int(sector)]
            hops += 1
        }
        if out.count > size { out.removeLast(out.count - size) }
        return out
    }

    static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        guard o + 2 <= b.count else { return 0 }
        return UInt16(b[o]) | UInt16(b[o + 1]) << 8
    }

    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}
