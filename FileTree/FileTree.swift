//
//  FileTree.swift
//  FileTree
//
//  Created by Devin Abbott on 8/17/18.
//  Copyright © 2018 Devin Abbott. All rights reserved.
//

import AppKit
import Foundation
import Witness
import Differ

private func isDirectory(path: FileTree.Path) -> Bool {
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
        return isDir.boolValue
    } else {
        return false
    }
}

// MARK: - NSPasteboard.PasteboardType

public extension NSPasteboard.PasteboardType {
    static let fileTreeIndex = NSPasteboard.PasteboardType(rawValue: "filetree.index")
}

public extension NSPasteboard.PasteboardType {
    static let fileTreeURL: NSPasteboard.PasteboardType = {
        if #available(OSX 10.13, *) {
            return NSPasteboard.PasteboardType.fileURL
        } else {
            return NSPasteboard.PasteboardType(rawValue: "filetree.url")
        }
    }()
}

// MARK: - NSTableColumn

private extension NSTableColumn {
    convenience init(title: String, resizingMask: ResizingOptions = .autoresizingMask) {
        self.init(identifier: NSUserInterfaceItemIdentifier(rawValue: title))
        self.title = title
        self.resizingMask = resizingMask
    }
}

// MARK: - NSOutlineView

extension NSOutlineView {
    public enum Style {
        case standard
        case singleColumn
    }

    public convenience init(style: Style) {
        self.init()

        switch style {
        case .standard:
            return
        case .singleColumn:
            let column = NSTableColumn(title: "OutlineColumn")
            column.minWidth = 100

            addTableColumn(column)
            outlineTableColumn = column
            columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            backgroundColor = .clear
            autoresizesOutlineColumn = true

            focusRingType = .none
            rowSizeStyle = .custom
            headerView = nil
        }
    }
}

// MARK: - FileTree

open class FileTree: NSBox {

    public typealias Path = String
    public typealias Name = String

    // MARK: Lifecycle

    public init(rootPath: Path? = nil) {
        super.init(frame: .zero)

        if let rootPath = rootPath {
            self.rootPath = rootPath
        }

        sharedInit()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        sharedInit()
    }

    private func sharedInit() {
        setUpViews()
        setUpConstraints()

        update()

        setUpWitness()

        outlineView.registerForDraggedTypes([.fileTreeIndex])

        initialized = true
    }

    // MARK: Public

    public var onAction: ((Path) -> Void)?

    public var onSelect: ((Path?) -> Void)?

    public var onCreateFile: ((Path, FileEventOptions) -> Void)?

    public var onDeleteFile: ((Path, FileEventOptions) -> Void)?

    public var onRenameFile: ((Path, Path, FileEventOptions) -> Void)?

    public var onPressDelete: ((Path) -> Void)?

    public var onPressEnter: ((Path) -> Void)?

    public var performMoveFile: ((Path, Path) -> Bool)?

    public var defaultRowStyle: FileTreeRowView.Style = .standard

    public var defaultRowHeight: CGFloat = 28.0 { didSet { update() } }

    public var defaultThumbnailSize = NSSize(width: 24, height: 24) { didSet { update() } }

    public var defaultThumbnailMargin: CGFloat = 4.0 { didSet { update() } }

    public var defaultFont: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular))

    /** Determine the name to display based on the file's full path. */
    public var displayNameForFile: ((Path) -> Name)? { didSet { update() } }

    /** Sets the height of the row. If not provided, height is set to `defaultRowHeight`. */
    public var rowHeightForFile: ((Path) -> CGFloat)? { didSet { update() } }

    public var rowViewForFile: ((Path, RowViewOptions) -> NSView)? { didSet { update() } }

    public var rowStyleForFile: ((Path, RowViewOptions) -> FileTreeRowView.Style)? { didSet { update() } }

    public var imageForFile: ((Path, NSSize) -> NSImage)? { didSet { update() } }

    public var menuForFile: ((Path) -> NSMenu?)?

    public var sortFiles: ((Name, Name) -> Bool)? { didSet { update() } }

    public var filterFiles: ((Name) -> Bool)? { didSet { update() } }

    public var validateProposedMove: ((Path, Path) -> Bool)?

    public var showHiddenFiles = false { didSet { update() } }

    public var showRootFile = true { didSet { update() } }

    public var intercellSpacing: NSSize {
        get { outlineView.intercellSpacing }
        set { outlineView.intercellSpacing = newValue }
    }

    public var isAnimationEnabled: Bool {
        get { outlineView.isAnimationEnabled }
        set { outlineView.isAnimationEnabled = newValue }
    }

    public var invalidatesIntrinsicContentSizeOnRowExpand: Bool = false {
        didSet {
            update()
        }
    }

    public var rootPath = "/" {
        didSet {
            if !initialized { return }

            outlineView.autosaveName = autosaveName

            setUpWitness()

            update()
        }
    }

    public func reloadData() {
        update()
    }

    @discardableResult public func beginRenamingFile(atPath path: Path) -> NSView? {
        if path == rootPath { return nil }

        renamingPath = path

        let index = outlineView.row(forItem: path)
        outlineView.scrollRowToVisible(index)
        outlineView.reloadItem(path)

        guard let cellView = outlineView.view(atColumn: 0, row: index, makeIfNecessary: false) else { return nil }

        // The caller will use this to initiate editing
        return cellView
    }

    public func endRenamingFile() {
        renamingPath = nil
    }

    private var renamingPath: String?

    private var contextMenuForPath: String?

    // MARK: Private

    private var witness: Witness?

    // We keep a cache of directory contents to prevent race condition bugs.
    //
    // If the number of files in a directory changes between the call to numberOfChildren
    // and the call to childOfItem, we can end up in an invalid state. We cache the contents
    // of the directory in the call to numberOfChildren to ensure it's the same in childOfItem.
    private var directoryContentsCache: [String: [String]] = [:]

    private var initialized = false
    private var outlineView = ControlledOutlineView(style: .singleColumn)
    private var scrollView = NSScrollView(frame: .zero)

    private var autosaveName: NSTableView.AutosaveName {
        return NSTableView.AutosaveName(rootPath)
    }

    private func shouldDisplay(fileName: String) -> Bool {
        if let filterFiles = filterFiles {
            return filterFiles(fileName)
        }

        if !showHiddenFiles {
            return !fileName.starts(with: ".")
        }

        return true
    }

    private func filteredAndSorted(fileNames: [String]) -> [String] {
        var children = fileNames.filter(shouldDisplay)

        if let sortComparator = sortFiles {
            children = children.sorted(by: sortComparator)
        } else {
            children = children.sorted()
        }

        return children
    }

    private func contentsOfDirectory(atPath path: String) -> [String] {
        let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []

        return filteredAndSorted(fileNames: children)
    }

    private func cachedContentsOfDirectory(atPath path: String, index: Int) -> String {
        let contents = directoryContentsCache[path] ?? contentsOfDirectory(atPath: path)

        if contents.count > index {
            return contents[index]
        } else {
            return ""
        }
    }

    public var selectedFile: Path? {
        didSet {
            setSelectedFile(selectedFile, oldPath: oldValue)
        }
    }

    public func setSelectedFile(_ selectedPath: Path?, oldPath oldValue: Path?) {
        if let selectedPath = selectedPath {
            var selectedIndex = outlineView.row(forItem: selectedPath)

            // File is either not in the tree or in a collapsed parent
            if selectedIndex == -1 {
                let ancestorPaths = URL(fileURLWithPath: selectedPath).ancestorPaths().reversed()

                for path in ancestorPaths {
                    let index = outlineView.row(forItem: path)

                    if index != -1 {
                        outlineView.expandItem(path)
                    }
                }

                selectedIndex = outlineView.row(forItem: selectedPath)
            }

            outlineView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)

            // Check that the view is currently visible, otherwise it will scroll to the bottom
            if visibleRect != .zero {
                outlineView.scrollRowToVisible(selectedIndex)
            }

            var reloadIndexSet = IndexSet(integer: selectedIndex)

            if let oldValue = oldValue {
                let oldSelectedIndex = outlineView.row(forItem: oldValue)
                reloadIndexSet.insert(oldSelectedIndex)
            }

            outlineView.reloadData(forRowIndexes: reloadIndexSet, columnIndexes: IndexSet(integer: 0))
        } else {
            outlineView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
        }
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row = outlineView.row(at: point)

        let path: Path
        if row >= 0, let item = outlineView.item(atRow: row) as? Path {
            path = item
        } else {
            path = rootPath
        }

        if let menu = menuForFile?(path) {
            menu.delegate = self

            contextMenuForPath = path

            if row >= 0, let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? FileTreeRowView {
                rowView.drawsContextMenuOutline = true
            }

            return menu
        }

        return nil
    }

    override public func keyDown(with event: NSEvent) {
        let row = outlineView.selectedRow
        guard let path = outlineView.item(atRow: row) as? Path else { return }

        switch event.keyCode {
        case 51: // Delete
            onPressDelete?(path)
        case 36: // Enter
            onPressEnter?(path)
        default:
            break
        }
    }

    func setUpViews() {
        boxType = .custom
        borderType = .lineBorder
        contentViewMargins = .zero
        borderWidth = 0

        outlineView.autosaveExpandedItems = true
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.autosaveName = autosaveName

        outlineView.reloadData()

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.addSubview(outlineView)
        scrollView.documentView = outlineView

        outlineView.sizeToFit()

        addSubview(scrollView)

        outlineView.onAction = { [unowned self] row in
            if let path = self.outlineView.item(atRow: row) as? Path {
                self.onAction?(path)
            }
        }

        outlineView.onSelect = { [unowned self] row in
            let path = self.outlineView.item(atRow: row) as? Path
            self.onSelect?(path)
        }
    }

    func setUpConstraints() {
        translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        topAnchor.constraint(equalTo: scrollView.topAnchor).isActive = true
        bottomAnchor.constraint(equalTo: scrollView.bottomAnchor).isActive = true
        leadingAnchor.constraint(equalTo: scrollView.leadingAnchor).isActive = true
        trailingAnchor.constraint(equalTo: scrollView.trailingAnchor).isActive = true
    }

    func update() {
        outlineView.reloadData()
    }
}

// MARK: - Size

extension FileTree {
    open override var intrinsicContentSize: NSSize {
        return outlineView.intrinsicContentSize
    }

    open override var fittingSize: NSSize {
        return outlineView.fittingSize
    }
}

// MARK: - File system events

extension FileTree {
    enum FSEventType: Equatable {
        case rename(from: String, to: String, inParent: URL, ownEvent: Bool)
        case directory(URL, ownEvent: Bool)
        case file(URL, ownEvent: Bool)

        var directoryURL: URL {
            switch self {
            case .rename(_, _, inParent: let url, _):
                return url
            case .directory(let url, _):
                return url.deletingLastPathComponent()
            case .file(let url, _):
                return url.deletingLastPathComponent()
            }
        }

        var nameMapping: (from: String, to: String)? {
            switch self {
            case let .rename(from: from, to: to, _, _):
                return (from: from, to: to)
            default:
                return nil
            }
        }

        var ownEventURL: URL? {
            switch self {
            case let .rename(_, to: to, inParent: parentURL, ownEvent: ownEvent):
                return ownEvent ? parentURL.appendingPathComponent(to) : nil
            case .directory(let url, let ownEvent):
                return ownEvent ? url : nil
            case .file(let url, let ownEvent):
                return ownEvent ? url : nil
            }
        }
    }

    struct FSEvent {
        let path: String
        let eventType: FSEventType
    }

    private func setUpWitness() {
        let flags: EventStreamCreateFlags = [
            EventStreamCreateFlags.FileEvents,
            EventStreamCreateFlags.MarkSelf,
            EventStreamCreateFlags.WatchRoot]

        self.witness = Witness(paths: [rootPath], flags: flags, latency: 0.150) { events in
            var fsEvents: [FSEvent] = []

            // When a file is renamed, we receive two consecutive events with .ItemRenamed set.
            // We group these into a single event.
            var i = 0
            while i < events.count {
                let event = events[i]
                let eventURL = URL(fileURLWithPath: event.path)

                // Ignore events for files we don't display
                if !self.shouldDisplay(fileName: eventURL.lastPathComponent) {
                    i += 1

                    continue
                }

                let ownEvent = event.flags.contains(.OwnEvent)

                if let next = i + 1 < events.count ? events[i + 1] : nil,
                    event.flags.contains(.ItemRenamed) &&
                    next.flags.contains(.ItemRenamed) {

                    let nextURL = URL(fileURLWithPath: next.path)
                    let eventParentURL = eventURL.deletingLastPathComponent()

                    if eventParentURL == nextURL.deletingLastPathComponent() {
                        fsEvents.append(
                            FSEvent(
                                path: event.path,
                                eventType: .rename(
                                    from: eventURL.lastPathComponent,
                                    to: nextURL.lastPathComponent,
                                    inParent: eventParentURL,
                                    ownEvent: ownEvent)))

                        i += 2

                        continue
                    }
                }

                if event.flags.contains(.ItemIsFile) {
                    fsEvents.append(
                        FSEvent(path: event.path, eventType: .file(eventURL, ownEvent: ownEvent)))
                } else if event.flags.contains(.ItemIsDir) {
                    fsEvents.append(
                        FSEvent(path: event.path, eventType: .directory(eventURL, ownEvent: ownEvent)))
                }

                i += 1
            }

            // Group events by directory so that we can apply changes per-directory.
            // We determine the actual changes to make by scanning the directory, not be the events
            // we receive, so we should only need to process each directory once.
            let eventsForDirectory: [String: [FSEvent]] = fsEvents.reduce([:], { acc, fsEvent in
                var acc = acc

                let directoryPath = fsEvent.eventType.directoryURL.path
                if acc[directoryPath] == nil {
                    acc[directoryPath] = []
                }
                acc[directoryPath]?.append(fsEvent)

                return acc
            })

            DispatchQueue.main.async {
                self.outlineView.beginUpdates()

                eventsForDirectory.forEach { directoryPath, fsEvents in
                    var nameMapping: [String: String] = [:]
                    var ownEventPaths: [Path] = []

                    fsEvents.forEach { fsEvent in
                        if let mapping = fsEvent.eventType.nameMapping {
                            nameMapping[mapping.to] = mapping.from
                        }

                        if let ownEventURL = fsEvent.eventType.ownEventURL {
                            ownEventPaths.append(ownEventURL.path)
                        }
                    }

                    self.applyChangesToDirectory(
                        atPath: directoryPath,
                        nameMapping: nameMapping,
                        ownEventPaths: ownEventPaths)
                }

                self.setSelectedFile(self.selectedFile, oldPath: self.selectedFile)

                self.outlineView.endUpdates()
            }
        }
    }

    // First insert and then delete items for this path. We process insertions and deletions
    // in batches to avoid leaving the outline view's indexes in an inconsistent state.
    private func applyChangesToDirectory(
        atPath path: Path,
        nameMapping: [String: String] = [:],
        ownEventPaths: [Path] = []) {

        // If we're not showing the rootPath, it won't exist as an item in the tree.
        // Instead we use nil to specify the top-level container.
        let parent = (!showRootFile && path == rootPath) ? nil : path

        if directoryContentsCache[path] == nil {
            outlineView.reloadItem(parent, reloadChildren: true)
            outlineView.sizeToFit()
            return
        }

        let nextFileNames = contentsOfDirectory(atPath: path)
        let prevFileNames = directoryContentsCache[path] ?? []

        directoryContentsCache[path] = nextFileNames

        let diff = prevFileNames.diff(nextFileNames)

        // Process deletions first, since these will affect the indexes of insertions.
        let deleted = diff.elements.compactMap { element -> Optional<Int> in
            switch element {
            case let .delete(at: index):
                return index
            default:
                return nil
            }
        }

        if !deleted.isEmpty {
            outlineView.removeItems(
                at: IndexSet(deleted),
                inParent: parent,
                withAnimation: NSTableView.AnimationOptions.slideUp)
        }

        let inserted = diff.elements.compactMap { element -> Optional<Int> in
            switch element {
            case let .insert(at: index):
                return index
            default:
                return nil
            }
        }

        if !inserted.isEmpty {
            outlineView.insertItems(
                at: IndexSet(inserted),
                inParent: parent,
                withAnimation: NSTableView.AnimationOptions.slideDown)
        }

        // Filter out moves before firing created/deleted events
        let extendedDiff = prevFileNames.extendedDiff(nextFileNames, isEqual: { prev, next in
            if let found = nameMapping[next] {
                if found == prev {
                    return true
                }
            }

            return prev == next
        })

        extendedDiff.forEach { element in
            switch element {
            case let .delete(at: index):
                let url = URL(fileURLWithPath: path).appendingPathComponent(prevFileNames[index])
                self.onDeleteFile?(url.path, ownEventPaths.contains(url.path) ? .ownEvent : .none)
            case let .insert(at: index):
                let url = URL(fileURLWithPath: path).appendingPathComponent(nextFileNames[index])
                self.onCreateFile?(url.path, ownEventPaths.contains(url.path) ? .ownEvent : .none)
            case .move:
                // Renames don't necessarily cause the position to change. Handle renames afterwards
                // since we know which files have been renamed from the filesystem events
                break
            }
        }

        nameMapping.forEach { key, value in
            let prevURL = URL(fileURLWithPath: path).appendingPathComponent(value)
            let nextURL = URL(fileURLWithPath: path).appendingPathComponent(key)
            self.onRenameFile?(prevURL.path, nextURL.path, ownEventPaths.contains(nextURL.path) ? .ownEvent : .none)
        }

        invalidateIntrinsicContentSize()
    }
}

// MARK: - NSOutlineViewDataSource

extension FileTree: NSOutlineViewDataSource {

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            if showRootFile {
                return 1
            } else {
                let contents = contentsOfDirectory(atPath: rootPath)
                directoryContentsCache[rootPath] = contents
                return contents.count
            }
        }

        guard let path = item as? String else { return 0 }

        let contents = contentsOfDirectory(atPath: path)
        directoryContentsCache[path] = contents
        return contents.count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            if showRootFile {
                return rootPath
            } else {
                return rootPath + "/" + cachedContentsOfDirectory(atPath: rootPath, index: index)
            }
        }
        let path = item as! String
        return path + "/" + cachedContentsOfDirectory(atPath: path, index: index)
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return outlineView.numberOfChildren(ofItem: item) > 0
    }

    public func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? {
        return item as? String
    }

    public func outlineView(_ outlineView: NSOutlineView, itemForPersistentObject object: Any) -> Any? {
        return object as? String
    }

    public func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        return item
    }

    // MARK: - Drag and drop

    typealias Element = Path

    public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let pasteboardItem = NSPasteboardItem()
        let index = outlineView.row(forItem: item)

        pasteboardItem.setString(String(index), forType: .fileTreeIndex)

        if let path = item as? String {
            pasteboardItem.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileTreeURL)
        }

        return pasteboardItem
    }

    public func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {

        let sourceIndexString = info.draggingPasteboard.string(forType: .fileTreeIndex)

        if let sourceIndexString = sourceIndexString,
            let sourceIndex = Int(sourceIndexString),
            let sourceItem = outlineView.item(atRow: sourceIndex) as? Element,
            let relativeItem = item as? Element? {

            let acceptanceCategory = outlineView.shouldAccept(dropping: sourceItem, relativeTo: relativeItem, at: index)

            switch acceptanceCategory {
            case .into(parent: let parentItem, _):
                let sourceItemPath = URL(fileURLWithPath: sourceItem)
                let proposedPath = URL(fileURLWithPath: parentItem).appendingPathComponent(sourceItemPath.lastPathComponent).path

                if let path = relativeItem, isDirectory(path: path) && validateProposedMoveInternal(oldPath: sourceItem, newPath: proposedPath) {
                    return NSDragOperation.move
                }
            case .intoContainer:
                let sourceItemPath = URL(fileURLWithPath: sourceItem)
                let proposedPath = URL(fileURLWithPath: rootPath).appendingPathComponent(sourceItemPath.lastPathComponent).path

                if !showRootFile && validateProposedMoveInternal(oldPath: sourceItem, newPath: proposedPath) {
                    return NSDragOperation.move
                }
            default: break
            }
        }

        return NSDragOperation()
    }

    public func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let sourceIndexString = info.draggingPasteboard.string(forType: .fileTreeIndex)

        if let sourceIndexString = sourceIndexString,
            let sourceIndex = Int(sourceIndexString),
            let sourceItem = outlineView.item(atRow: sourceIndex) as? Element,
            let relativeItem = item as? Element? {

            let acceptanceCategory = outlineView.shouldAccept(dropping: sourceItem, relativeTo: relativeItem, at: index)

            switch acceptanceCategory {
            case .into(parent: let parentItem, _):
                let sourceItemPath = URL(fileURLWithPath: sourceItem)
                let proposedPath = URL(fileURLWithPath: parentItem).appendingPathComponent(sourceItemPath.lastPathComponent).path
                return performMoveFile?(sourceItem, proposedPath) ?? false
            case .intoContainer(_):
                let sourceItemPath = URL(fileURLWithPath: sourceItem)
                let proposedPath = URL(fileURLWithPath: rootPath).appendingPathComponent(sourceItemPath.lastPathComponent).path
                return performMoveFile?(sourceItem, proposedPath) ?? false
            default:
                break
            }
        }

        return false
    }

    private func validateProposedMoveInternal(oldPath: Path, newPath: Path) -> Bool {
        return oldPath != newPath && validateProposedMove?(oldPath, newPath) ?? true
    }
}

// MARK: - FileTreeRowView

open class FileTreeRowView: NSTableRowView {

    public enum Style: Equatable {
        case standard
        case custom(CustomStyle)

        public static var rounded: Style = .custom(.rounded)
    }

    public struct CustomStyle: Equatable {
        public init(
            inset: NSSize = .zero,
            radius: NSSize = .zero,
            ringInset: NSSize = .zero,
            ringRadius: NSSize = .zero,
            backgroundColor: NSColor? = nil,
            bottomBorderColor: NSColor? = nil
        ) {
            self.inset = inset
            self.radius = radius
            self.ringInset = ringInset
            self.ringRadius = ringRadius
            self.backgroundColor = backgroundColor
            self.bottomBorderColor = bottomBorderColor
        }

        public var inset: NSSize
        public var radius: NSSize
        public var ringInset: NSSize
        public var ringRadius: NSSize
        public var backgroundColor: NSColor?
        public var bottomBorderColor: NSColor?

        public static var rounded = CustomStyle(
            inset: NSSize(width: 3, height: 1),
            radius: NSSize(width: 5, height: 5),
            ringInset: NSSize(width: 3, height: 1),
            ringRadius: NSSize(width: 5, height: 5)
        )
    }

    public init(style: Style = .standard) {
        self.style = style

        super.init(frame: .zero)
    }

    required public init?(coder: NSCoder) {
        self.style = .standard

        super.init(coder: coder)
    }

    open var style: Style {
        didSet {
            if style != oldValue {
                needsDisplay = true
            }
        }
    }

    open var drawsContextMenuOutline = false {
        didSet {
            if drawsContextMenuOutline != oldValue {
                needsDisplay = true
            }
        }
    }

    /**
     Make sure we're not drawing a row bigger than the containing table view.

     Sometimes when expanding a row, it will temporarily increase in width.
     */
    open var rowWidthForDrawing: CGFloat {
        return min(superview?.superview?.bounds.width ?? CGFloat.greatestFiniteMagnitude, bounds.width)
    }

    /**
     Get a rect suitable for drawing the row's background.
     */
    open var rectForDrawing: NSRect {
        return NSRect(x: bounds.origin.y, y: bounds.origin.y, width: rowWidthForDrawing, height: bounds.height)
    }

    open override func drawSelection(in dirtyRect: NSRect) {
        switch style {
        case .standard:
            super.drawSelection(in: dirtyRect)
        case .custom(let style):
            if #available(OSX 10.14, *) {
                if isSelected {
                    if let window = window, window.isMainWindow && window.isKeyWindow && window.firstResponder == superview {
                        NSColor.selectedContentBackgroundColor.setFill()
                    } else {
                        NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
                    }
                    NSBezierPath(
                        roundedRect: rectForDrawing.insetBy(dx: style.inset.width, dy: style.inset.height),
                        xRadius: style.radius.width,
                        yRadius: style.radius.height
                    ).fill()
                }
            } else {
                super.drawSelection(in: dirtyRect)
            }
        }
    }

    open override func draw(_ dirtyRect: NSRect) {
        switch style {
        case .standard:
            break
        case .custom(let style):
            if let backgroundColor = style.backgroundColor {
                backgroundColor.setFill()
                dirtyRect.fill()
            }
        }

        super.draw(dirtyRect)

        switch style {
        case .standard:
            break
        case .custom(let style):
            if let bottomBorderColor = style.bottomBorderColor {
                bottomBorderColor.setFill()
                let rect = self.rectForDrawing
                NSRect(x: rect.origin.x, y: rect.maxY - 1, width: rect.width, height: 1).fill()
            }
        }

        if drawsContextMenuOutline {
            if #available(OSX 10.14, *) {
                NSColor.controlAccentColor.setStroke()
            } else {
                NSColor.selectedControlColor.setStroke()
            }

            switch style {
            case .standard:
                let path = NSBezierPath(roundedRect: rectForDrawing.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3)
                path.lineWidth = 2
                path.stroke()
            case .custom(let style):
                let path = NSBezierPath(
                    roundedRect: bounds.insetBy(dx: style.ringInset.width, dy: style.ringInset.height),
                    xRadius: style.ringRadius.width,
                    yRadius: style.ringRadius.height
                )
                path.lineWidth = 2
                path.stroke()
            }
        }
    }
}

// MARK: - FileEventOptions

extension FileTree {

    public struct FileEventOptions: OptionSet {
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public let rawValue: Int

        // The filesystem operation that caused this event was triggered from this process
        public static let ownEvent = FileEventOptions(rawValue: 1 << 0)

        public static let none: FileEventOptions = []
    }
}

// MARK: - RowViewOptions

extension FileTree {

    public struct RowViewOptions: OptionSet {
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public let rawValue: Int

        public static let editable = RowViewOptions(rawValue: 1 << 0)
        public static let hasActiveContextMenu = RowViewOptions(rawValue: 1 << 1)
        public static let isFirstRow = RowViewOptions(rawValue: 1 << 2)
        public static let isLastRow = RowViewOptions(rawValue: 1 << 3)

        public static let none: RowViewOptions = []
    }

    private func rowViewOptions(atPath path: Path) -> RowViewOptions {
        var options: RowViewOptions = []

        if renamingPath == path {
            options.insert(.editable)
        }

        if contextMenuForPath == path {
            options.insert(.hasActiveContextMenu)
        }

        if outlineView.row(forItem: path) == 0 {
            options.insert(.isFirstRow)
        }

        if outlineView.row(forItem: path) == outlineView.numberOfRows - 1 {
            options.insert(.isLastRow)
        }

        return options
    }
}

// MARK: - NSOutlineViewDelegate

extension FileTree: NSOutlineViewDelegate {

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return false
    }

    public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        guard let path = item as? String else { return nil }

        let options = rowViewOptions(atPath: path)

        let rowView = FileTreeRowView(style: rowStyleForFile?(path, options) ?? defaultRowStyle)

        rowView.drawsContextMenuOutline = contextMenuForPath == path

        return rowView
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let path = item as? String else { return NSView() }

        let options = rowViewOptions(atPath: path)

        return rowViewForFile?(path, options)
    }

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let path = item as? String else { return defaultRowHeight }

        return rowHeightForFile?(path) ?? defaultRowHeight
    }

    public func outlineViewItemDidExpand(_ notification: Notification) {
        if invalidatesIntrinsicContentSizeOnRowExpand {
            invalidateIntrinsicContentSize()
        }
    }

    public func outlineViewItemDidCollapse(_ notification: Notification) {
        if invalidatesIntrinsicContentSizeOnRowExpand {
            invalidateIntrinsicContentSize()
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
        if row - 1 >= 0,
            let previous = outlineView.rowView(atRow: row - 1, makeIfNecessary: false) as? FileTreeRowView,
            let path = outlineView.item(atRow: row - 1) as? String {
            previous.style = rowStyleForFile?(path, rowViewOptions(atPath: path)) ?? defaultRowStyle
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, didRemove rowView: NSTableRowView, forRow row: Int) {
        if row + 1 < outlineView.numberOfRows,
            let next = outlineView.rowView(atRow: row + 1, makeIfNecessary: false) as? FileTreeRowView,
            let path = outlineView.item(atRow: row + 1) as? String {
            next.style = rowStyleForFile?(path, rowViewOptions(atPath: path)) ?? defaultRowStyle
        }
    }
}

// MARK: - NSMenuDelegate

extension FileTree: NSMenuDelegate {
    public func menuDidClose(_ menu: NSMenu) {
        if let contextMenuForPath = self.contextMenuForPath {
            self.contextMenuForPath = nil

            let row = outlineView.row(forItem: contextMenuForPath)

            if row >= 0, let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? FileTreeRowView {
                rowView.drawsContextMenuOutline = false
            }
        }
    }
}

// MARK: - Configurations

extension FileTree {

    public class DefaultCellView: NSTableCellView, NSTextFieldDelegate {

        public var onChangeBackgroundStyle: ((NSView.BackgroundStyle) -> Void)?

        public var onBeginRenaming: (() -> Void)?

        public var onEndRenaming: ((FileTree.Path) -> Void)?

        override public var backgroundStyle: NSView.BackgroundStyle {
            didSet { onChangeBackgroundStyle?(backgroundStyle) }
        }

        public func controlTextDidEndEditing(_ obj: Notification) {
            guard let textView = obj.object as? NSTextField else { return }

            if let cellView = textView.superview as? DefaultCellView {
                cellView.onEndRenaming?(textView.stringValue)
            }
        }
    }

    // A default configuration, provided for convenience.
    public static func makeDefaultTree(rootPath: Path? = nil) -> FileTree {
        let fileTree = FileTree(rootPath: rootPath)

        fileTree.imageForFile = { path, size in
            return NSWorkspace.shared.icon(forFile: path)
        }

        fileTree.rowViewForFile = { path, options in
            let thumbnailSize = fileTree.defaultThumbnailSize
            let thumbnailMargin = fileTree.defaultThumbnailMargin
            let name = fileTree.displayNameForFile?(path) ?? URL(fileURLWithPath: path).lastPathComponent

            let view = DefaultCellView()

            let textView = NSTextField(labelWithString: name)

            if options.contains(.editable) {
                textView.isEditable = true
                textView.isEnabled = true
            }

            let imageView = NSImageView(image: fileTree.imageForFile?(path, thumbnailSize) ?? NSImage())
            imageView.imageScaling = .scaleProportionallyUpOrDown

            view.addSubview(textView)
            view.addSubview(imageView)

            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: thumbnailMargin).isActive = true
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            imageView.widthAnchor.constraint(equalToConstant: thumbnailSize.width).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: thumbnailSize.height).isActive = true

            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: thumbnailMargin * 2 + thumbnailSize.width).isActive = true
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4).isActive = true
            textView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            textView.font = fileTree.defaultFont
            textView.maximumNumberOfLines = 1
            textView.lineBreakMode = .byTruncatingMiddle

            view.onChangeBackgroundStyle = { style in
                switch style {
                case .light:
                    textView.textColor = NSColor.controlTextColor
                case .dark:
                    textView.textColor = NSColor.selectedControlTextColor
                default:
                    break
                }
            }

            view.onBeginRenaming = {
                textView.delegate = view
                NSApp.activate(ignoringOtherApps: true)
                fileTree.window?.makeFirstResponder(textView)
            }

            view.onEndRenaming = { newName in
                textView.delegate = nil

                fileTree.endRenamingFile()

                if newName != name {
                    let newPath = URL(fileURLWithPath: path)
                        .deletingLastPathComponent()
                        .appendingPathComponent(newName)
                        .path
                    let _ = fileTree.performMoveFile?(path, newPath)
                }
            }

            return view
        }

        fileTree.performMoveFile = { oldPath, newPath in
            do {
                try FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
                return true
            } catch {
                Swift.print("Failed to move \(oldPath) to \(newPath)")
                return false
            }
        }

        return fileTree
    }
}

// MARK: - ControlledOutlineView

open class ControlledOutlineView: NSOutlineView {

    open override func expandItem(_ item: Any?, expandChildren: Bool) {
        if isAnimationEnabled {
            super.expandItem(item, expandChildren: expandChildren)
        } else {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0

            super.expandItem(item, expandChildren: expandChildren)

            NSAnimationContext.endGrouping()
        }
    }

    open override func collapseItem(_ item: Any?, collapseChildren: Bool) {
        if isAnimationEnabled {
            super.collapseItem(item, collapseChildren: collapseChildren)
        } else {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0

            super.collapseItem(item, collapseChildren: collapseChildren)

            NSAnimationContext.endGrouping()
        }
    }

    open var isAnimationEnabled: Bool = true

    open var onAction: ((Int) -> Void)?

    open var onSelect: ((Int) -> Void)?

    open var dragThreshold: CGFloat = 5

    open override func mouseDown(with event: NSEvent) {
        trackMouse(startingWith: event)
    }

    open override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)

        onSelect?(row)
        onAction?(row)
    }

    open override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 126: // Up
            if numberOfRows == 0 {
                onSelect?(-1)
            } else {
                let newRow = max(0, selectedRow - 1)
                onSelect?(newRow)
            }
        case 125: // Down
            if numberOfRows == 0 {
                onSelect?(-1)
            } else {
                let newRow = min(selectedRow + 1, numberOfRows - 1)
                onSelect?(newRow)
            }
        default:
            super.keyDown(with: event)
        }
    }

    open func trackMouse(startingWith initialEvent: NSEvent) {
        guard let window = window else { return }

        let initialPosition = convert(initialEvent.locationInWindow, from: nil)

        trackingLoop: while true {
            let event = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged])!
            let position = convert(event.locationInWindow, from: nil)

            switch event.type {
            case .leftMouseDragged:
                // After a certain distance, transfer control back to default drag code
                if initialPosition.distance(to: position) > dragThreshold {
                    super.mouseDown(with: initialEvent)
                    super.mouseMoved(with: event)
                    break trackingLoop
                }
            case .leftMouseUp:
                mouseUp(with: event)
                break trackingLoop
            default:
                break
            }
        }
    }
}

// MARK: - NSPoint

private extension NSPoint {
    func distance(to: NSPoint) -> CGFloat {
        return sqrt((x - to.x) * (x - to.x) + (y - to.y) * (y - to.y))
    }
}

// MARK: - URL

private extension URL {
    func ancestorPaths() -> [String] {
        var ancestors: [String] = []
        var parentURL = self
        var currentURL = parentURL.deletingLastPathComponent()

        // Fail when the path current path stops getting shorter, e.g. "/" is shorter than "/../",
        // which is how `deletingLastPathComponent` behaves on the root path
        while currentURL.path.count < parentURL.path.count {
            ancestors.append(currentURL.path)
            parentURL = currentURL
            currentURL = currentURL.deletingLastPathComponent()
        }

        return ancestors
    }
}
