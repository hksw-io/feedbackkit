#if os(iOS) || os(macOS)
import Foundation
import MetricKit

/// A crash as the feedback service's `/v1/crash` takes it: the crashed thread's frames, the exception, and the
/// crashed run's version, system and device. An Objective-C exception's message and arguments are never part of it,
/// as they can hold what someone typed.
struct CrashReport: Encodable, Equatable, Sendable {
    struct Frame: Encodable, Equatable, Sendable {
        let binary: String
        let uuid: String
        let offset: UInt64
    }

    /// A thread's frames, top first.
    struct Thread {
        let crashed: Bool
        let frames: [Frame]
    }

    static let maxFrames = 512

    let appVersion: String
    let system: String
    let device: String
    let exceptionType: Int?
    let exceptionCode: UInt64?
    let signal: Int?
    let exceptionName: String?
    let className: String?
    /// The first frame in the app's own code, or the top frame when there is none: what the service groups by.
    /// `nil`, with no frames, when MetricKit gave the crashed thread no stack.
    let site: String?
    let frames: [Frame]

    init(
        threads: [Thread],
        appBinaries: Set<String>,
        appVersion: String,
        system: String,
        device: String,
        exceptionType: Int?,
        exceptionCode: UInt64?,
        signal: Int?,
        exceptionName: String?,
        className: String?)
    {
        let frames = (threads.first(where: \.crashed) ?? threads.first { !$0.frames.isEmpty })?.frames ?? []
        let site = frames.first { appBinaries.contains($0.binary) } ?? frames.first
        self.appVersion = String(appVersion.prefix(100))
        self.system = String(system.prefix(100))
        self.device = String(device.prefix(100))
        self.exceptionType = exceptionType
        self.exceptionCode = exceptionCode
        self.signal = signal
        self.exceptionName = exceptionName.flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
        self.className = className.flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
        self.site = site.map { "\($0.binary.prefix(100))+0x\(String($0.offset, radix: 16))" }
        self.frames = frames.prefix(Self.maxFrames).map { Frame(binary: String($0.binary.prefix(100)), uuid: $0.uuid, offset: $0.offset) }
    }
}

extension CrashReport.Frame {
    init?(binary: String?, uuid: String?, offset: UInt64?) {
        guard let binary, !binary.isEmpty, let uuid, let offset else { return nil }
        self.init(binary: binary, uuid: uuid, offset: offset)
    }
}

// MARK: - MXCrashDiagnostic, iOS 26

extension CrashReport {
    init(_ diagnostic: MXCrashDiagnostic, appBinaries: Set<String>) throws {
        try self.init(
            callStackTree: diagnostic.callStackTree.jsonRepresentation(),
            appBinaries: appBinaries,
            appVersion: "\(diagnostic.applicationVersion) (\(diagnostic.metaData.applicationBuildVersion))",
            system: diagnostic.metaData.osVersion,
            device: diagnostic.metaData.deviceType,
            exceptionType: diagnostic.exceptionType?.intValue,
            exceptionCode: diagnostic.exceptionCode?.uint64Value,
            signal: diagnostic.signal?.intValue,
            exceptionName: diagnostic.exceptionReason?.exceptionName,
            className: diagnostic.exceptionReason?.className)
    }

    /// From the JSON `MXCallStackTree.jsonRepresentation()` writes. Each frame nests its callers in it, so a deep
    /// stack is deeper than Foundation's JSON reader goes (512 levels, about 255 frames). `CallStackScanner` reads it
    /// in one pass instead, without building the tree.
    init(
        callStackTree: Data,
        appBinaries: Set<String>,
        appVersion: String,
        system: String,
        device: String,
        exceptionType: Int?,
        exceptionCode: UInt64?,
        signal: Int?,
        exceptionName: String?,
        className: String?) throws
    {
        self.init(
            threads: try CallStackScanner.threads(in: callStackTree),
            appBinaries: appBinaries,
            appVersion: appVersion,
            system: system,
            device: device,
            exceptionType: exceptionType,
            exceptionCode: exceptionCode,
            signal: signal,
            exceptionName: exceptionName,
            className: className)
    }
}

/// Reads the threads and frames out of MetricKit's JSON call stack tree in a single pass, keeping only a stack of
/// the containers it is inside, so a stack of any depth costs no recursion.
enum CallStackScanner {
    struct Malformed: Error {}

    private enum Role {
        case none
        case thread
        case frame(Int)
    }

    private struct Container {
        let isObject: Bool
        /// An object's current key, or the key an array is the value of.
        var key: String?
        let role: Role
    }

    private struct Partial {
        var binary: String?
        var uuid: String?
        var offset: UInt64?
    }

    static func threads(in json: Data) throws(Malformed) -> [CrashReport.Thread] {
        let bytes = [UInt8](json)
        var index = 0
        var path: [Container] = []
        var threads: [(crashed: Bool, frames: [Partial])] = []
        var expectsKey = false

        func value(_ text: String, isString: Bool) {
            guard let container = path.last, container.isObject, let key = container.key else { return }
            switch container.role {
            case .thread where key == "threadAttributed" && !isString:
                threads[threads.count - 1].crashed = text == "true"
            case let .frame(frame):
                switch key {
                case "binaryName" where isString: threads[threads.count - 1].frames[frame].binary = text
                case "binaryUUID" where isString: threads[threads.count - 1].frames[frame].uuid = text
                case "offsetIntoBinaryTextSegment" where !isString: threads[threads.count - 1].frames[frame].offset = UInt64(text)
                default: break
                }
            default:
                break
            }
        }

        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t"), UInt8(ascii: ":"):
                index += 1
            case UInt8(ascii: "{"):
                var role = Role.none
                if let array = path.last, !array.isObject {
                    switch array.key {
                    case "callStacks":
                        threads.append((false, []))
                        role = .thread
                    case "callStackRootFrames", "subFrames":
                        guard !threads.isEmpty else { throw Malformed() }
                        threads[threads.count - 1].frames.append(Partial())
                        role = .frame(threads[threads.count - 1].frames.count - 1)
                    default:
                        break
                    }
                }
                path.append(Container(isObject: true, key: nil, role: role))
                expectsKey = true
                index += 1
            case UInt8(ascii: "["):
                path.append(Container(isObject: false, key: path.last?.isObject == true ? path.last?.key : nil, role: .none))
                index += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                guard path.popLast() != nil else { throw Malformed() }
                expectsKey = false
                index += 1
            case UInt8(ascii: ","):
                expectsKey = path.last?.isObject == true
                index += 1
            case UInt8(ascii: "\""):
                let text = try self.string(bytes, from: &index)
                if expectsKey, path.last?.isObject == true {
                    path[path.count - 1].key = text
                    expectsKey = false
                } else {
                    value(text, isString: true)
                }
            default:
                let start = index
                while index < bytes.count, !Self.delimiters.contains(bytes[index]) {
                    index += 1
                }
                value(String(decoding: bytes[start ..< index], as: UTF8.self), isString: false)
            }
        }
        guard path.isEmpty else { throw Malformed() }
        return threads.map { thread in
            CrashReport.Thread(
                crashed: thread.crashed,
                frames: thread.frames.compactMap { CrashReport.Frame(binary: $0.binary, uuid: $0.uuid, offset: $0.offset) })
        }
    }

    private static let delimiters: Set<UInt8> = Set(" \n\r\t,:{}[]\"".utf8)

    /// A JSON string starting at the quote at `index`, unescaped; `index` ends past its closing quote.
    private static func string(_ bytes: [UInt8], from index: inout Int) throws(Malformed) -> String {
        var scalars = String.UnicodeScalarView()
        var utf8: [UInt8] = []
        func flush() {
            scalars.append(contentsOf: String(decoding: utf8, as: UTF8.self).unicodeScalars)
            utf8.removeAll(keepingCapacity: true)
        }
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                flush()
                return String(scalars)
            case UInt8(ascii: "\\"):
                guard index < bytes.count else { throw Malformed() }
                let escaped = bytes[index]
                index += 1
                switch escaped {
                case UInt8(ascii: "n"): utf8.append(0x0A)
                case UInt8(ascii: "t"): utf8.append(0x09)
                case UInt8(ascii: "r"): utf8.append(0x0D)
                case UInt8(ascii: "b"): utf8.append(0x08)
                case UInt8(ascii: "f"): utf8.append(0x0C)
                case UInt8(ascii: "u"):
                    var code = try Self.hex(bytes, at: &index)
                    if (0xD800 ..< 0xDC00).contains(code), index + 1 < bytes.count,
                       bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u")
                    {
                        index += 2
                        let low = try Self.hex(bytes, at: &index)
                        code = 0x10000 + (code - 0xD800) << 10 + low &- 0xDC00
                    }
                    flush()
                    scalars.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                default: utf8.append(escaped)
                }
            default:
                utf8.append(byte)
            }
        }
        throw Malformed()
    }

    private static func hex(_ bytes: [UInt8], at index: inout Int) throws(Malformed) -> UInt32 {
        guard index + 4 <= bytes.count, let code = UInt32(String(decoding: bytes[index ..< index + 4], as: UTF8.self), radix: 16)
        else { throw Malformed() }
        index += 4
        return code
    }
}

// MARK: - CrashDiagnostic, iOS and macOS 27

@available(iOS 27, macOS 27, *)
extension CrashReport {
    init(_ diagnostic: CrashDiagnostic, appBinaries: Set<String>, appVersion: String, system: String, device: String) {
        let tree = diagnostic.callStackTree
        self.init(
            threads: tree.callStackThreads.map { thread in
                CrashReport.Thread(crashed: thread.threadAttributed == true, frames: Self.frames(thread.rootFrames, in: tree))
            },
            appBinaries: appBinaries,
            appVersion: appVersion,
            system: system,
            device: device,
            exceptionType: diagnostic.exceptionType,
            exceptionCode: diagnostic.exceptionCode,
            signal: diagnostic.signal,
            exceptionName: diagnostic.exceptionReason?.exceptionName,
            className: diagnostic.exceptionReason?.className)
    }

    /// Top first, each frame before its callers, with a stack of its own rather than recursion: a crash from
    /// runaway recursion has thousands of frames.
    private static func frames(_ roots: ContiguousArray<CallStackFrame>, in tree: CallStackTree) -> [Frame] {
        var frames: [Frame] = []
        var pending = Array(roots.reversed())
        while let frame = pending.popLast() {
            if let own = Frame(binary: frame.binaryName(from: tree), uuid: frame.binaryUUID?.uuidString, offset: frame.offsetIntoBinaryTextSegment) {
                frames.append(own)
            }
            pending.append(contentsOf: frame.subFrames.reversed())
        }
        return frames
    }
}
#endif
