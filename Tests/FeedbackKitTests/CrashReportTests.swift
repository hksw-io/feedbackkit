#if os(iOS) || os(macOS)
import Foundation
import MetricKit
import Testing
@testable import FeedbackKit

struct CrashReportTests {
    static let kernel = "11111111-1111-1111-1111-111111111111"
    static let core = "22222222-2222-2222-2222-222222222222"
    static let app = "33333333-3333-3333-3333-333333333333"
    static let ui = "44444444-4444-4444-4444-444444444444"

    /// The shape of `MXCallStackTree.jsonRepresentation()`: a frame's callers nest under it, its own fields may
    /// come after them, and strings may be escaped.
    static let mxTree = Data(#"""
    {
      "callStackPerThread" : true,
      "callStacks" : [
        {
          "threadAttributed" : false,
          "callStackRootFrames" : [
            {"binaryUUID" : "11111111-1111-1111-1111-111111111111", "offsetIntoBinaryTextSegment" : 4096, "sampleCount" : 1, "binaryName" : "libsystem_kernel.dylib", "address" : 7203947008}
          ]
        },
        {
          "threadAttributed" : true,
          "callStackRootFrames" : [
            {
              "binaryUUID" : "22222222-2222-2222-2222-222222222222",
              "offsetIntoBinaryTextSegment" : 100,
              "sampleCount" : 1,
              "subFrames" : [
                {
                  "subFrames" : [
                    {"binaryUUID" : "44444444-4444-4444-4444-444444444444", "offsetIntoBinaryTextSegment" : 220, "sampleCount" : 1, "binaryName" : "SwiftUICore", "address" : 7203950000}
                  ],
                  "binaryUUID" : "33333333-3333-3333-3333-333333333333",
                  "offsetIntoBinaryTextSegment" : 1715004,
                  "sampleCount" : 1,
                  "binaryName" : "Swiftflip",
                  "address" : 4295000000
                }
              ],
              "binaryName" : "libswiftCore.dylib",
              "address" : 7203940000
            }
          ]
        }
      ]
    }
    """#.utf8)

    static let crashedThread = [
        CrashReport.Frame(binary: "libswiftCore.dylib", uuid: core, offset: 100),
        CrashReport.Frame(binary: "Swiftflip", uuid: app, offset: 1_715_004),
        CrashReport.Frame(binary: "SwiftUICore", uuid: ui, offset: 220),
    ]

    static func report(
        _ tree: Data = mxTree,
        appBinaries: Set<String> = ["Swiftflip"],
        appVersion: String = "1.23.0 (295)",
        exceptionName: String? = nil,
        className: String? = nil) throws -> CrashReport?
    {
        try CrashReport(
            callStackTree: tree,
            appBinaries: appBinaries,
            appVersion: appVersion,
            system: "iPhone OS 26.1 (23B85)",
            device: "iPhone17,2",
            exceptionType: 1,
            exceptionCode: 0,
            signal: 11,
            exceptionName: exceptionName,
            className: className)
    }

    @Test
    func `the crashed thread's frames come top first, and the site is the first in the app's own code`() throws {
        let report = try #require(try Self.report())

        #expect(report.frames == Self.crashedThread)
        #expect(report.site == "Swiftflip+0x1a2b3c")
        #expect(report.appVersion == "1.23.0 (295)")
        #expect(report.system == "iPhone OS 26.1 (23B85)")
        #expect(report.device == "iPhone17,2")
        #expect(report.exceptionType == 1)
        #expect(report.exceptionCode == 0)
        #expect(report.signal == 11)
    }

    @Test
    func `a crash outside the app's own code is placed at its top frame`() throws {
        let report = try #require(try Self.report(appBinaries: ["Otherdesk"]))

        #expect(report.site == "libswiftCore.dylib+0x64")
    }

    @Test
    func `a stack thousands of frames deep is read, and only its top 512 are kept`() throws {
        let callers = (1 ..< 3000).map { depth in
            #"{"binaryUUID" : "\#(Self.ui)", "offsetIntoBinaryTextSegment" : \#(depth), "binaryName" : "\#(depth == 700 ? "Swiftflip" : "SwiftUICore")", "subFrames" : ["#
        }
        let innermost = #"{"binaryUUID" : "\#(Self.ui)", "offsetIntoBinaryTextSegment" : 3000, "binaryName" : "SwiftUICore"}"#
        let frame = callers.joined() + innermost + String(repeating: "]}", count: callers.count)
        let tree = Data(#"{"callStackPerThread" : true, "callStacks" : [{"threadAttributed" : true, "callStackRootFrames" : [\#(frame)]}]}"#.utf8)

        let report = try #require(try Self.report(tree))

        #expect(report.frames.count == 512)
        #expect(report.frames.map(\.offset) == Array(1 ... 512))
        #expect(report.site == "Swiftflip+0x2bc", "the app's own frame below the 512 kept still places the crash")
    }

    @Test
    func `a crash without a frame makes no report`() throws {
        let empty = Data(#"{"callStackPerThread" : true, "callStacks" : [{"threadAttributed" : true, "callStackRootFrames" : []}]}"#.utf8)

        #expect(try Self.report(empty) == nil)
    }

    @Test
    func `text longer than the service takes is cut, and an empty exception name is none`() throws {
        let report = try #require(try Self.report(
            appVersion: String(repeating: "1", count: 150),
            exceptionName: String(repeating: "E", count: 300),
            className: ""))

        #expect(report.appVersion.count == 100)
        #expect(report.exceptionName?.count == 200)
        #expect(report.className == nil)
    }

    @Test
    func `a report encodes only the fields the service takes`() throws {
        let report = try #require(try Self.report(exceptionName: "NSInvalidArgumentException", className: "NSException"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let json = try #require(try JSONSerialization.jsonObject(with: encoder.encode(report)) as? [String: Any])

        #expect(Set(json.keys) == [
            "appVersion", "system", "device", "exceptionType", "exceptionCode", "signal",
            "exceptionName", "className", "site", "frames",
        ])
        let frames = try #require(json["frames"] as? [[String: Any]])
        #expect(frames.map { Set($0.keys) } == Array(repeating: ["binary", "uuid", "offset"], count: 3))
        let bare = try #require(try Self.report())
        let bareJSON = try #require(try JSONSerialization.jsonObject(with: encoder.encode(bare)) as? [String: Any])
        #expect(bareJSON["exceptionName"] == nil && bareJSON["className"] == nil, "a field with nothing in it is left out")
    }

    @Test
    @available(iOS 27, macOS 27, *)
    func `the typed report of iOS and macOS 27 gives the same report as MetricKit's JSON`() throws {
        let diagnostic = try JSONDecoder().decode(CrashDiagnostic.self, from: Data(#"""
        {
          "exceptionType" : 1,
          "exceptionCode" : 0,
          "signal" : 11,
          "exceptionReason" : {
            "composedMessage" : "-[Deck title]: unrecognized selector sent to Ana's deck",
            "formatString" : "%@",
            "arguments" : ["Ana's deck"],
            "exceptionType" : "",
            "className" : "NSException",
            "exceptionName" : "NSInvalidArgumentException"
          },
          "callStackTree" : {
            "callStackPerThread" : true,
            "binaryInfo" : [
              {"uuid" : "11111111-1111-1111-1111-111111111111", "name" : "libsystem_kernel.dylib"},
              {"uuid" : "22222222-2222-2222-2222-222222222222", "name" : "libswiftCore.dylib"},
              {"uuid" : "33333333-3333-3333-3333-333333333333", "name" : "Swiftflip"},
              {"uuid" : "44444444-4444-4444-4444-444444444444", "name" : "SwiftUICore"}
            ],
            "callStackThreads" : [
              {"threadAttributed" : false, "rootFrames" : [
                {"binaryUUID" : "11111111-1111-1111-1111-111111111111", "offsetIntoBinaryTextSegment" : 4096, "address" : 7203947008, "sampleCount" : 1, "subFrames" : []}
              ]},
              {"threadAttributed" : true, "rootFrames" : [
                {"binaryUUID" : "22222222-2222-2222-2222-222222222222", "offsetIntoBinaryTextSegment" : 100, "address" : 7203940000, "sampleCount" : 1, "subFrames" : [
                  {"binaryUUID" : "33333333-3333-3333-3333-333333333333", "offsetIntoBinaryTextSegment" : 1715004, "address" : 4295000000, "sampleCount" : 1, "subFrames" : [
                    {"binaryUUID" : "44444444-4444-4444-4444-444444444444", "offsetIntoBinaryTextSegment" : 220, "address" : 7203950000, "sampleCount" : 1, "subFrames" : []}
                  ]}
                ]}
              ]}
            ]
          }
        }
        """#.utf8))

        let typed = try #require(CrashReport(
            diagnostic,
            appBinaries: ["Swiftflip"],
            appVersion: "1.23.0 (295)",
            system: "iPhone OS 26.1 (23B85)",
            device: "iPhone17,2"))

        #expect(typed == (try #require(try Self.report(exceptionName: "NSInvalidArgumentException", className: "NSException"))))
    }
}
#endif
