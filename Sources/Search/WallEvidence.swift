import SwiftUI

struct WallWires: View {
    let wires: [WallGraph.Wire]
    let viewport: CGRect
    var body: some View {
        Canvas { context, _ in
            for wire in wires {
                let a = CGRect(x: wire.from.x, y: wire.from.y, width: wire.from.width, height: wire.from.height)
                let b = CGRect(x: wire.to.x, y: wire.to.y, width: wire.to.width, height: wire.to.height)
                guard a.union(b).insetBy(dx: -100, dy: -100).intersects(viewport) else { continue }
                let forward = a.midX <= b.midX
                let start = CGPoint(x: forward ? a.maxX : a.minX, y: a.midY)
                let end = CGPoint(x: forward ? b.minX : b.maxX, y: b.midY)
                let reach = max(50, min(160, abs(end.x - start.x) / 2)), direction: CGFloat = forward ? 1 : -1
                var path = Path()
                path.move(to: start)
                path.addCurve(to: end, control1: CGPoint(x: start.x + direction * reach, y: start.y), control2: CGPoint(x: end.x - direction * reach, y: end.y))
                let provenance = ObjectRelationship.provenance.contains(wire.link.kind)
                context.stroke(path, with: .color(Palette.muted.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: provenance ? [4, 4] : []))
                var arrow = Path()
                arrow.move(to: CGPoint(x: end.x - direction * 7, y: end.y - 4)); arrow.addLine(to: end)
                arrow.addLine(to: CGPoint(x: end.x - direction * 7, y: end.y + 4))
                context.stroke(arrow, with: .color(Palette.muted.opacity(0.6)), lineWidth: 1)
                let label = wire.link.label.isEmpty ? ObjectRelationship.title(wire.link.kind) : wire.link.label
                let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 10)
                let labelWidth = CGFloat(min(40, label.count)) * 5.5
                let bounds = CGRect(x: middle.x - labelWidth / 2, y: middle.y - 7, width: labelWidth, height: 14)
                // Tight gaps show a wire; the connection sheet retains its full label.
                if !a.intersects(bounds), !b.intersects(bounds) {
                    context.draw(Text(verbatim: String(label.prefix(40))).font(.system(size: 10)).foregroundStyle(Palette.muted), at: middle)
                }
            }
        }
    }
}

struct WallConnections: View {
    let object: LocusObject
    @ObservedObject var store: WorkspaceStore
    let close: () -> Void
    @State private var target: UUID?
    @State private var kind = "relatedTo"
    @State private var label = ""
    @State private var query = ""
    @State private var notice: String?
    private var candidates: [LocusObject] { WallConnectionTargets.matching(store.snapshot.objects, excluding: object.id, query: query) }
    private var selected: LocusObject? { store.snapshot.objects.first { $0.id == target && $0.id != object.id && $0.supported } }
    private var current: LocusObject? { store.snapshot.objects.first { $0.id == object.id } }
    private var existing: [(String, UUID, ObjectRelationship)] {
        store.snapshot.objects.flatMap { source in
            source.relationships.filter { ObjectRelationship.known.contains($0.kind) && (source.id == object.id || $0.target == object.id) }
                .map { (source.title, source.id, $0) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connections · \(current?.title ?? object.title)").font(.system(size: 15, weight: .medium)).lineLimit(2)
            TextField("Find an object by title or type", text: $query).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Find connection target")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if candidates.isEmpty { Text("No matching objects in this Space.").font(.system(size: 12)).foregroundStyle(Palette.muted).padding(8) }
                    ForEach(candidates) { candidate in
                        Button { target = candidate.id; notice = nil } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: candidate.title).lineLimit(1)
                                    Text(candidate.kindTitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                if target == candidate.id { Image(systemName: "checkmark") }
                            }.padding(8).contentShape(Rectangle())
                                .background(target == candidate.id ? Palette.wash : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain).accessibilityLabel("Connect to \(candidate.title), \(candidate.kindTitle)")
                    }
                }
            }.frame(height: 140)
            Text(verbatim: selected.map { "To: " + $0.title } ?? "Choose an object above.")
                .font(.system(size: 12)).lineLimit(2).foregroundStyle(Palette.muted)
            Picker("Relationship", selection: $kind) {
                ForEach(ObjectRelationship.editable, id: \.self) { Text(ObjectRelationship.title($0)).tag($0) }
            }
            TextField("Optional label", text: $label)
            HStack {
                Text("Links stay with the objects when cards are removed.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Connect") {
                    guard let target else { return }
                    if store.connect(object.id, to: target, kind: kind, label: label) { notice = nil; label = "" }
                    else { notice = store.problem ?? "This connection already exists." }
                }.disabled(selected == nil || current == nil || !store.writable)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if existing.isEmpty { Text("No connections yet.").foregroundStyle(Palette.muted) }
                    ForEach(Array(existing.enumerated()), id: \.offset) { _, row in
                        let destination = store.snapshot.objects.first { $0.id == row.2.target }?.title ?? "Unavailable"
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: "\(row.0) → \(destination)").font(.system(size: 12, weight: .medium))
                                Text(verbatim: ObjectRelationship.title(row.2.kind) + (row.2.label.isEmpty ? "" : " · " + row.2.label)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            if ObjectRelationship.editable.contains(row.2.kind) {
                                Button("Disconnect") { _ = store.disconnect(row.1, from: row.2.target, kind: row.2.kind) }.disabled(!store.writable)
                            } else { Text("Source").font(.system(size: 11)).foregroundStyle(Palette.faint) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 150)
            if let message = notice ?? store.problem { Text(message).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            HStack { Spacer(); Button("Done", action: close).keyboardShortcut(.cancelAction) }
        }.padding(20).frame(width: 550).foregroundStyle(Palette.ink).background(Palette.ground)
    }
}

struct InspirationLinkEditor: View {
    @ObservedObject var store: WorkspaceStore
    var point: CGPoint? = nil
    let close: () -> Void
    @State private var address = ""
    @State private var title = ""
    @State private var note = ""
    @State private var notice: String?
    @FocusState private var addressFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save inspiration link").font(.system(size: 15, weight: .medium))
            TextField("https://…", text: $address).textFieldStyle(.roundedBorder).focused($addressFocused)
                .accessibilityLabel("Inspiration address")
            TextField("Title (optional)", text: $title).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Inspiration title")
            Text("Note (optional)").font(.system(size: 12)).foregroundStyle(Palette.muted)
            TextEditor(text: $note).font(.system(size: 13)).frame(height: 150)
                .accessibilityLabel("Inspiration note")
            Text("Saves a reference without loading the link. Visit it and collect the page to save a visual preview. A board link saves the board reference.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            if let message = notice ?? store.problem { Text(message).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
                          let object = InspirationSource.object(url: url, title: title, text: note) else { notice = "Enter a valid HTTP or HTTPS address."; return }
                    if store.addInspiration(object, png: nil, at: point) { close() }
                }.disabled(!store.writable).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 470).foregroundStyle(Palette.ink).background(Palette.ground)
            .onAppear { addressFocused = true }
    }
}

struct WallEvidenceInspector: View {
    let object: LocusObject
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var browser: Browser
    let edit: () -> Void
    let close: () -> Void
    private var source: LocusObject? {
        guard let id = object.relationshipTarget(object.type == "aiOutput" ? "generatedFrom" : "collectedFrom") else { return nil }
        return store.snapshot.objects.first { $0.id == id && $0.type == "page" && $0.supported }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(object.title).font(.system(size: 15, weight: .medium)).lineLimit(2)
                Spacer()
                Button("Done", action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let image = WorkspaceImage.thumbnail(object, store: store) {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if object.snapshotID != nil {
                        Text("Preview is missing or damaged. The saved text and source remain available.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    if object.type == "aiOutput" {
                        Text("AI · may be wrong · \(object.content["provider"]?.text ?? "") · \(object.content["model"]?.text ?? "")")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        if object.content["addressedAI"] == .bool(true) { Text("The source page contained instructions addressed to AI; the answer may have been steered.").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                        if case .array(let values) = object.content["strays"], !values.isEmpty {
                            Text(verbatim: "Not on the page: " + values.compactMap(\.text).joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        if object.content["sourceTruncated"] == .bool(true) { Text("Only part of the long source page was read.").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                        if object.content["answerLimited"] == .bool(true) { Text("The answer reached the length limit.").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                        Text(verbatim: object.text).font(.system(size: 13)).textSelection(.enabled)
                        Text(verbatim: "Read: " + (object.content["readAt"]?.text ?? "") + " · " + (object.content["sourceTitle"]?.text ?? ""))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    } else {
                        Text("\(InspirationSource(rawValue: object.content["provider"]?.text ?? "web")?.title ?? "Web") · \(object.content["resourceKind"]?.text ?? "page")").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        if let description = object.content["description"]?.text, !description.isEmpty { Text(verbatim: description).font(.system(size: 13)).textSelection(.enabled) }
                        if !object.text.isEmpty { Text(verbatim: object.text).font(.system(size: 13)).textSelection(.enabled) }
                        if case .dictionary(let screenshot) = object.content["screenshot"] { Text(verbatim: screenshot["reason"]?.text ?? "").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                    }
                    Text(verbatim: object.content["url"]?.text ?? "").font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 250, maxHeight: 480)
            HStack {
                if object.type == "inspiration" {
                    Button("Edit Note", action: edit).disabled(!store.writable || !store.snapshot.objects.contains(object))
                    Button("Open Source") { browser.openWallPage(object); close() }
                } else {
                    Button("Open Read Source") { browser.openAIReadSource(object); close() }
                        .help("Open the address this answer actually read")
                        .disabled(!store.snapshot.objects.contains(where: { $0.id == object.id && $0.supported && $0.type == "aiOutput" }))
                }
                if let source { Button("Show Source on Wall") { _ = browser.revealWallObject(source.id, in: store.snapshot.spaceID); close() } }
                Spacer()
            }
        }.padding(20).frame(width: 600).foregroundStyle(Palette.ink).background(Palette.ground)
    }
}
