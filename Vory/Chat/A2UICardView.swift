import SwiftUI
import A2UISwiftCore
import A2UISwiftUI

/// One surface's view model, kept for the thread's life so a form's answers survive the row
/// leaving the screen. Keyed by the transcript row and the block inside it.
@MainActor
final class A2UISurfaceCache {
    final class Entry {
        let source: String
        let model: SurfaceViewModel
        let surfaceID: String
        let sink = ActionSink()
        init(source: String, model: SurfaceViewModel, surfaceID: String) {
            self.source = source
            self.model = model
            self.surfaceID = surfaceID
        }
    }

    /// The button's action closure is `@Sendable` and the handler it calls is not, so the hop
    /// back to the main actor lives here. `answered` drops a second tap before the turn lands.
    final class ActionSink: @unchecked Sendable {
        var handler: (String) -> Void = { _ in }
        var answered = false
        func send(_ text: String) {
            if answered { return }
            answered = true
            let handler = handler
            DispatchQueue.main.async { handler(text) }
        }
    }

    private var entries: [String: Entry] = [:]

    func entry(key: String, source: String) -> Entry? {
        if let existing = entries[key], existing.source == source { return existing }
        guard let messages = try? A2UICard.messages(from: source) else {
            entries[key] = nil
            return nil
        }
        let model = SurfaceViewModel(catalog: basicCatalog)
        _ = model.processMessages(messages)
        // A theme on the surface would replace this; the card wears Vory's.
        model.a2uiStyle = Self.voryStyle()
        let created = Entry(source: source, model: model, surfaceID: A2UICard.surfaceID(in: messages))
        entries[key] = created
        return created
    }

    static func voryStyle() -> A2UIStyle {
        A2UIStyle(
            primaryColor: AppTheme.current,
            cardStyle: .init(cornerRadius: 12, shadowRadius: 0, shadowColor: .clear, shadowY: 0, backgroundColor: .clear)
        )
    }
}

/// The card in the thread: the surface, up to the same cap as an HTML card, with Full Screen
/// for the rest. A block that does not decode stays a code block with a note, never nothing.
struct A2UICardView: View {
    @Environment(\.windowGeometry) private var windowGeometry
    var source: String
    var cacheKey: String
    var cache: A2UISurfaceCache
    var answeredSurfaces: Set<String>
    var onAction: (String) -> Void
    var onShowSource: (() -> Void)?
    @State private var full = false
    @State private var sent = false

    var body: some View {
        if let entry = cache.entry(key: cacheKey, source: source) {
            card(entry)
        } else {
            unreadable
        }
    }

    private func card(_ entry: A2UISurfaceCache.Entry) -> some View {
        let answered = sent || entry.sink.answered || answeredSurfaces.contains(entry.surfaceID)
        let sink = entry.sink
        let surfaceID = entry.surfaceID
        entry.sink.handler = { text in
            sent = true
            onAction(text)
        }
        let cap = HTMLCard.heightCap(windowHeight: windowGeometry.bounds.height)
        return VStack(alignment: .leading, spacing: 0) {
            A2UISurfaceView(viewModel: entry.model, scrolls: false) { action in
                guard !sink.answered else { return }
                sink.send(A2UICard.replyText(action: action, surfaceId: surfaceID))
            }
            .disabled(answered)
            .frame(maxWidth: .infinity, maxHeight: cap, alignment: .top)
            .clipped()
            if answered {
                Text("Answered")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            Button { full = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.semibold))
                    .padding(6).background(.thinMaterial, in: .circle)
            }
            .buttonStyle(.plain).padding(6)
            .accessibilityLabel("Open the card full screen")
        }
        .accessibilityIdentifier("a2ui.card")
        .sheet(isPresented: $full) {
            A2UICardSheet(entry: entry, source: source, onShowSource: onShowSource).sheetFrame(.wide).withAppModel()
        }
    }

    private var unreadable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This card could not be read.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.top, 8)
            LongText(source, code: true).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
}

/// The card on its own, scrolling, with its source a toggle away.
struct A2UICardSheet: View {
    var entry: A2UISurfaceCache.Entry
    var source: String
    var onShowSource: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showingSource = false

    var body: some View {
        NavigationStack {
            Group {
                if showingSource {
                    ScrollView {
                        LongText(source, code: true).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                } else {
                    A2UISurfaceView(viewModel: entry.model, scrolls: true)
                }
            }
            .navigationTitle("Card")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingSource.toggle() } label: {
                            Label(showingSource ? "Show Card" : "Show Source", systemImage: showingSource ? "rectangle.on.rectangle" : "chevron.left.forwardslash.chevron.right")
                        }
                        if let onShowSource {
                            Button(action: onShowSource) { Label("Show Source in Chat", systemImage: "text.alignleft") }
                        }
                        Button { UIPasteboard.general.string = source } label: { Label("Copy JSON", systemImage: "doc.on.doc") }
                    } label: { Label("Card options", systemImage: "ellipsis.circle") }
                }
            }
        }
    }
}
