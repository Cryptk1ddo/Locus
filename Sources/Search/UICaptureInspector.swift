import SwiftUI

/// Captured page content is displayed as text/data, never rendered as HTML.
struct UICaptureInspector: View {
    let object: LocusObject
    let store: WorkspaceStore
    let close: () -> Void
    @State private var preview: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(object.title).font(.system(size: 14, weight: .medium))
                Spacer()
                Button("Done", action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let preview {
                        Image(nsImage: preview).resizable().scaledToFit()
                            .frame(maxWidth: min(560, preview.size.width), maxHeight: min(240, preview.size.height))
                            .accessibilityLabel("Captured visible element crop")
                    } else if object.snapshotID != nil {
                        Text("Preview is missing or damaged. The captured metadata remains available.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    ForEach(object.content.keys.sorted(), id: \.self) { key in
                        if let value = object.content[key], key != "screenshotAllowed" {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(key).font(.system(size: 12, weight: .semibold))
                                Text(Self.formatted(value)).font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20).frame(width: 600, height: 560)
        .onAppear {
            if let image = WorkspaceImage.image(object, store: store) {
                if case .dictionary(let rect) = object.content["snapshotRect"],
                   case .number(let width) = rect["width"], case .number(let height) = rect["height"],
                   width.isFinite, height.isFinite, width > 0, height > 0 { image.size = NSSize(width: width, height: height) }
                preview = image
            }
        }
    }

    private static func formatted(_ value: ObjectValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else { return "Unavailable" }
        return string
    }
}
