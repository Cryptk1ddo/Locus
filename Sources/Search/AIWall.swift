import Foundation

/// Only the answer and its evidence summary are durable. No keys, page body or conversation history.
@MainActor enum AIWall {
    static func object(turn: Assistant.Turn, provider: String, model: String, title: String, url: URL, readAt: String, addressed: Bool, sourceTruncated: Bool = false) -> LocusObject? {
        guard turn.done, turn.checked, turn.failed == nil, !turn.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              turn.answer.count <= Assistant.longest, let url = SavedPageAddress.clean(url) else { return nil }
        let heading = turn.question.map { String($0.prefix(300)) } ?? "Summary · \(title)"
        return LocusObject(type: "aiOutput", title: heading, content: [
            "text": .string(turn.answer), "question": turn.question.map(ObjectValue.string) ?? .null,
            "provider": .string(provider), "model": .string(model), "url": .string(url.absoluteString),
            "sourceTitle": .string(title), "readAt": .string(readAt), "mayBeWrong": .bool(true),
            "addressedAI": .bool(addressed), "sourceTruncated": .bool(sourceTruncated), "answerLimited": .bool(turn.answerLimited), "strays": .array(turn.strays.map(ObjectValue.string))
        ])
    }
}

extension Browser {
    func openAIReadSource(_ expected: LocusObject) {
        let store = WorkspaceStore.shared(for: spaceID)
        guard let object = store.snapshot.objects.first(where: { $0.id == expected.id && $0.supported && $0.type == "aiOutput" }),
              let address = object.content["url"]?.text.flatMap(URL.init(string:)),
              let url = SavedPageAddress.clean(address), url == address else { return }
        // An explicitly updated page reference may now represent another URL.
        // The answer's immutable read URL remains the evidence to open.
        if let id = object.relationshipTarget("generatedFrom"),
           let page = store.snapshot.objects.first(where: { $0.id == id && $0.type == "page" && $0.supported && $0.url == url }) {
            openWallPage(page, savedAddress: true)
        } else { _ = open(url, foreground: true) }
    }

    func canSaveAIAnswer(_ turn: Assistant.Turn, assistant: Assistant) -> Bool {
        guard assisting === assistant, assistant.durable, assistant.space == spaceID, assistant.sourcePage != nil,
              turn.done, turn.checked, turn.failed == nil, !turn.answer.isEmpty,
              assistant.turns.contains(turn), let tab = tabs.first(where: { $0.id == assistant.tab }),
              !tab.shy, !tab.bench, tab.held == nil, tab.built?.configuration.websiteDataStore.isPersistent == true
        else { return false }
        return WorkspaceStore.shared(for: spaceID).writable
    }
    func saveAIAnswer(_ turn: Assistant.Turn, assistant: Assistant) {
        guard canSaveAIAnswer(turn, assistant: assistant), let source = assistant.sourcePage,
              let url = assistant.sourceURL, let title = assistant.sourceTitle, let readAt = assistant.readAt else { return }
        let store = WorkspaceStore.shared(for: spaceID)
        if let id = assistant.savedOutputs[turn.id] {
            if store.snapshot.objects.contains(where: { $0.id == id }) { _ = revealWallObject(id, in: spaceID) }
            else { announce("This saved answer was deleted. Ask again to create new evidence.") }
            return
        }
        guard let object = AIWall.object(turn: turn, provider: assistant.provider.rawValue, model: assistant.model,
                                        title: title, url: url, readAt: readAt, addressed: assistant.addressed, sourceTruncated: assistant.readWasCut) else { return }
        if store.addAIOutput(object, sourcePage: source) {
            assistant.savedOutputs[turn.id] = object.id
            _ = revealWallObject(object.id, in: spaceID)
            announce("AI answer and source saved to Wall")
        } else { announce(store.problem ?? "The source changed. Ask again before saving this answer.") }
    }
}
