import Foundation
import A2UISwiftCore
import VoryCore

// A card the bot drew in A2UI: a fenced ```a2ui block in its reply renders as native controls
// instead of as code. The block is A2UI v0.9 messages (one JSON value, a JSON array, or JSONL).
// Any bot can do it today; no gateway change is needed. A tapped action becomes a user turn:
// a sentence a person can read, then a fenced ```a2ui-action block the bot can parse. The card
// never answers an approval, a clarify, a sudo or a secret prompt — those stay on the chat's
// own cards. Pictures, video and audio load over https only.

/// The pure parts of the card, kept apart from the views so they can be tested.
enum A2UICard {
    enum Failure: Error, Equatable {
        case empty
        case notJSON
        case invalid
    }

    /// Whether a fenced block is a card: its language says a2ui.
    static func isCard(language: String?) -> Bool { languageTag(language) == "a2ui" }

    /// Whether a fenced block is the structured half of a reply to a card.
    static func isAction(language: String?) -> Bool { languageTag(language) == "a2ui-action" }

    private static func languageTag(_ language: String?) -> String? {
        language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The messages a card renders. Missing `version` becomes `v0.9`. A surface that updates
    /// before it is created gets a `createSurface` for the basic catalog. Any other catalog id
    /// is read as the basic catalog: a card can only draw what this app ships.
    static func messages(from text: String) throws -> [A2uiMessage] {
        var objects = try jsonObjects(from: text)
        objects = injectVersion(objects)
        objects = restrictMedia(objects)
        objects = synthesizeCreateSurface(objects)
        objects = mapCatalogs(objects)
        guard JSONSerialization.isValidJSONObject(objects),
              let data = try? JSONSerialization.data(withJSONObject: objects) else { throw Failure.notJSON }
        guard let decoded = try? JSONDecoder().decode([A2uiMessage].self, from: data), !decoded.isEmpty else { throw Failure.invalid }
        return decoded
    }

    /// The surface a card's actions name. The first one the messages declare.
    static func surfaceID(in messages: [A2uiMessage]) -> String {
        for message in messages {
            switch message {
            case .createSurface(let payload): return payload.surfaceId
            case .updateComponents(let payload): return payload.surfaceId
            case .updateDataModel(let payload): return payload.surfaceId
            case .deleteSurface(let payload): return payload.surfaceId
            }
        }
        return "main"
    }

    /// Surface ids declared by the closed a2ui fences in a reply.
    static func surfaceIDs(in text: String) -> Set<String> {
        var ids = Set<String>()
        for body in fenced(text, card: true) {
            if let messages = try? messages(from: body) {
                for message in messages {
                    switch message {
                    case .createSurface(let payload): ids.insert(payload.surfaceId)
                    case .updateComponents(let payload): ids.insert(payload.surfaceId)
                    case .updateDataModel(let payload): ids.insert(payload.surfaceId)
                    case .deleteSurface(let payload): ids.insert(payload.surfaceId)
                    }
                }
            }
        }
        return ids
    }

    /// Surface ids a person already answered, from later user turns.
    static func answeredSurfaceIDs(in items: [TranscriptItem]) -> Set<String> {
        var ids = Set<String>()
        for item in items {
            guard case .user(let text, _) = item.kind, text.contains("a2ui-action") else { continue }
            ids.formUnion(actionSurfaceIDs(in: text))
        }
        return ids
    }

    /// Surface ids named by the closed a2ui-action fences in a user turn.
    static func actionSurfaceIDs(in text: String) -> Set<String> {
        var ids = Set<String>()
        for body in fenced(text, card: false) {
            guard let data = body.data(using: .utf8),
                  let message = try? JSONDecoder().decode(A2uiClientMessage.self, from: data),
                  case .action(let action) = message else { continue }
            ids.insert(action.surfaceId)
        }
        return ids
    }

    /// What a user bubble shows for a turn that answered a card: the sentence, without the JSON.
    struct UserDisplay: Equatable {
        var prose: String
        var replied: Bool
    }

    static func userDisplay(_ text: String) -> UserDisplay {
        guard text.contains("a2ui-action") else { return UserDisplay(prose: text, replied: false) }
        let pattern = #"```[ \t]*a2ui-action[^\n]*\n[\s\S]*?\n```"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return UserDisplay(prose: text, replied: false) }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        guard stripped != text else { return UserDisplay(prose: text, replied: false) }
        return UserDisplay(prose: stripped.trimmingCharacters(in: .whitespacesAndNewlines), replied: true)
    }

    /// The user turn a tapped action sends: a sentence, then the action as JSON.
    static func replyText(action: ResolvedAction, surfaceId: String, at date: Date = Date()) -> String {
        let prose = proseLine(action)
        let message = A2uiClientMessage.action(A2uiClientAction(
            name: action.name,
            surfaceId: surfaceId,
            sourceComponentId: action.sourceComponentId,
            timestamp: ISO8601DateFormatter().string(from: date),
            context: action.context
        ))
        let json = (try? JSONEncoder().encode(message)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        \(prose)

        ```a2ui-action
        \(json)
        ```
        """
    }

    private static func proseLine(_ action: ResolvedAction) -> String {
        let details = action.context.keys.sorted().compactMap { key -> String? in
            guard let value = action.context[key] else { return nil }
            let text = plain(value)
            guard !text.isEmpty else { return nil }
            return "\(key) \(text)"
        }
        if details.isEmpty { return "Chose \"\(action.name)\" on the card." }
        return "Chose \"\(action.name)\" on the card: \(details.joined(separator: ", "))."
    }

    private static func plain(_ value: AnyCodable) -> String {
        switch value {
        case .string(let text): return text
        case .number(let number):
            if number.rounded() == number, number < Double(Int.max), number > Double(Int.min) { return String(Int(number)) }
            return String(number)
        case .bool(let flag): return flag ? "yes" : "no"
        case .null: return "nothing"
        case .array(let items): return items.map(plain).filter { !$0.isEmpty }.joined(separator: ", ")
        case .dictionary(let fields):
            return fields.keys.sorted().compactMap { key -> String? in
                guard let value = fields[key] else { return nil }
                let text = plain(value)
                guard !text.isEmpty else { return nil }
                return "\(key) \(text)"
            }.joined(separator: ", ")
        }
    }

    /// Closed fences of one kind. `card` picks a2ui; otherwise a2ui-action.
    private static func fenced(_ text: String, card: Bool) -> [String] {
        guard text.contains(card ? "a2ui" : "a2ui-action") else { return [] }
        var bodies: [String] = []
        for block in MarkdownParser.blocks(from: text) {
            guard case .code(let language, let body, true) = block else { continue }
            if card ? isCard(language: language) : isAction(language: language) { bodies.append(body) }
        }
        return bodies
    }

    // MARK: - JSON preparation

    private static let mediaComponents: Set<String> = ["Image", "Video", "AudioPlayer"]

    private static func jsonObjects(from text: String) throws -> [[String: Any]] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }
        if trimmed.hasPrefix("[") {
            guard let data = trimmed.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { throw Failure.notJSON }
            return try array.map { value in
                guard let object = value as? [String: Any] else { throw Failure.notJSON }
                return object
            }
        }
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return [object]
        }
        var lines: [[String: Any]] = []
        for line in trimmed.split(whereSeparator: \.isNewline) {
            let row = line.trimmingCharacters(in: .whitespaces)
            if row.isEmpty { continue }
            guard let data = row.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.notJSON }
            lines.append(object)
        }
        guard !lines.isEmpty else { throw Failure.empty }
        return lines
    }

    private static func injectVersion(_ objects: [[String: Any]]) -> [[String: Any]] {
        objects.map { object in
            guard object["version"] == nil else { return object }
            var copy = object
            copy["version"] = "v0.9"
            return copy
        }
    }

    /// A surface's first update creates it, on the basic catalog, when the model left that out.
    private static func synthesizeCreateSurface(_ objects: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        var out: [[String: Any]] = []
        for object in objects {
            if let body = object["createSurface"] as? [String: Any], let id = body["surfaceId"] as? String, !id.isEmpty {
                seen.insert(id)
                out.append(object)
                continue
            }
            if let id = surfaceID(in: object), !seen.contains(id),
               object["updateComponents"] != nil || object["updateDataModel"] != nil {
                out.append([
                    "version": "v0.9",
                    "createSurface": [
                        "surfaceId": id,
                        "catalogId": basicCatalogId,
                        "sendDataModel": false,
                    ] as [String: Any],
                ])
                seen.insert(id)
            }
            out.append(object)
        }
        return out
    }

    private static func mapCatalogs(_ objects: [[String: Any]]) -> [[String: Any]] {
        objects.map { object in
            guard var body = object["createSurface"] as? [String: Any] else { return object }
            if (body["catalogId"] as? String) != basicCatalogId { body["catalogId"] = basicCatalogId }
            var copy = object
            copy["createSurface"] = body
            return copy
        }
    }

    /// Image, video and audio URLs that are not https are blanked, including values a binding
    /// would pull out of the data model. A path with no scheme is left alone: it never loads.
    private static func restrictMedia(_ objects: [[String: Any]]) -> [[String: Any]] {
        var paths = Set<String>()
        var copy = objects
        for index in copy.indices {
            guard var update = copy[index]["updateComponents"] as? [String: Any],
                  var components = update["components"] as? [[String: Any]] else { continue }
            for componentIndex in components.indices {
                guard let name = components[componentIndex]["component"] as? String, mediaComponents.contains(name) else { continue }
                components[componentIndex]["url"] = sanitizedURL(components[componentIndex]["url"], paths: &paths)
            }
            update["components"] = components
            copy[index]["updateComponents"] = update
        }
        guard !paths.isEmpty else { return copy }
        for index in copy.indices {
            guard var update = copy[index]["updateDataModel"] as? [String: Any], let value = update["value"] else { continue }
            let base = normalizedPath((update["path"] as? String) ?? "/")
            update["value"] = sanitizedData(value, at: base, paths: paths)
            copy[index]["updateDataModel"] = update
        }
        return copy
    }

    private static func sanitizedURL(_ value: Any?, paths: inout Set<String>) -> Any {
        if let text = value as? String { return allowedMediaURL(text) ? text : "" }
        if let fields = value as? [String: Any], let path = fields["path"] as? String {
            paths.insert(normalizedPath(path))
            return fields
        }
        return value ?? ""
    }

    private static func sanitizedData(_ value: Any, at path: String, paths: Set<String>) -> Any {
        if let text = value as? String {
            return paths.contains(path) && !allowedMediaURL(text) ? "" : text
        }
        if let fields = value as? [String: Any] {
            var copy = fields
            for (key, child) in fields {
                let childPath = path == "/" ? "/\(key)" : "\(path)/\(key)"
                copy[key] = sanitizedData(child, at: childPath, paths: paths)
            }
            return copy
        }
        if let items = value as? [Any] {
            return items.enumerated().map { sanitizedData($0.element, at: "\(path)/\($0.offset)", paths: paths) }
        }
        return value
    }

    /// A URL with a scheme loads only over https. No scheme is not a remote load.
    private static func allowedMediaURL(_ text: String) -> Bool {
        guard let scheme = URL(string: text)?.scheme?.lowercased(), !scheme.isEmpty else { return true }
        return scheme == "https"
    }

    private static func normalizedPath(_ path: String) -> String {
        if path.isEmpty || path == "/" { return "/" }
        return path.hasPrefix("/") ? path : "/" + path
    }

    private static func surfaceID(in object: [String: Any]) -> String? {
        for key in ["createSurface", "updateComponents", "updateDataModel", "deleteSurface"] {
            if let body = object[key] as? [String: Any], let id = body["surfaceId"] as? String, !id.isEmpty { return id }
        }
        return nil
    }
}
