import Foundation
import Testing
import A2UISwiftCore
@testable import Vory
@testable import VoryCore

/// A fenced a2ui block in a reply becomes a card; the parser's part of that.
@Suite struct A2UICardFenceTests {
    @Test func anA2UIFenceInsideOtherContentIsItsOwnClosedBlock() {
        let text = "Here it is:\n\n```a2ui\n{\"version\":\"v0.9\"}\n```\n\nSay the word."
        let blocks = MarkdownParser.blocks(from: text)
        #expect(blocks.count == 3)
        #expect(blocks[0] == .paragraph("Here it is:"))
        #expect(blocks[1] == .code(language: "a2ui", text: "{\"version\":\"v0.9\"}", closed: true))
        #expect(blocks[2] == .paragraph("Say the word."))
        #expect(A2UICard.isCard(language: "a2ui") && A2UICard.isCard(language: "A2UI "))
        #expect(!A2UICard.isCard(language: "html") && !A2UICard.isCard(language: nil) && !A2UICard.isAction(language: "a2ui"))
        #expect(A2UICard.isAction(language: "a2ui-action"))
    }

    @Test func anUnclosedFenceIsStillCodeAndNotYetACard() {
        let blocks = MarkdownParser.blocks(from: "Drawing:\n\n```a2ui\n{\"updateComponents\"")
        #expect(blocks.count == 2)
        #expect(blocks[1] == .code(language: "a2ui", text: "{\"updateComponents\"", closed: false))
    }
}

/// What a card accepts, and the turn a button sends back.
@Suite struct A2UICardMessageTests {
    private let textOnly = """
    {"updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Text","text":"Hi"}]}}
    """

    @Test func aSingleObjectGainsAVersionAndASurface() throws {
        let messages = try A2UICard.messages(from: textOnly)
        #expect(messages.count == 2)
        guard case .createSurface(let created) = messages[0] else { Issue.record("no surface"); return }
        #expect(created.surfaceId == "s")
        #expect(created.catalogId == basicCatalogId)
        guard case .updateComponents(let update) = messages[1] else { Issue.record("no components"); return }
        #expect(update.components.map(\.id) == ["root"])
        #expect(A2UICard.surfaceID(in: messages) == "s")
    }

    @Test func anArrayAndJSONLBothDecode() throws {
        let array = """
        [
          {"updateDataModel":{"surfaceId":"s","value":{"name":"Ada"}}},
          {"updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Text","text":{"path":"/name"}}]}}
        ]
        """
        let fromArray = try A2UICard.messages(from: array)
        #expect(fromArray.count == 3)
        guard case .createSurface = fromArray[0] else { Issue.record("array did not synthesize a surface"); return }

        let lines = """
        {"version":"v0.9.1","createSurface":{"surfaceId":"line","catalogId":"\(basicCatalogId)"}}
        {"updateComponents":{"surfaceId":"line","components":[{"id":"root","component":"Text","text":"From a line"}]}}
        """
        let fromLines = try A2UICard.messages(from: lines)
        #expect(fromLines.count == 2)
        guard case .createSurface(let created) = fromLines[0] else { Issue.record("jsonl surface"); return }
        #expect(created.surfaceId == "line" && created.catalogId == basicCatalogId)
    }

    @Test func anUnknownCatalogBecomesTheBasicCatalog() throws {
        let text = """
        {"version":"v0.9","createSurface":{"surfaceId":"s","catalogId":"https://example.com/custom"}}
        """
        let messages = try A2UICard.messages(from: text)
        guard case .createSurface(let created) = messages.first else { Issue.record("no surface"); return }
        #expect(created.catalogId == basicCatalogId)
    }

    @Test func mediaURLsThatAreNotHTTPSAreBlankedIncludingBindings() throws {
        let text = """
        [
          {"updateComponents":{"surfaceId":"s","components":[
            {"id":"root","component":"Column","children":["ok","bad","bound"]},
            {"id":"ok","component":"Image","url":"https://cdn.example/a.png"},
            {"id":"bad","component":"Video","url":"http://evil.example/a.mp4"},
            {"id":"bound","component":"AudioPlayer","url":{"path":"/clip"}}
          ]}},
          {"updateDataModel":{"surfaceId":"s","value":{"clip":"file:///tmp/a.mp3","note":"http://keep.example"}}}
        ]
        """
        let messages = try A2UICard.messages(from: text)
        let components = messages.compactMap { message -> [RawComponent]? in
            if case .updateComponents(let update) = message { return update.components }
            return nil
        }.flatMap { $0 }
        #expect(components.first { $0.id == "ok" }?.properties["url"] == .string("https://cdn.example/a.png"))
        #expect(components.first { $0.id == "bad" }?.properties["url"] == .string(""))
        guard case .updateDataModel(let data) = messages.last, case .dictionary(let fields) = data.value else {
            Issue.record("data model missing"); return
        }
        #expect(fields["clip"] == .string(""))
        #expect(fields["note"] == .string("http://keep.example"))
    }

    @Test func emptyAndBrokenBlocksFail() {
        #expect(throws: A2UICard.Failure.empty) { try A2UICard.messages(from: "  \n") }
        #expect(throws: A2UICard.Failure.self) { try A2UICard.messages(from: "not json") }
        #expect(throws: A2UICard.Failure.self) { try A2UICard.messages(from: "{\"version\":\"v0.9\"}") }
    }

    @Test func aReplyRoundTripsThroughTheParser() throws {
        let action = ResolvedAction(name: "book", sourceComponentId: "bookBtn", context: [
            "date": .string("Tuesday"),
            "guests": .number(2),
        ])
        let text = A2UICard.replyText(action: action, surfaceId: "s1", at: Date(timeIntervalSince1970: 0))
        #expect(text.hasPrefix("Chose \"book\" on the card: date Tuesday, guests 2."))
        let blocks = MarkdownParser.blocks(from: text)
        let fence = try #require(blocks.compactMap { block -> String? in
            if case .code(let language, let body, true) = block, A2UICard.isAction(language: language) { return body }
            return nil
        }.first)
        let message = try JSONDecoder().decode(A2uiClientMessage.self, from: Data(fence.utf8))
        guard case .action(let decoded) = message else { Issue.record("not an action"); return }
        #expect(decoded.name == "book")
        #expect(decoded.surfaceId == "s1")
        #expect(decoded.sourceComponentId == "bookBtn")
        #expect(decoded.context["date"] == .string("Tuesday"))
        #expect(decoded.context["guests"] == .number(2))
        #expect(A2UICard.actionSurfaceIDs(in: text) == ["s1"])

        let display = A2UICard.userDisplay(text)
        #expect(display.replied)
        #expect(display.prose == "Chose \"book\" on the card: date Tuesday, guests 2.")
        #expect(!display.prose.contains("a2ui-action"))
    }

    @Test func answeredSurfacesComeFromLaterUserTurns() throws {
        let reply = """
        Here:\n\n```a2ui\n\(textOnly)\n```\n
        """
        #expect(A2UICard.surfaceIDs(in: reply) == ["s"])
        let action = A2UICard.replyText(
            action: ResolvedAction(name: "book", sourceComponentId: "go", context: [:]),
            surfaceId: "s",
            at: Date(timeIntervalSince1970: 0)
        )
        let items = [
            TranscriptItem(id: "a", kind: .assistant(text: reply, reasoning: nil, streaming: false)),
            TranscriptItem(id: "u", kind: .user(text: action, attachments: [])),
        ]
        #expect(A2UICard.answeredSurfaceIDs(in: items) == ["s"])
        #expect(A2UICard.userDisplay("plain").replied == false)
    }
}
