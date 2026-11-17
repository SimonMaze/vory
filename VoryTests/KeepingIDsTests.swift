#if os(iOS)
import Foundation
import Testing
@testable import VoryCore

/// A snapshot's rows paired with the rows shown (`ChatSession.keepingIDs`) on iPhone and iPad. Rows
/// the two lists agree on from the top are paired first; past them, a tool row whose command appears
/// once on each side; every other row is paired by what it says, as before, only between those
/// pairs. A running tool a snapshot left out no longer moves every later tool of the same name onto
/// its neighbor's id, also in a long chat that runs the same commands every turn, and no pair the
/// one-pass pairing got right is lost (`keepingIDs55`, kept here to compare).
@Suite struct KeepingIDsTests {
    // MARK: Rows

    static func user(_ id: String, _ text: String) -> TranscriptItem {
        TranscriptItem(id: id, kind: .user(text: text, attachments: []))
    }
    static func reply(_ id: String, _ text: String) -> TranscriptItem {
        TranscriptItem(id: id, kind: .assistant(text: text, reasoning: nil, streaming: false))
    }
    static func tool(_ id: String, _ name: String, _ context: String?) -> TranscriptItem {
        TranscriptItem(id: id, kind: .tool(ToolActivity(id: id, name: name, context: context, status: .done)))
    }
    static func note(_ id: String) -> TranscriptItem {
        TranscriptItem(id: id, kind: .system(text: "Reconnected", symbol: "bolt"))
    }

    /// The one-pass pairing by what each row says, a tool by its name: build 55's `keepingIDs`, its code unchanged and
    /// its comments left out.
    static func keepingIDs55(_ built: [TranscriptItem], from shown: [TranscriptItem]) -> [TranscriptItem] {
        func said(_ item: TranscriptItem) -> String? {
            switch item.kind {
            case .user(let t, _): return "u" + t.trimmingCharacters(in: .whitespacesAndNewlines)
            case .assistant(_, let r, false) where item.isThinkingOnly: return "r" + StreamAssembler.normalized(String((r ?? "").prefix(600))).prefix(300)
            case .assistant(let t, _, let streaming): return streaming ? nil : "a" + t.trimmingCharacters(in: .whitespacesAndNewlines)
            case .tool(let act): return "t" + act.name
            default: return nil
            }
        }
        var out = built
        var next = 0
        var taken = Set<String>()
        for i in out.indices {
            if let words = said(out[i]),
               let j = shown[next...].prefix(6).firstIndex(where: { said($0) == words }), !taken.contains(shown[j].id) {
                out[i].id = shown[j].id
                next = j + 1
            } else if taken.contains(out[i].id) {
                out[i].id += "-\(i)"
            }
            taken.insert(out[i].id)
        }
        return out
    }

    // MARK: The tools turn of the measured run

    /// One part of the turn: a tool call (name, command) or a reply's words.
    enum Part { case call(String, String?), words(String) }

    static let prompt = "tools"
    static let intro = "Checking the whole host before I touch anything."
    static let answer = "## The host, top to bottom\n\nDisk is the only real problem."
    static let parts: [Part] = [
        .call("terminal", "df -h /"),
        .call("terminal", "du -sh /var/log/* | sort -rh | head"),
        .words("Logs are the big one. Memory next."),
        .call("terminal", "free -h"),
        .call("terminal", "uptime"),
        .call("read_file", "/etc/logrotate.d/nginx"),
        .words("There it is: `rotate 52` keeps a year of nginx logs."),
        .call("terminal", "systemctl --failed"),
        .call("terminal", "systemctl status nginx postgresql"),
        .words("Services are healthy. Checking the backups now."),
        .call("terminal", "ls -lh /backups | tail -5"),
        .call("terminal", "df -h /backups"),
        .call("search_files", "nightly-export"),
        .words("The nightly export writes its dumps to the backups disk."),
        .call("terminal", "journalctl -p err --since today | tail -3"),
        .call("terminal", "psql -c 'show max_wal_size'"),
    ]
    /// The live tool ids, in order.
    static let toolIDs = ["tool-t-b9fbe73a", "tool-t-7c40024c", "tool-t-b8891918", "tool-t-9568ff93", "tool-t-14b6edb7", "tool-t-2ca3ab16",
                          "tool-t-d5755f10", "tool-t-d7234628", "tool-t-57564b89", "tool-t-f4f5e8e8", "tool-t-7cf6606e", "tool-t-90774349"]

    /// The turn as the snapshot builds it (`h-` ids, one row before it from earlier), as it was shown live (the live
    /// ids; `liveContext` gives each call's context as live sent it, nil to leave the call out), and for each built
    /// row the live id it truly is (nil where the live row was left out).
    static func turn(liveContext: (Int, String?) -> String?? = { _, c in .some(c) }) -> (built: [TranscriptItem], shown: [TranscriptItem], truth: [String?]) {
        var built = [reply("h-97-96", "Earlier answer.")], shown = [reply("h-97-96", "Earlier answer.")]
        var truth: [String?] = ["h-97-96"]
        var index = 98
        func h() -> String { defer { index += 1 }; return "h-\(index + 1)-\(index)" }
        built.append(user(h(), prompt)); shown.append(user("inflight-user-1794790826", prompt)); truth.append("inflight-user-1794790826")
        built.append(reply(h(), intro)); shown.append(reply("stream-9E71", intro)); truth.append("stream-9E71")
        var call = 0, words = 0
        for part in parts {
            switch part {
            case .call(let name, let context):
                built.append(tool(h(), name, context))
                if case .some(let live) = liveContext(call, context) {
                    shown.append(tool(toolIDs[call], name, live)); truth.append(toolIDs[call])
                } else {
                    truth.append(nil)
                }
                call += 1
            case .words(let w):
                words += 1
                built.append(reply(h(), w)); shown.append(reply("stream-\(words)", w)); truth.append("stream-\(words)")
            }
        }
        built.append(reply(h(), answer)); shown.append(reply("stream-1019", answer)); truth.append("stream-1019")
        return (built, shown, truth)
    }

    // MARK: 1. The measured run's shape

    @Test func aDroppedRunningToolLeavesEveryOtherRowItsOwnID() throws {
        // The first call (`df -h /`) was left out of the live rows by a snapshot while it ran.
        let (built, shown, truth) = Self.turn { i, c in i == 0 ? .none : .some(c) }
        let ids = ChatSession.keepingIDs(built, from: shown).map(\.id)
        #expect(Set(ids).count == ids.count)
        for i in built.indices {
            if let t = truth[i] { #expect(ids[i] == t, "row \(i)") } else { #expect(ids[i] == built[i].id, "row \(i) keeps its own") }
        }
        let search = try #require(built.firstIndex { if case .tool(let a) = $0.kind { return a.name == "search_files" }; return false })
        #expect(ids[search] == "tool-t-f4f5e8e8")
        // The one-pass pairing put each later terminal on its neighbor's id and lost this one.
        #expect(Self.keepingIDs55(built, from: shown).map(\.id)[search] != "tool-t-f4f5e8e8")
    }

    // MARK: 2. No command pairs: the result is the one-pass pairing's

    @Test func withNoCommandPairedTheResultIsTheOnePassPairings() {
        let cases: [(Int, String?) -> String??] = [
            { _, c in .some(c.map { "$ " + $0 }) },             // every live context formatted otherwise
            { _, _ in .some(nil) },                              // no live contexts
            { i, c in i == 0 ? .none : .some(c.map { "# " + $0 }) }, // and a call left out
        ]
        for live in cases {
            let (built, shown, _) = Self.turn(liveContext: live)
            #expect(ChatSession.keepingIDs(built, from: shown).map(\.id) == Self.keepingIDs55(built, from: shown).map(\.id))
        }
    }

    // MARK: 3. Some commands pair and some don't

    @Test func aPairTheOnePassPairingGotRightStaysRight() {
        // Every third call's live context formatted otherwise, the first call left out.
        let (built, shown, truth) = Self.turn { i, c in i == 0 ? .none : .some(i % 3 == 1 ? c.map { "$ " + $0 } : c) }
        let before = Self.keepingIDs55(built, from: shown).map(\.id)
        let now = ChatSession.keepingIDs(built, from: shown).map(\.id)
        #expect(Set(now).count == now.count)
        for i in built.indices where truth[i] != nil && before[i] == truth[i] { #expect(now[i] == truth[i], "row \(i)") }
        #expect(built.indices.filter { truth[$0] != nil && now[$0] == truth[$0] }.count
                > built.indices.filter { truth[$0] != nil && before[$0] == truth[$0] }.count)
    }

    // MARK: 4. Rows out of order and a row left out, pinned

    @Test func aReplyShownBeforeItsToolAndALeftOutCall() {
        let built = [Self.user("h1", "go"), Self.reply("h2", "On it."), Self.tool("h3", "terminal", "uptime"),
                     Self.reply("h4", "Up 41 days."), Self.tool("h5", "terminal", "free -h"), Self.tool("h6", "terminal", "df -h /"),
                     Self.reply("h7", "Disk is fine."), Self.reply("h8", "All good.")]
        // Live, the first reply came before its tool, and `free -h` was left out.
        let shown = [Self.user("p", "go"), Self.reply("i", "On it."), Self.reply("r1", "Up 41 days."), Self.tool("ta", "terminal", "uptime"),
                     Self.tool("tc", "terminal", "df -h /"), Self.reply("r2", "Disk is fine."), Self.reply("a", "All good.")]
        #expect(ChatSession.keepingIDs(built, from: shown).map(\.id) == ["p", "i", "ta", "h4", "h5", "tc", "r2", "a"])
        #expect(Self.keepingIDs55(built, from: shown).map(\.id) == ["p", "i", "ta", "h4", "tc", "h6", "r2", "a"])
    }

    // MARK: 5. The same call more than once

    @Test func repeatedCallsPairInOrder() {
        let built = [Self.user("h1", "check"), Self.tool("h2", "terminal", "uptime"), Self.tool("h3", "terminal", "df -h /"),
                     Self.tool("h4", "terminal", "uptime"), Self.tool("h5", "terminal", "uptime"), Self.reply("h6", "Done.")]
        let all = [Self.user("p", "check"), Self.tool("u1", "terminal", "uptime"), Self.tool("d", "terminal", "df -h /"),
                   Self.tool("u2", "terminal", "uptime"), Self.tool("u3", "terminal", "uptime"), Self.reply("a", "Done.")]
        #expect(ChatSession.keepingIDs(built, from: all).map(\.id) == ["p", "u1", "d", "u2", "u3", "a"])
        // One of them left out: the repeated calls go in order as the one-pass pairing has them.
        var shorter = all
        shorter.remove(at: 3)
        #expect(ChatSession.keepingIDs(built, from: shorter).map(\.id) == Self.keepingIDs55(built, from: shorter).map(\.id))
    }

    // MARK: 6. Tools with no command

    @Test func toolsWithNoCommandPairByName() {
        let built = [Self.user("h1", "plan"), Self.tool("h2", "todo_list", nil), Self.tool("h3", "terminal", ""),
                     Self.tool("h4", "todo_list", nil), Self.reply("h5", "Planned.")]
        let shown = [Self.user("p", "plan"), Self.tool("t1", "todo_list", nil), Self.tool("t2", "terminal", "  "),
                     Self.tool("t3", "todo_list", nil), Self.reply("a", "Planned.")]
        let ids = ChatSession.keepingIDs(built, from: shown).map(\.id)
        #expect(ids == ["p", "t1", "t2", "t3", "a"])
        #expect(ids == Self.keepingIDs55(built, from: shown).map(\.id))
    }

    // MARK: 7. Many turns, from a fixed seed

    /// SplitMix64: the same numbers on every run.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// A turn of 3 to 15 calls (often the same command more than once, some with none), words after some of them, up to
    /// two calls left out live, live-only notes, some live contexts formatted otherwise and some live words changed.
    static func randomTurn(_ g: inout Seeded) -> (built: [TranscriptItem], shown: [TranscriptItem], truth: [String?]) {
        let names = ["terminal", "terminal", "terminal", "terminal", "read_file", "search_files"]
        let commands = ["df -h /", "uptime", "free -h", "ls", "du -sh /var/log"]
        var parts: [Part] = []
        for k in 0..<Int.random(in: 3...15, using: &g) {
            let name = names.randomElement(using: &g)!
            let command = Double.random(in: 0..<1, using: &g) < 0.85 ? commands.randomElement(using: &g)! : nil
            parts.append(.call(name, command))
            if Double.random(in: 0..<1, using: &g) < 0.4 { parts.append(.words("Words after call \(k).")) }
        }
        let calls = parts.indices.filter { if case .call = parts[$0] { return true }; return false }
        let dropCount = [0, 1, 1, 2].randomElement(using: &g)!
        let drops = Set(calls.shuffled(using: &g).prefix(dropCount))
        let reformat = Bool.random(using: &g)
        var built = [user("h-0", "go"), reply("h-1", "On it.")], shown = [user("live-0", "go"), reply("live-1", "On it.")]
        var truth: [String?] = ["live-0", "live-1"]
        for (k, part) in parts.enumerated() {
            let n = k + 2
            switch part {
            case .call(let name, let command):
                built.append(tool("h-\(n)", name, command))
                if drops.contains(k) { truth.append(nil); continue }
                let live = reformat && Bool.random(using: &g) ? command.map { "$ " + $0 } : command
                shown.append(tool("live-\(n)", name, live)); truth.append("live-\(n)")
            case .words(let w):
                built.append(reply("h-\(n)", w))
                shown.append(reply("live-\(n)", Double.random(in: 0..<1, using: &g) < 0.1 ? w + " (live)" : w)); truth.append("live-\(n)")
            }
            if Double.random(in: 0..<1, using: &g) < 0.08 { shown.append(note("note-\(n)")) }
        }
        built.append(reply("h-end", "Done.")); shown.append(reply("live-end", "Done.")); truth.append("live-end")
        return (built, shown, truth)
    }

    @Test func manyTurnsNeverLoseARightPairOrShareAnID() {
        var g = Seeded(state: 0x5EED_0056)
        var lost: [String] = [], shared: [Int] = [], gained = 0
        for t in 0..<3000 {
            let (built, shown, truth) = Self.randomTurn(&g)
            let before = Self.keepingIDs55(built, from: shown).map(\.id)
            let now = ChatSession.keepingIDs(built, from: shown).map(\.id)
            if Set(now).count != now.count { shared.append(t) }
            for i in built.indices where truth[i] != nil {
                if before[i] == truth[i], now[i] != truth[i] { lost.append("turn \(t) row \(i)") }
                if before[i] != truth[i], now[i] == truth[i] { gained += 1 }
            }
        }
        #expect(lost.isEmpty, "right pairs lost: \(lost.prefix(5))")
        #expect(shared.isEmpty, "turns with a shared id: \(shared.prefix(5))")
        #expect(gained > 0)
    }

    // MARK: 8. A long chat running the same checks every turn

    static let checks: [(String, String)] = [
        ("terminal", "df -h /"), ("terminal", "free -h"), ("terminal", "uptime"), ("terminal", "systemctl --failed"),
        ("terminal", "du -sh /var/log"), ("terminal", "df -h /backups"), ("read_file", "/etc/logrotate.d/nginx"),
        ("search_files", "nightly-export"), ("terminal", "journalctl -p err --since today | tail -3"),
    ]

    /// `turns` turns of the same health checks with the same words. The turns in `live` were watched in this session:
    /// shown under their live ids with the stored words (an earlier snapshot gave them those). The others were loaded:
    /// shown under the snapshot's ids, or one index off (`shifted`). A note only this device shows follows turn
    /// `noteAfter`. The newest turn is still as it streamed: its contexts as `format` gives them, the calls in `drops`
    /// left out.
    static func longChat(turns: Int, live: Set<Int>, shifted: Bool, noteAfter: Int?, format: (String) -> String,
                         drops: Set<Int>) -> (built: [TranscriptItem], shown: [TranscriptItem], truth: [String?], newest: Int) {
        var built: [TranscriptItem] = [], shown: [TranscriptItem] = [], truth: [String?] = []
        var index = 0, newest = 0
        func add(_ make: (String, String?) -> TranscriptItem, turn: Int, key: String, context: String?, isNewest: Bool, left: Bool = false) {
            let id = "h-\(index + 1)-\(index)"
            built.append(make(id, context))
            defer { index += 1 }
            guard !left else { truth.append(nil); return }
            let shownID = live.contains(turn) ? "live-\(turn)-\(key)" : shifted ? "h-\(index + 2)-\(index + 1)" : id
            shown.append(make(shownID, isNewest ? context.map(format) : context))
            truth.append(shownID)
        }
        for t in 0..<turns {
            let isNewest = t == turns - 1
            if isNewest { newest = built.count }
            add({ id, _ in user(id, "check the host") }, turn: t, key: "u", context: nil, isNewest: isNewest)
            for (k, check) in checks.enumerated() {
                add({ id, c in tool(id, check.0, c) }, turn: t, key: "\(k)", context: check.1, isNewest: isNewest, left: isNewest && drops.contains(k))
                if k == 3 { add({ id, _ in reply(id, "Disk and services look fine.") }, turn: t, key: "w", context: nil, isNewest: isNewest) }
            }
            add({ id, _ in reply(id, "All checks done.") }, turn: t, key: "a", context: nil, isNewest: isNewest)
            if t == noteAfter { shown.append(note("note-\(t)")) }
        }
        return (built, shown, truth, newest)
    }

    @Test func aLongChatOfTheSameChecksKeepsTheNewestTurnsIDs() {
        // Twelve turns, four watched live (the newest among them), the loaded ones one index off, a note after turn 5,
        // and the newest turn's first call left out while it ran.
        let (built, shown, truth, newest) = Self.longChat(turns: 12, live: [3, 7, 8, 11], shifted: true, noteAfter: 5,
                                                          format: { $0 }, drops: [0])
        let ids = ChatSession.keepingIDs(built, from: shown).map(\.id)
        #expect(Set(ids).count == ids.count)
        for i in built.indices {
            if let t = truth[i] { #expect(ids[i] == t, "row \(i)") } else { #expect(ids[i] == built[i].id, "row \(i) keeps its own") }
        }
        // The one-pass pairing kept 2 of the newest turn's 11 rows shown.
        let before = Self.keepingIDs55(built, from: shown).map(\.id)
        #expect(built.indices.filter { $0 >= newest && truth[$0] != nil && before[$0] == truth[$0] }.count == 2)
    }

    @Test func aLongChatWithOtherCommandFormatsIsNeverWorse() {
        // Every live context formatted otherwise: nothing pairs by command, and the result is the one-pass pairing's.
        let all = Self.longChat(turns: 12, live: [3, 7, 8, 11], shifted: true, noteAfter: 5, format: { "$ " + $0 }, drops: [0])
        #expect(ChatSession.keepingIDs(all.built, from: all.shown).map(\.id) == Self.keepingIDs55(all.built, from: all.shown).map(\.id))
        // Some formatted otherwise and two calls left out: every pair the one-pass pairing got right stays right.
        let mixed = Self.longChat(turns: 12, live: [3, 7, 8, 11], shifted: true, noteAfter: 5,
                                 format: { ["free -h", "uptime", "nightly-export"].contains($0) ? "$ " + $0 : $0 }, drops: [0, 4])
        let before = Self.keepingIDs55(mixed.built, from: mixed.shown).map(\.id)
        let now = ChatSession.keepingIDs(mixed.built, from: mixed.shown).map(\.id)
        #expect(Set(now).count == now.count)
        for i in mixed.built.indices where mixed.truth[i] != nil && before[i] == mixed.truth[i] { #expect(now[i] == mixed.truth[i], "row \(i)") }
    }

    // MARK: 9. Many long chats, from a fixed seed

    /// 4 to 29 earlier turns and the newest, each running 3 to 9 of the checks; earlier turns watched live or loaded
    /// (one index off a quarter of the time), notes only this device shows, the newest turn as it streamed with up to two
    /// calls left out and its contexts formatted alike, all otherwise, or some otherwise.
    static func randomChat(_ g: inout Seeded) -> (built: [TranscriptItem], shown: [TranscriptItem], truth: [String?]) {
        let turns = Int.random(in: 4..<30, using: &g)
        let format = ["same", "same", "all", "some"].randomElement(using: &g)!
        let shifted = Double.random(in: 0..<1, using: &g) < 0.25
        var built: [TranscriptItem] = [], shown: [TranscriptItem] = [], truth: [String?] = []
        var index = 0
        func add(_ make: (String, String?, String?) -> TranscriptItem, turn: Int, key: String, isLive: Bool, isNewest: Bool,
                 context: String?, text: String?, left: Bool, g: inout Seeded) {
            let id = "h-\(index + 1)-\(index)"
            built.append(make(id, context, text))
            if !left {
                let shownID = isLive ? "live-\(turn)-\(key)" : shifted ? "h-\(index + 2)-\(index + 1)" : id
                var c = context, w = text
                if isNewest, let cc = c, format == "all" || (format == "some" && Bool.random(using: &g)) { c = "$ " + cc }
                if isNewest, let ww = w, Double.random(in: 0..<1, using: &g) < 0.1 { w = ww + " (live)" }
                shown.append(make(shownID, c, w))
                truth.append(shownID)
            } else {
                truth.append(nil)
            }
            index += 1
            if Double.random(in: 0..<1, using: &g) < 0.03 { shown.append(note("note-\(index)")) }
        }
        for t in 0...turns {
            let isNewest = t == turns
            let isLive = isNewest || Bool.random(using: &g)
            let stepCount = Int.random(in: 3...checks.count, using: &g)
            let steps = Array(checks.shuffled(using: &g).prefix(stepCount))
            let dropCount = [0, 1, 1, 2].randomElement(using: &g)!
            let drops: Set<Int> = isNewest ? Set((0..<steps.count).shuffled(using: &g).prefix(dropCount)) : []
            add({ id, _, _ in user(id, "check the host \(t % 3)") }, turn: t, key: "u", isLive: isLive, isNewest: isNewest,
                context: nil, text: nil, left: false, g: &g)
            for (k, step) in steps.enumerated() {
                add({ id, c, _ in tool(id, step.0, c) }, turn: t, key: "\(k)", isLive: isLive, isNewest: isNewest,
                    context: step.1, text: nil, left: drops.contains(k), g: &g)
                if Double.random(in: 0..<1, using: &g) < 0.3 {
                    add({ id, _, w in reply(id, w ?? "") }, turn: t, key: "w\(k)", isLive: isLive, isNewest: isNewest,
                        context: nil, text: "Words after step \(k).", left: false, g: &g)
                }
            }
            add({ id, _, _ in reply(id, "All checks done for run \(t).") }, turn: t, key: "a", isLive: isLive, isNewest: isNewest,
                context: nil, text: nil, left: false, g: &g)
        }
        return (built, shown, truth)
    }

    @Test func manyLongChatsNeverLoseARightPairOrShareAnID() {
        var g = Seeded(state: 0x5EED_0057)
        var lost: [String] = [], shared: [Int] = [], gained = 0
        for t in 0..<400 {
            let (built, shown, truth) = Self.randomChat(&g)
            let before = Self.keepingIDs55(built, from: shown).map(\.id)
            let now = ChatSession.keepingIDs(built, from: shown).map(\.id)
            if Set(now).count != now.count { shared.append(t) }
            for i in built.indices where truth[i] != nil {
                if before[i] == truth[i], now[i] != truth[i] { lost.append("chat \(t) row \(i)") }
                if before[i] != truth[i], now[i] == truth[i] { gained += 1 }
            }
        }
        #expect(lost.isEmpty, "right pairs lost: \(lost.prefix(5))")
        #expect(shared.isEmpty, "chats with a shared id: \(shared.prefix(5))")
        #expect(gained > 0)
    }
}
#endif
