import SwiftUI
import AppKit

@MainActor
public final class SpreadsheetUIState: ObservableObject {
    public struct InspectedCell: Identifiable {
        public let id = UUID()
        public let rowIndex: Int
        public let columnPath: String
        public let value: BSONValue
    }

    @Published public var inspectedCellPopover: InspectedCell?
    public init() {}
}

public struct SpreadsheetTableView: View {
    @ObservedObject public var tab: CollectionTabState
    @ObservedObject public var workspace: WorkspaceViewModel

    @StateObject private var uiState = SpreadsheetUIState()

    private let gutterWidth: CGFloat = 44
    private let rowHeight: CGFloat = 34
    private let headerHeight: CGFloat = 36

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return f
    }()

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 8
        f.usesGroupingSeparator = true
        return f
    }()

    public init(tab: CollectionTabState, workspace: WorkspaceViewModel) {
        self.tab = tab
        self.workspace = workspace
    }

    public var body: some View {
        let columns = tab.tableColumns

        if tab.documents.isEmpty && !tab.isLoading {
            emptyResultsView
        } else {
            GeometryReader { geo in
                let totalColsWidth = columns.reduce(CGFloat(0)) { $0 + columnWidth(for: $1) }
                let contentWidth = gutterWidth + totalColsWidth
                let fillerWidth = max(0, geo.size.width - contentWidth)

                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(tab.documents.enumerated()), id: \.offset) { rowIdx, doc in
                                VStack(alignment: .leading, spacing: 0) {
                                    tableRowView(
                                        rowIndex: rowIdx,
                                        document: doc,
                                        columns: columns,
                                        fillerWidth: fillerWidth
                                    )

                                    if tab.expandedRowIndices.contains(rowIdx) {
                                        inlineExpandedRowTree(
                                            rowIndex: rowIdx,
                                            document: doc,
                                            totalWidth: max(geo.size.width, contentWidth)
                                        )
                                    }
                                }
                            }
                        } header: {
                            tableHeaderView(columns: columns, fillerWidth: fillerWidth)
                        }
                    }
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                }
                .id(tab.resultRevision)
                .background(Color(nsColor: .textBackgroundColor))
            }
            .popover(item: $uiState.inspectedCellPopover) { item in
                NestedValuePopoverView(
                    path: item.columnPath,
                    value: item.value,
                    onEditFullDocument: {
                        guard canSwitchSelectedRow(to: item.rowIndex) else { return }
                        uiState.inspectedCellPopover = nil
                        tab.selectRow(item.rowIndex, openEditor: true)
                    }
                )
            }
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 64, height: 64)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Text("No documents matched your query")
                .font(.system(size: 14.5, weight: .semibold))
            Text("Update the filter in the query bar above and press Return or ⌘Return.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            if tab.queryText != "db.getCollection(\"\(tab.collection)\").find({})" {
                Button("Reset to Default Query") {
                    tab.queryText = "db.getCollection(\"\(tab.collection)\").find({})"
                    tab.pageSkip = 0
                    Task { await workspace.runQuery(for: tab) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Sticky Header Bar
    private func tableHeaderView(columns: [TableColumnDescriptor], fillerWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Left Gutter Header (#)
            HStack(spacing: 0) {
                Text("#")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: gutterWidth, height: headerHeight)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 1)
            }

            // Column Headers
            ForEach(columns) { col in
                let width = columnWidth(for: col)
                let isChildColumn = (col.parentPath != nil)
                let isSorted = (tab.sortColumnPath == col.path)

                HStack(spacing: 6) {
                    // Type Icon
                    columnTypeIcon(for: col)

                    // Column Name (clickable to sort)
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            tab.toggleSort(forColumn: col.path)
                        }
                    } label: {
                        HStack(spacing: 2) {
                            if let prefix = col.parentPrefix {
                                Text(prefix)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Color.purple.opacity(0.75))
                                    .lineLimit(1)
                            }
                            Text(col.leafName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isChildColumn ? Color.purple : Color.primary)
                                .lineLimit(1)

                            if isSorted {
                                Image(systemName: tab.sortAscending ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.leading, 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Click to sort by \(col.path)")

                    Spacer(minLength: 4)

                    // Expand / Collapse Nested Object Columns Pill
                    if col.isExpandableObject {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                tab.toggleColumnExpansion(col.path)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: col.isExpanded ? "minus" : "plus")
                                    .font(.system(size: 8.5, weight: .bold))
                                if !col.isExpanded && col.subFieldCount > 0 {
                                    Text("\(col.subFieldCount)")
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule()
                                    .fill(col.isExpanded ? Color.purple : Color.purple.opacity(0.15))
                            )
                            .foregroundStyle(col.isExpanded ? Color.white : Color.purple)
                        }
                        .buttonStyle(.plain)
                        .help(col.isExpanded ? "Collapse \(col.path) sub-columns" : "Expand \(col.subFieldCount) nested fields into columns")
                    }
                }
                .padding(.horizontal, 10)
                .frame(width: width, height: headerHeight)
                .background(
                    ZStack(alignment: .top) {
                        if isChildColumn {
                            Color.purple.opacity(0.06)
                            Rectangle()
                                .fill(Color.purple.opacity(0.65))
                                .frame(height: 2)
                        } else if col.isExpanded {
                            Color.purple.opacity(0.04)
                            Rectangle()
                                .fill(Color.purple)
                                .frame(height: 2)
                        } else {
                            Color(nsColor: .windowBackgroundColor)
                        }
                    }
                )
                .overlay(alignment: .trailing) {
                    ColumnResizeHandle(
                        currentWidth: width,
                        onResize: { newWidth in
                            var tx = Transaction()
                            tx.disablesAnimations = true
                            withTransaction(tx) {
                                tab.columnWidths[col.path] = max(90, min(800, newWidth))
                            }
                        },
                        onAutoFit: {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                tab.autoFitColumnWidth(for: col.path)
                            }
                        }
                    )
                }
            }

            // Right Filler Header so header always spans 100% width
            if fillerWidth > 0 {
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: fillerWidth, height: headerHeight)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func columnTypeIcon(for col: TableColumnDescriptor) -> some View {
        if col.path == "_id" || col.dominantType == "ObjectId" {
            Image(systemName: "key.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 0.92, green: 0.56, blue: 0.18))
        } else if col.isExpandableObject || col.dominantType == "Object" {
            Image(systemName: "curlybraces")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.purple)
        } else if col.dominantType == "Array" {
            Image(systemName: "brackets")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.orange)
        } else if ["Int32", "Int64", "Double", "Decimal128"].contains(col.dominantType) {
            Image(systemName: "number")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(red: 0.25, green: 0.58, blue: 0.96))
        } else if col.dominantType == "Boolean" {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 0.20, green: 0.75, blue: 0.50))
        } else if col.dominantType == "Date" || col.dominantType == "Timestamp" {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.70, blue: 0.74))
        } else {
            Image(systemName: "text.alignleft")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Row
    private func tableRowView(
        rowIndex: Int,
        document: BSONDocument,
        columns: [TableColumnDescriptor],
        fillerWidth: CGFloat
    ) -> some View {
        let isSelected = (tab.selectedRowIndex == rowIndex)

        let rowBackground: Color = {
            if isSelected {
                return Color.accentColor.opacity(0.16)
            }
            return rowIndex.isMultiple(of: 2)
                ? Color(nsColor: .textBackgroundColor)
                : Color.primary.opacity(0.022)
        }()

        return HStack(spacing: 0) {
            // Left Gutter Cell: Selection Bar + Row Number
            HStack(spacing: 0) {
                Text("\(tab.pageSkip + rowIndex + 1)")
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: gutterWidth, height: rowHeight)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                }
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
            }

            // Data Cells
            ForEach(columns) { col in
                let width = columnWidth(for: col)
                let val = document.value(atPath: col.path)
                cellView(rowIndex: rowIndex, column: col, value: val, width: width)
            }

            // Right Filler Cell
            if fillerWidth > 0 {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: fillerWidth, height: rowHeight)
            }
        }
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard canSwitchSelectedRow(to: rowIndex) else { return }
                tab.selectRow(rowIndex, openEditor: true)
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                guard canSwitchSelectedRow(to: rowIndex) else { return }
                tab.selectRow(rowIndex, openEditor: tab.isInspectorVisible)
            }
        )
    }

    private func canSwitchSelectedRow(to targetRowIndex: Int) -> Bool {
        guard tab.isInspectorVisible,
              tab.hasUnsavedEditorChanges,
              (tab.selectedRowIndex != targetRowIndex || tab.isCreatingNewDocument) else {
            return true
        }
        return workspace.confirmDiscardUnsavedChangesIfNeeded(in: tab)
    }

    // MARK: - Individual Cell Renderer
    @ViewBuilder
    private func cellView(
        rowIndex: Int,
        column: TableColumnDescriptor,
        value: BSONValue?,
        width: CGFloat
    ) -> some View {
        let isNumeric: Bool = {
            guard let v = value else { return false }
            switch v {
            case .int32, .int64, .double, .decimal128: return true
            default: return false
            }
        }()

        HStack(spacing: 6) {
            if isNumeric {
                Spacer(minLength: 0)
            }

            if let value = value {
                switch value {
                case .objectId(let oid):
                    HStack(spacing: 5) {
                        Text("OID")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(Color(red: 0.92, green: 0.56, blue: 0.18).opacity(0.16))
                            .foregroundStyle(Color(red: 0.92, green: 0.56, blue: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 3.5))

                        Text(oid.hexString)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.88))
                            .lineLimit(1)
                    }

                case .string(let str):
                    if str.isEmpty {
                        Text("\"\"")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    } else if str.contains("@") && !str.contains(" ") {
                        Text(str)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color(red: 0.22, green: 0.60, blue: 0.95))
                            .lineLimit(1)
                    } else {
                        Text(str)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                    }

                case .int32(let i):
                    Text("\(i)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.25, green: 0.58, blue: 0.96))
                        .lineLimit(1)

                case .int64(let i):
                    Text("\(i)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.25, green: 0.58, blue: 0.96))
                        .lineLimit(1)

                case .double(let d):
                    let formatted: String = {
                        if d.isNaN { return "NaN" }
                        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
                        return Self.numberFormatter.string(from: NSNumber(value: d)) ?? String(d)
                    }()
                    Text(formatted)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.25, green: 0.58, blue: 0.96))
                        .lineLimit(1)
                        .help(String(d))

                case .decimal128(let decData):
                    let decStr = BSONDecimal128.decodeToString(decData)
                    Text(decStr)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.25, green: 0.58, blue: 0.96))
                        .lineLimit(1)
                        .help(decStr)

                case .bool(let b):
                    HStack(spacing: 4.5) {
                        Circle()
                            .fill(b ? Color(red: 0.16, green: 0.78, blue: 0.50) : Color.secondary.opacity(0.6))
                            .frame(width: 5.5, height: 5.5)
                        Text(b ? "true" : "false")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(b ? Color(red: 0.16, green: 0.78, blue: 0.50).opacity(0.14) : Color.secondary.opacity(0.12))
                    )
                    .foregroundStyle(b ? Color(red: 0.16, green: 0.78, blue: 0.50) : Color.secondary)

                case .dateTime(let date):
                    Text(Self.displayDateFormatter.string(from: date))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Color(red: 0.18, green: 0.70, blue: 0.74))
                        .lineLimit(1)
                        .help(BSONValue.formatISODate(date))

                case .null:
                    Text("NULL")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.secondary.opacity(0.10))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5))

                case .undefined:
                    Text("UNDEFINED")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.orange.opacity(0.10))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5))

                case .document(let subDoc):
                    HStack(spacing: 4) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                tab.toggleColumnExpansion(column.path)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: column.isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(Color.purple)

                                Text(objectPreviewSummary(subDoc))
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Color.primary.opacity(0.85))
                                    .lineLimit(1)

                                Text("\(subDoc.count)")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4.5)
                                    .padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.18))
                                    .foregroundStyle(Color.purple)
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.purple.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.purple.opacity(0.22), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Click to expand nested columns for \(column.path)")

                        Button {
                            uiState.inspectedCellPopover = SpreadsheetUIState.InspectedCell(
                                rowIndex: rowIndex,
                                columnPath: column.path,
                                value: value
                            )
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .help("Pop out nested object inspector")
                    }

                case .array(let arr):
                    Button {
                        uiState.inspectedCellPopover = SpreadsheetUIState.InspectedCell(
                            rowIndex: rowIndex,
                            columnPath: column.path,
                            value: value
                        )
                    } label: {
                        HStack(spacing: 5) {
                            Text(arrayPreviewSummary(arr))
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Color.primary.opacity(0.85))
                                .lineLimit(1)

                            Text("\(arr.count)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.20))
                                .foregroundStyle(Color.orange)
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.orange.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.orange.opacity(0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Click to inspect \(arr.count) array elements")

                default:
                    Text(value.displayCellText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(EarlgreyTheme.bsonValueColor(value))
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }

            if !isNumeric {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: rowHeight)
        .background(column.parentPath != nil ? Color.purple.opacity(0.02) : Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)
        }
        .contextMenu {
            Button {
                guard canSwitchSelectedRow(to: rowIndex) else { return }
                tab.selectRow(rowIndex, openEditor: true)
            } label: {
                Label("View / Edit Document…", systemImage: "square.and.pencil")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.14)) {
                    tab.toggleRowExpansion(rowIndex)
                }
            } label: {
                Label(
                    tab.expandedRowIndices.contains(rowIndex) ? "Collapse Row Tree" : "Expand Row Tree Inline",
                    systemImage: "list.bullet.indent"
                )
            }

            if let value = value {
                Divider()

                Button {
                    applyQuickFilter(path: column.path, value: value)
                } label: {
                    Label("Filter by \(column.path) == \(value.displayCellText)", systemImage: "line.3.horizontal.decrease.circle")
                }

                if case .document = value {
                    Button {
                        tab.toggleColumnExpansion(column.path)
                    } label: {
                        Label(
                            column.isExpanded ? "Collapse Nested Columns" : "Expand Nested Columns",
                            systemImage: "rectangle.split.3x1"
                        )
                    }
                }

                Divider()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value.displayCellText, forType: .string)
                } label: {
                    Label("Copy Cell Value", systemImage: "doc.on.doc")
                }
            }

            Button {
                let json = BSONShellFormatter.format(tab.documents[rowIndex])
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(json, forType: .string)
            } label: {
                Label("Copy Document JSON", systemImage: "curlybraces")
            }
        }
    }

    // MARK: - Inline Expanded Row Tree Drawer
    private func inlineExpandedRowTree(rowIndex: Int, document: BSONDocument, totalWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    "Document #\(tab.pageSkip + rowIndex + 1) — Nested Field Breakdown",
                    systemImage: "list.bullet.indent"
                )
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    let json = BSONShellFormatter.format(document)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(json, forType: .string)
                } label: {
                    Label("Copy JSON", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    guard canSwitchSelectedRow(to: rowIndex) else { return }
                    tab.selectRow(rowIndex, openEditor: true)
                } label: {
                    Label("Edit Document", systemImage: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Divider()

            let maxInlineItems = 80
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(document.elements.prefix(maxInlineItems).enumerated()), id: \.offset) { _, el in
                    inlineTreeElementRow(key: el.key, value: el.value, depth: 0, rowIndex: rowIndex)
                }
                if document.elements.count > maxInlineItems {
                    truncatedTreeNotice(
                        remaining: document.elements.count - maxInlineItems,
                        depth: 0,
                        rowIndex: rowIndex
                    )
                }
            }
        }
        .padding(.leading, gutterWidth + 14)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .frame(width: totalWidth, alignment: .leading)
        .background(Color.accentColor.opacity(0.04))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.65))
                .frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)
        }
    }

    private func truncatedTreeNotice(remaining: Int, depth: Int, rowIndex: Int) -> some View {
        Button {
            guard canSwitchSelectedRow(to: rowIndex) else { return }
            tab.selectRow(rowIndex, openEditor: true)
        } label: {
            Text("+ \(remaining) more items — open in Document Editor to view all")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.leading, CGFloat(depth * 18 + 14))
        .padding(.top, 2)
    }

    private func inlineTreeElementRow(key: String, value: BSONValue, depth: Int, rowIndex: Int) -> AnyView {
        let maxChildren = 80
        let maxDepth = 8

        switch value {
        case .document(let subDoc):
            if depth >= maxDepth && !subDoc.isEmpty {
                return AnyView(
                    HStack(spacing: 8) {
                        Text("\(key):")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button {
                            guard canSwitchSelectedRow(to: rowIndex) else { return }
                            tab.selectRow(rowIndex, openEditor: true)
                        } label: {
                            Text("{ \(subDoc.count) fields — open Document Editor to view deeper nesting }")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, CGFloat(depth * 18 + 14))
                )
            }
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.purple)
                        Text(key)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text("Object (\(subDoc.count) fields)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.14))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                    .padding(.leading, CGFloat(depth * 18))

                    ForEach(Array(subDoc.elements.prefix(maxChildren).enumerated()), id: \.offset) { _, child in
                        inlineTreeElementRow(key: child.key, value: child.value, depth: depth + 1, rowIndex: rowIndex)
                    }
                    if subDoc.elements.count > maxChildren {
                        truncatedTreeNotice(remaining: subDoc.elements.count - maxChildren, depth: depth + 1, rowIndex: rowIndex)
                    }
                }
            )

        case .array(let arr):
            if depth >= maxDepth && !arr.isEmpty {
                return AnyView(
                    HStack(spacing: 8) {
                        Text("\(key):")
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button {
                            guard canSwitchSelectedRow(to: rowIndex) else { return }
                            tab.selectRow(rowIndex, openEditor: true)
                        } label: {
                            Text("[ \(arr.count) items — open Document Editor to view deeper nesting ]")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, CGFloat(depth * 18 + 14))
                )
            }
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.orange)
                        Text(key)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text("Array [\(arr.count)]")
                            .font(.system(size: 10.5, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    .padding(.leading, CGFloat(depth * 18))

                    ForEach(Array(arr.prefix(maxChildren).enumerated()), id: \.offset) { idx, item in
                        inlineTreeElementRow(key: "[\(idx)]", value: item, depth: depth + 1, rowIndex: rowIndex)
                    }
                    if arr.count > maxChildren {
                        truncatedTreeNotice(remaining: arr.count - maxChildren, depth: depth + 1, rowIndex: rowIndex)
                    }
                }
            )

        default:
            return AnyView(
                HStack(spacing: 8) {
                    Text("\(key):")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(value.displayCellText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(EarlgreyTheme.bsonValueColor(value))
                        .textSelection(.enabled)
                    Text(value.typeLabel)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, CGFloat(depth * 18 + 14))
            )
        }
    }

    // MARK: - Helpers
    private func objectPreviewSummary(_ doc: BSONDocument) -> String {
        if doc.isEmpty { return "{}" }
        let previews = doc.elements.prefix(2).map { el -> String in
            switch el.value {
            case .string(let s):
                let short = s.count > 12 ? String(s.prefix(12)) + "…" : s
                return "\(el.key): \"\(short)\""
            case .document:
                return "\(el.key): {…}"
            case .array(let a):
                return "\(el.key): [\(a.count)]"
            default:
                return "\(el.key): \(el.value.displayCellText)"
            }
        }
        let suffix = doc.count > 2 ? ", …" : ""
        return "{ " + previews.joined(separator: ", ") + suffix + " }"
    }

    private func arrayPreviewSummary(_ arr: [BSONValue]) -> String {
        if arr.isEmpty { return "[]" }
        let previews = arr.prefix(2).map { item -> String in
            switch item {
            case .string(let s):
                let short = s.count > 12 ? String(s.prefix(12)) + "…" : s
                return "\"\(short)\""
            case .document(let d):
                if let first = d.elements.first {
                    return "{\(first.key): …}"
                }
                return "{}"
            default:
                return item.displayCellText
            }
        }
        let suffix = arr.count > 2 ? ", …" : ""
        return "[ " + previews.joined(separator: ", ") + suffix + " ]"
    }

    private func columnWidth(for col: TableColumnDescriptor) -> CGFloat {
        if let custom = tab.columnWidths[col.path] {
            return custom
        }
        if col.path == "_id" {
            return 240
        }
        if col.isExpandableObject {
            return 225
        }
        if col.dominantType == "Array" {
            return 210
        }
        if col.dominantType == "Date" {
            return 205
        }
        if ["Int32", "Int64", "Double", "Decimal128"].contains(col.dominantType) {
            return max(115, CGFloat(col.path.count * 8 + 45))
        }
        if col.dominantType == "Boolean" {
            return max(105, CGFloat(col.path.count * 8 + 45))
        }
        return max(165, CGFloat(col.path.count * 8 + 60))
    }

    private func applyQuickFilter(path: String, value: BSONValue) {
        let singleDoc = BSONDocument(elements: [BSONElement(key: path, value: value)])
        let formattedFilter = BSONShellFormatter.format(singleDoc, indent: 0)
            .replacingOccurrences(of: "\n", with: " ")
        tab.queryText = "db.getCollection(\"\(tab.collection)\").find(\(formattedFilter))"
        Task {
            await workspace.runQuery(for: tab)
        }
    }
}

private final class ColumnDragState: ObservableObject {
    @Published var isHovering: Bool = false
    @Published var isDragging: Bool = false
    var dragStartWidth: CGFloat?
}

// MARK: - Column Resize Handle
private struct ColumnResizeHandle: View {
    let currentWidth: CGFloat
    let onResize: (CGFloat) -> Void
    let onAutoFit: () -> Void

    @StateObject private var dragState = ColumnDragState()

    var body: some View {
        let active = dragState.isHovering || dragState.isDragging
        ZStack(alignment: .trailing) {
            Color.clear
                .frame(width: 10)
            Rectangle()
                .fill(active ? Color.accentColor : Color.primary.opacity(0.10))
                .frame(width: active ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            dragState.isHovering = hovering
            if hovering || dragState.isDragging {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .onTapGesture(count: 2) {
            onAutoFit()
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !dragState.isDragging {
                        dragState.isDragging = true
                        dragState.dragStartWidth = currentWidth
                        NSCursor.resizeLeftRight.set()
                    }
                    if let start = dragState.dragStartWidth {
                        onResize(start + value.translation.width)
                    }
                }
                .onEnded { _ in
                    dragState.isDragging = false
                    dragState.dragStartWidth = nil
                    if !dragState.isHovering {
                        NSCursor.arrow.set()
                    }
                }
        )
    }
}

// MARK: - Nested Value Popover Tree
private struct NestedValuePopoverView: View {
    let path: String
    let value: BSONValue
    let onEditFullDocument: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(path, systemImage: "curlybraces")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                Spacer()
                Button("Edit Document") {
                    onEditFullDocument()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    nestedTreeRows(for: value, depth: 0)
                }
                .padding(12)
            }
            .frame(minWidth: 360, maxWidth: 480, minHeight: 160, maxHeight: 340)
        }
    }

    private func nestedTreeRows(for val: BSONValue, depth: Int) -> AnyView {
        let maxItems = 80
        let maxDepth = 8

        switch val {
        case .document(let doc):
            if depth >= maxDepth && !doc.isEmpty {
                return AnyView(
                    Button {
                        onEditFullDocument()
                    } label: {
                        Text("{ \(doc.count) fields — open Document Editor to view deeper nesting }")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, CGFloat(depth * 14))
                )
            }
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(doc.elements.prefix(maxItems).enumerated()), id: \.offset) { _, el in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(el.key):")
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if case .document(let sub) = el.value {
                                    Text("{ \(sub.count) fields }")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.purple)
                                } else if case .array(let arr) = el.value {
                                    Text("[ \(arr.count) items ]")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(el.value.displayCellText)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(EarlgreyTheme.bsonValueColor(el.value))
                                        .textSelection(.enabled)
                                }
                                Spacer()
                            }
                            .padding(.leading, CGFloat(depth * 14))

                            if case .document = el.value {
                                nestedTreeRows(for: el.value, depth: depth + 1)
                            } else if case .array = el.value {
                                nestedTreeRows(for: el.value, depth: depth + 1)
                            }
                        }
                    }
                    if doc.elements.count > maxItems {
                        Button {
                            onEditFullDocument()
                        } label: {
                            Text("+ \(doc.elements.count - maxItems) more items — open in Document Editor to view all")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, CGFloat(depth * 14))
                    }
                }
            )
        case .array(let arr):
            if depth >= maxDepth && !arr.isEmpty {
                return AnyView(
                    Button {
                        onEditFullDocument()
                    } label: {
                        Text("[ \(arr.count) items — open Document Editor to view deeper nesting ]")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, CGFloat(depth * 14))
                )
            }
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(arr.prefix(maxItems).enumerated()), id: \.offset) { idx, item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 6) {
                                Text("[\(idx)]")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if case .document(let sub) = item {
                                    Text("{ \(sub.count) fields }")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.purple)
                                } else if case .array(let subArr) = item {
                                    Text("[ \(subArr.count) items ]")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(item.displayCellText)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(EarlgreyTheme.bsonValueColor(item))
                                        .textSelection(.enabled)
                                }
                                Spacer()
                            }
                            .padding(.leading, CGFloat(depth * 14))

                            if case .document = item {
                                nestedTreeRows(for: item, depth: depth + 1)
                            } else if case .array = item {
                                nestedTreeRows(for: item, depth: depth + 1)
                            }
                        }
                    }
                    if arr.count > maxItems {
                        Button {
                            onEditFullDocument()
                        } label: {
                            Text("+ \(arr.count - maxItems) more items — open in Document Editor to view all")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, CGFloat(depth * 14))
                    }
                }
            )
        default:
            return AnyView(
                Text(val.displayCellText)
                    .font(.system(size: 12, design: .monospaced))
            )
        }
    }
}
