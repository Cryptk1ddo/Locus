import AppKit

enum CanvasTable {
    struct Row { let table: NSTextTable; let index: Int; let cells: [String]; let alignment: [NSTextAlignment] }
    struct Layout { var rows: [Int: Row] = [:]; var separators: Set<Int> = [] }
    static func cells(_ line: String) -> [String]? {
        guard line.contains("|") else { return nil }
        var pieces: [String] = [], current = "", escaped = false, ticks = 0
        for character in line.trimmingCharacters(in: .whitespaces) {
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\" { current.append(character); escaped = true; continue }
            if character == "`" { ticks ^= 1; current.append(character); continue }
            if character == "|", ticks == 0 { pieces.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
            else { current.append(character) }
        }
        pieces.append(current.trimmingCharacters(in: .whitespaces))
        if pieces.first == "" { pieces.removeFirst() }; if pieces.last == "" { pieces.removeLast() }
        return pieces.count >= 1 && pieces.count <= 12 ? pieces : nil
    }
    static func layout(_ lines: [String]) -> Layout {
        var result = Layout(), index = 0, fence: String?
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { let marker = String(trimmed.prefix(3)); if fence == marker { fence = nil } else if fence == nil { fence = marker }; index += 1; continue }
            guard fence == nil, index + 1 < lines.count, let header = cells(lines[index]), let delimiter = cells(lines[index + 1]), header.count == delimiter.count,
                  delimiter.allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) else { index += 1; continue }
            let alignment: [NSTextAlignment] = delimiter.map { $0.hasPrefix(":") && $0.hasSuffix(":") ? .center : $0.hasSuffix(":") ? .right : .left }
            let table = NSTextTable(); table.numberOfColumns = header.count; table.layoutAlgorithm = .fixedLayoutAlgorithm
            table.setValue(100, type: .percentage, for: .width)
            result.rows[index] = Row(table: table, index: 0, cells: header, alignment: alignment); result.separators.insert(index + 1)
            index += 2; var row = 1
            while index < lines.count, row <= 100, let values = cells(lines[index]), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                result.rows[index] = Row(table: table, index: row, cells: Array((values + Array(repeating: "", count: header.count)).prefix(header.count)), alignment: alignment)
                index += 1; row += 1
            }
        }
        return result
    }
    static func render(_ row: Row) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (column, cell) in row.cells.enumerated() {
            let value = NSMutableAttributedString(attributedString: CanvasMarkdown.render(cell))
            if value.length == 0 { value.append(NSAttributedString(string: "\n")) }
            // A table is source text, rather than a task-list editing surface.
            var tasks: [NSRange] = []
            value.enumerateAttribute(.link, in: NSRange(location: 0, length: value.length)) { url, range, _ in if (url as? URL)?.scheme == "locus-task" { tasks.append(range) } }
            for range in tasks { value.removeAttribute(.link, range: range) }
            let block = NSTextTableBlock(table: row.table, startingRow: row.index, rowSpan: 1, startingColumn: column, columnSpan: 1)
            block.setValue(CGFloat(100) / CGFloat(row.cells.count), type: .percentage, for: .width)
            block.setWidth(6, type: .absolute, for: .padding); block.setWidth(0.5, type: .absolute, for: .border)
            block.setBorderColor(Palette.NS.faint); block.backgroundColor = row.index == 0 ? Palette.NS.wash : Palette.NS.ground
            let paragraph = NSMutableParagraphStyle(); paragraph.textBlocks = [block]; paragraph.alignment = row.alignment[column]; paragraph.paragraphSpacing = 3
            value.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: value.length))
            if row.index == 0 { value.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .semibold), range: NSRange(location: 0, length: value.length)) }
            output.append(value)
        }
        return output
    }
}
