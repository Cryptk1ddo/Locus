import AppKit
import SwiftUI

/// Development probes follow Bench's existing test-only UI convention. This
/// does not expose a new production object/agent authority surface.
extension Bench {
    func wallCommand(_ request: [String: Any], browser: Browser, _ answer: @escaping ([String: Any]) -> Void) {
        guard Store.testing else { answer(["error": "wall only works on a --test run"]); return }
        let store = WorkspaceStore.shared(for: browser.spaceID)
        switch request["action"] as? String ?? "state" {
        case "canvasVaultMetrics":
            answer(CanvasVault.shared(workspace: store.file).monitoringDiagnostics); return
        case "canvasVault":
            let vault = CanvasVault.shared(workspace: store.file)
            if let path = request["path"] as? String { _ = vault.connect(URL(fileURLWithPath: path)) }
            if let autosave = request["autosave"] as? Bool { vault.setAutosave(autosave) }
            if request["disconnect"] as? Bool == true { vault.disconnect() }
            if request["bind"] as? Bool == true { vault.bindImportedFiles(store: store) }
            vault.refresh(); answer(["connected": vault.connected, "autosave": vault.autosave, "title": vault.title, "revision": vault.revision, "entries": vault.entries, "problem": vault.problem ?? ""]); return
        case "canvasFileFixture":
            guard let path = request["path"] as? String else { answer(["error": "Missing test file"]); return }
            _ = CanvasFiles.add([URL(fileURLWithPath: path)], to: store, at: CGPoint(x: 0, y: 0))
        case "canvasEdit":
            guard let surface = CanvasSurface.inView(browser.window?.contentView), let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)) else { answer(["error": "No Canvas or card"]); return }
            surface.edit(id)
        case "canvasEditorInfo":
            let editor = browser.window?.firstResponder as? NSTextView
            answer(["status": editor.flatMap { CanvasSurface.owning($0)?.fileEditorStatus } ?? "", "canUndo": editor?.undoManager?.canUndo ?? false, "canRedo": editor?.undoManager?.canRedo ?? false, "text": editor?.string ?? "", "editing": editor.map { CanvasSurface.owning($0) != nil } ?? false]); return
        case "canvasInsert":
            guard let editor = browser.window?.firstResponder as? NSTextView, CanvasSurface.owning(editor) != nil else { answer(["error": "Canvas editor is not focused"]); return }
            editor.insertText(request["text"] as? String ?? "", replacementRange: NSRange(location: NSNotFound, length: 0))
        case "canvasPerformance":
            guard let surface = CanvasSurface.inView(browser.window?.contentView), let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds) else { answer(["error": "No Canvas surface"]); return }
            let controller = surface.controller, original = controller.viewport
            let frames = min(120, max(10, request["frames"] as? Int ?? 60)), started = ProcessInfo.processInfo.systemUptime
            let beforeMemory = NativePerformance.footprint()
            var samples: [Double] = []
            surface.resetPerformanceCounters()
            func frame(_ index: Int) {
                guard index < frames else {
                    let counters = surface.performanceCounters
                    controller.viewport = original
                    let sorted = samples.sorted()
                    answer(["frames": frames, "elapsedMs": (ProcessInfo.processInfo.systemUptime - started) * 1000, "medianMs": sorted[sorted.count / 2], "p95Ms": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], "counters": counters, "footprintBefore": beforeMemory ?? 0, "footprintAfter": NativePerformance.footprint() ?? 0, "pixels": [bitmap.pixelsWide, bitmap.pixelsHigh]])
                    return
                }
                let began = ProcessInfo.processInfo.systemUptime
                controller.viewport = WallViewport(x: original.x + Double(index % 2) * 6, y: original.y, zoom: original.zoom)
                DispatchQueue.main.async {
                    surface.cacheDisplay(in: surface.bounds, to: bitmap)
                    samples.append((ProcessInfo.processInfo.systemUptime - began) * 1000)
                    DispatchQueue.main.async { frame(index + 1) }
                }
            }
            frame(0); return
        case "canvasState":
            guard let surface = CanvasSurface.inView(browser.window?.contentView) else { answer(["error": "No Canvas surface"]); return }
            let canvas = surface.controller
            answer(["selected": canvas.selected.map(\.uuidString), "selectedEdges": canvas.selectedEdges.map(\.uuidString), "viewport": ["x": canvas.viewport.x, "y": canvas.viewport.y, "zoom": canvas.viewport.zoom], "readOnly": canvas.readOnly, "canUndo": store.canUndo, "canRedo": store.canRedo, "frame": NSStringFromRect(surface.convert(surface.bounds, to: nil))]); return
        case "canvasOptions":
            guard let surface = CanvasSurface.inView(browser.window?.contentView) else { answer(["error": "No Canvas surface"]); return }
            if let readOnly = request["readOnly"] as? Bool { surface.controller.readOnly = readOnly; surface.controller.remember() }
        case "canvasContentInfo":
            guard let surface = CanvasSurface.inView(browser.window?.contentView), let window = browser.window else { answer(["error": "No Canvas surface"]); return }
            let rows = surface.subviews.compactMap { view -> [String: Any]? in
                guard let preview = view as? CanvasTextPreview, let storage = preview.text.textStorage, let layout = preview.text.layoutManager, let container = preview.text.textContainer else { return nil }
                var links: [[String: Any]] = []
                storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                    guard let url = value as? URL else { return }
                    let rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
                    let point = preview.text.convert(NSPoint(x: rect.midX + preview.text.textContainerInset.width, y: rect.midY + preview.text.textContainerInset.height), to: nil)
                    links.append(["url": url.absoluteString, "point": [point.x, window.frame.height - point.y]])
                }
                var attachments = 0, tables = 0
                storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in if value != nil { attachments += 1 } }
                storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in if let paragraph = value as? NSParagraphStyle, !paragraph.textBlocks.isEmpty { tables += 1 } }
                return ["object": preview.objectID?.uuidString ?? "", "text": storage.string, "links": links, "images": attachments, "tableCells": tables]
            }
            answer(["previews": rows]); return
        case "canvasImport":
            do { _ = try CanvasJSON.importData(Data((request["json"] as? String ?? "{}").utf8), into: store) } catch { answer(["error": error.localizedDescription]); return }
        case "canvasImportFolder":
            guard let path = request["path"] as? String else { answer(["error": "Folder path required"]); return }
            do {
                let result = try CanvasImport.portable(URL(fileURLWithPath: path), into: store)
                answer(["imported": result.selected.count, "granted": result.granted, "previews": result.previews, "unresolved": result.unresolved])
            } catch { answer(["error": error.localizedDescription]) }; return
        case "canvasExportFile":
            guard Store.testing, let path = request["path"] as? String, let format = (request["format"] as? String).flatMap(CanvasExport.Format.init(rawValue:)) else { answer(["error": "file export probes require a test profile"]); return }
            let selected: Set<UUID>? = request["selection"] as? Bool == true ? (CanvasSurface.inView(browser.window?.contentView)?.controller.expandedSelection() ?? []) : nil
            do {
                let url = URL(fileURLWithPath: path)
                if format == .portable { answer(["unresolved": try CanvasExport.portable(store.snapshot, store: store, selection: selected, to: url)]) }
                else { try (format == .json ? CanvasJSON.export(store.snapshot, selection: selected) : CanvasExport.overview(store.snapshot, store: store, selection: selected, format: format)).write(to: url, options: .atomic); answer(["exported": true]) }
            } catch { answer(["error": error.localizedDescription]) }
            return
        case "canvasExport":
            do { answer(["json": String(data: try CanvasJSON.export(store.snapshot), encoding: .utf8) ?? ""]); return } catch { answer(["error": error.localizedDescription]); return }
        case "canvasUndo": _ = store.undoCanvas()
        case "canvasRedo": _ = store.redoCanvas()
        case "dropLinks":
            guard let rows = request["links"] as? [[String: String]], let x = request["x"] as? Double,
                  let y = request["y"] as? Double else { answer(["error": "dropLinks needs links and canvas x/y"]); return }
            let delay = min(1, max(0, request["delay"] as? Double ?? 0))
            let providers = rows.map { row in
                let provider = NSItemProvider()
                provider.suggestedName = row["title"]
                provider.registerObject(ofClass: NSURL.self, visibility: .all) { complete in
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { complete(row["url"].flatMap(NSURL.init(string:)), nil) }
                    return Progress(totalUnitCount: 1)
                }
                return provider
            }
            let viewport = WallViewport.load(window: browser.record.id, space: browser.spaceID, settings: Store.settings)
            answer(["accepted": browser.dropWallLinks(providers, at: CGPoint(x: x, y: y), viewport: viewport, store: store)])
            return
        case "dragFixture":
            if request["close"] as? Bool == true { WallDragFixture.window?.close(); WallDragFixture.window = nil }
            else if let url = (request["url"] as? String).flatMap(URL.init(string:)) { WallDragFixture.show(browser: browser, store: store, url: url) }
        case "dragFixtureInfo":
            guard let window = WallDragFixture.window, let screen = NSScreen.screens.first else { answer(["error": "no drag fixture"]); return }
            let frame = window.frame
            answer(["screenFrame": [frame.minX, screen.frame.maxY - frame.maxY, frame.width, frame.height]])
            return
        case "recover": _ = store.recoverPrevious()
        case "previewAvailable":
            let object = (request["id"] as? String).flatMap(UUID.init(uuidString:)).flatMap { id in store.snapshot.objects.first { $0.id == id } }
            answer(["available": object.flatMap { WorkspaceImage.thumbnail($0, store: store) } != nil]); return
        case "search":
            browser.searchWallObjects()
            browser.typed = request["typed"] as? String ?? "wall: "
        case "submitSearch": browser.submit(aside: request["aside"] as? Bool ?? false)
        case "chooseSearch":
            if let index = request["index"] as? Int, browser.offers.indices.contains(index) { browser.take(browser.offers[index]) }
        case "reveal":
            if let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)),
               let space = (request["space"] as? String).flatMap(UUID.init(uuidString:)) { browser.revealWallObject(id, in: space) }
        case "place":
            if let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)) { store.place(id) }
        case "removePlacements":
            if let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)) {
                for p in store.snapshot.placements where p.objectID == id { store.removePlacement(p.id) }
            }
        case "deleteObject":
            if let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)) { store.deleteObject(id) }
        case "move":
            if let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)),
               let p = store.snapshot.placements.first(where: { $0.objectID == id }),
               let x = request["x"] as? Double, let y = request["y"] as? Double { store.move(p.id, x: x, y: y) }
        case "collectInspiration":
            if browser.wallPresented { browser.collectWallSource(delay: request["delay"] as? Double ?? 0) }
            else { browser.collectInspiration(delay: request["delay"] as? Double ?? 0) }
        case "inspirationLink":
            guard let url = (request["url"] as? String).flatMap(URL.init(string:)),
                  let object = InspirationSource.object(url: url, title: request["title"] as? String ?? "", text: request["text"] as? String ?? "")
            else { answer(["error": "inspirationLink needs HTTP(S) URL"]); return }
            _ = store.addInspiration(object, png: nil)
        case "openAIReadSource":
            if let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)),
               let object = store.snapshot.objects.first(where: { $0.id == id }) { browser.openAIReadSource(object) }
        case "saveAI":
            if let assistant = browser.assisting, let turn = assistant.turns.last { browser.saveAIAnswer(turn, assistant: assistant) }
        case "resize":
            if let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)),
               let p = store.snapshot.placements.first(where: { $0.objectID == id }),
               let width = request["width"] as? Double, let height = request["height"] as? Double { store.resize(p.id, width: width, height: height) }
        case "connect", "disconnect":
            if let source = (request["source"] as? String).flatMap(UUID.init(uuidString:)),
               let target = (request["target"] as? String).flatMap(UUID.init(uuidString:)), let kind = request["kind"] as? String {
                if request["action"] as? String == "connect" { _ = store.connect(source, to: target, kind: kind, label: request["label"] as? String ?? "") }
                else { _ = store.disconnect(source, from: target, kind: kind) }
            }
        case "viewport":
            if let x = request["x"] as? Double, let y = request["y"] as? Double, let zoom = request["zoom"] as? Double {
                let value = WallViewport(x: x, y: y, zoom: zoom)
                if value.valid, let surface = CanvasSurface.inView(browser.window?.contentView) { surface.controller.viewport = value }
                value.save(window: browser.record.id, space: browser.spaceID, settings: Store.settings)
            }
            let value = WallViewport.load(window: browser.record.id, space: browser.spaceID, settings: Store.settings)
            answer(["x": value.x, "y": value.y, "zoom": value.zoom]); return
        case "capture":
            if browser.wallPresented { browser.captureWallSource() } else { browser.startUICapture() }
        case "captureSelector":
            guard let selector = request["selector"] as? String else { answer(["error": "captureSelector needs selector"]); return }
            if browser.wallPresented { browser.captureWallSource(picking: false, selector: selector) }
            else { browser.startUICapture(picking: false, selector: selector) }
        case "cancelCapture": browser.uiCapture?.cancel()
        case "recapture":
            if let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)),
               let object = store.snapshot.objects.first(where: { $0.id == id }) { browser.recaptureUI(object) }
        case "sourcePage":
            if let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)),
               let object = store.snapshot.objects.first(where: { $0.id == id }),
               let source = browser.captureSourcePage(object) { browser.openWallPage(source) }
        case "canRecapture":
            let object = (request["id"] as? String).flatMap(UUID.init(uuidString:)).flatMap { id in store.snapshot.objects.first { $0.id == id } }
            answer(["available": object.map(browser.canRecaptureUI) ?? false]); return
        case "pageData":
            guard let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let object = store.snapshot.objects.first(where: { $0.id == id }),
                  let data = try? JSONEncoder().encode(object),
                  let value = try? JSONSerialization.jsonObject(with: data) else { answer(["error": "no object"]); return }
            answer(["object": value]); return
        case "updatePage":
            if let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)),
               let object = store.snapshot.objects.first(where: { $0.id == id }) { browser.updateWallPage(object) }
        case "captureData":
            guard let object = store.snapshot.objects.last(where: { $0.type == "uiCapture" }),
                  let data = try? JSONEncoder().encode(object),
                  let value = try? JSONSerialization.jsonObject(with: data) else { answer(["error": "no capture"]); return }
            answer(["object": value, "assetExists": object.snapshotID.map { FileManager.default.fileExists(atPath: store.assetURL($0).path) } ?? false])
            return
        case "open": browser.openWall()
        case "close": browser.closeWall()
        case "savePage":
            if browser.wallPresented { browser.saveWallSourcePage() } else { browser.savePageToWall() }
        case "note":
            store.add(LocusObject(type: "note", title: request["title"] as? String ?? "Note",
                                  content: ["text": .string(request["text"] as? String ?? "")]))
        case "openPage":
            if let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)),
               let object = store.snapshot.objects.first(where: { $0.id == id }) { browser.openWallPage(object, savedAddress: request["savedAddress"] as? Bool ?? false) }
        case "picture", "capturePicture", "evidencePicture", "connectionsPicture":
            guard let path = request["path"] as? String else { answer(["error": "wall picture needs path"]); return }
            let root: AnyView
            if request["action"] as? String == "capturePicture", let object = store.snapshot.objects.last(where: { $0.type == "uiCapture" }) {
                root = AnyView(UICaptureInspector(object: object, store: store, close: {}).frame(width: 1_000, height: 650).background(Palette.ground))
            } else if request["action"] as? String == "evidencePicture", let object = store.snapshot.objects.last(where: { ["inspiration", "aiOutput"].contains($0.type) }) {
                root = AnyView(WallEvidenceInspector(object: object, store: store, browser: browser, edit: {}, close: {}).frame(width: 1_000, height: 650).background(Palette.ground))
            } else if request["action"] as? String == "connectionsPicture", let id = (request["id"] as? String).flatMap(UUID.init(uuidString:)), let object = store.snapshot.objects.first(where: { $0.id == id }) {
                root = AnyView(WallConnections(object: object, store: store, close: {}).frame(width: 1_000, height: 650).background(Palette.ground))
            } else { root = AnyView(WallView(browser: browser, store: store).frame(width: 1_000, height: 650)) }
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 1_000, height: 650)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                defer { window.contentView = nil }
                guard let picture = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    answer(["error": "nothing drawn"]); return
                }
                host.cacheDisplay(in: host.bounds, to: picture)
                do {
                    try picture.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    answer(["saved": path])
                } catch { answer(["error": error.localizedDescription]) }
            }
            return
        default: break
        }
        answer(["collecting": browser.collectingInspiration, "canCollect": browser.canCollectInspiration,
                "wires": WallGraph.wires(in: store.snapshot).count,
                "placementData": store.snapshot.placements.map { ["id": $0.id.uuidString, "object": $0.objectID.uuidString, "x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height] as [String: Any] },
                "capturing": browser.capturingUI, "canCapture": browser.canCaptureUI, "showing": browser.wallPresented, "spaceID": browser.spaceID.uuidString,
                "revealID": browser.wallReveal?.uuidString ?? "", "typed": browser.typed,
                "completed": browser.completed, "picked": browser.picked ?? -1,
                "closedTabs": browser.ghosts.count,
                "bindings": browser.tabs.compactMap { tab -> [String: String]? in
                    guard let id = tab.wallObjectID(in: browser.spaceID) else { return nil }
                    return ["tab": tab.id.uuidString, "object": id.uuidString]
                },
                "editing": browser.editing, "ending": browser.ending ?? "",
                "offers": browser.offers.map { offer -> [String: String] in
                    var row = ["id": offer.id, "title": offer.key, "url": offer.url?.absoluteString ?? ""]
                    if case .object(let space, let id) = offer.kind { row["space"] = space.uuidString; row["object"] = id.uuidString }
                    return row
                },
                "objects": store.snapshot.objects.map { ["id": $0.id.uuidString, "type": $0.type, "title": $0.title] },
                "placements": store.snapshot.placements.count,
                "builtTabs": browser.tabs.filter { $0.built != nil }.map { $0.id.uuidString },
                "canSavePage": browser.canSavePageToWall,
                "sourceTab": browser.wallSourceTab.map(Bench.short) ?? "",
                "canCaptureSource": browser.canCaptureWallSource,
                "wallTabs": browser.tabs.filter(\.isWall).map(Bench.short),
                "announcement": browser.announcement ?? "",
                "writable": store.writable, "revision": store.snapshot.revision,
                "recoveryRevision": store.recovery?.revision ?? -1, "recoveryObjects": store.recovery?.objectCount ?? 0,
                "problem": store.problem ?? ""])
    }
}

/// Only reachable in SEARCH_PROBE. Supplies a visible native drag source for
/// desktop QA against the real Wall view, without touching a user's windows.
@MainActor private enum WallDragFixture {
    static var window: NSWindow?
    static func show(browser: Browser, store: WorkspaceStore, url: URL) {
        window?.close()
        let host = NSHostingView(rootView: VStack(spacing: 0) {
            HStack {
                Text("Drag reference onto Wall below").padding(12).contentShape(Rectangle())
                    .onDrag { NSItemProvider(object: url as NSURL) }
                Spacer()
            }.padding(.horizontal, 16).frame(height: 52).background(Palette.wash)
            WallView(browser: browser, store: store).frame(width: 1_000, height: 650)
        }.frame(width: 1_000, height: 702))
        let panel = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1_000, height: 702),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Locus · link drop QA"
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        window = panel
        panel.center(); panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
