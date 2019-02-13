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

// MARK: - NSTableColumn

private extension NSTableColumn {
    convenience init(title: String, resizingMask: ResizingOptions = .autoresizingMask) {
        self.init(identifier: NSUserInterfaceItemIdentifier(rawValue: title))
        self.title = title
        self.resizingMask = resizingMask
    }
}

// MARK: - NSOutlineView

private extension NSOutlineView {
    enum Style {
        case standard
        case singleColumn
    }

    convenience init(style: Style) {
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

public class FileTree: NSBox {

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

        initialized = true
    }

    // MARK: Public

    public var onAction: ((Path) -> Void)?

    public var onSelect: ((Path) -> Void)?

    public var onCreateFile: ((Path) -> Void)?

    public var onDeleteFile: ((Path) -> Void)?

    public var onRenameFile: ((Path, Path) -> Void)?

    public var defaultRowHeight: CGFloat = 28.0 { didSet { update() } }

    public var defaultThumbnailSize = NSSize(width: 24, height: 24) { didSet { update() } }

    public var defaultThumbnailMargin: CGFloat = 4.0 { didSet { update() } }

    public var defaultFont: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular))

    /** Determine the name to display based on the file's full path. */
    public var displayNameForFile: ((Path) -> Name)? { didSet { update() } }

    /** Sets the height of the row. If not provided, height is set to `defaultRowHeight`. */
    public var rowHeightForFile: ((Path) -> CGFloat)? { didSet { update() } }

    public var rowViewForFile: ((Path, RowViewOptions) -> NSView)? { didSet { update() } }

    public var imageForFile: ((Path, NSSize) -> NSImage)? { didSet { update() } }

    public var menuForFile: ((Path) -> NSMenu?)?

    public var sortFiles: ((Name, Name) -> Bool)? { didSet { update() } }

    public var filterFiles: ((Name) -> Bool)? { didSet { update() } }

    public var showHiddenFiles = false { didSet { update() } }

    public var showRootFile = true { didSet { update() } }

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
    private var outlineView = NSOutlineView(style: .singleColumn)
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

    @objc func handleAction(_ sender: AnyObject?) {
        let row = outlineView.selectedRow
        guard let path = outlineView.item(atRow: row) as? Path else { return }
        onAction?(path)
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard let path = outlineView.item(atRow: row) as? Path else { return }
        onSelect?(path)
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row = outlineView.row(at: point)
        guard let path = outlineView.item(atRow: row) as? Path else { return nil }

        if let menu = menuForFile?(path) {
            menu.delegate = self

            contextMenuForPath = path

            if let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? FileTreeRowView {
                rowView.drawsContextMenuOutline = true
            }

            return menu
        }

        return nil
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
        outlineView.target = self
        outlineView.action = #selector(handleAction(_:))

        outlineView.reloadData()

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.addSubview(outlineView)
        scrollView.documentView = outlineView

        outlineView.sizeToFit()

        addSubview(scrollView)

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

// MARK: - File system events

extension FileTree {
    enum FSEventType: Equatable {
        case rename(from: String, to: String, inParent: URL)
        case directory(URL)

        var directoryURL: URL? {
            switch self {
            case .rename:
                return nil
            case .directory(let url):
                return url
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

        self.witness = Witness(paths: [rootPath], flags: flags, latency: 0) { events in
//            print("file system events received: \(events)")

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

                let eventParentURL = eventURL.deletingLastPathComponent()

                if let next = i + 1 < events.count ? events[i + 1] : nil,
                    event.flags.contains(.ItemRenamed) &&
                    next.flags.contains(.ItemRenamed) {

                    let nextURL = URL(fileURLWithPath: next.path)

                    if eventParentURL == nextURL.deletingLastPathComponent() {
                        fsEvents.append(
                            FSEvent(
                                path: event.path,
                                eventType: .rename(
                                    from: eventURL.lastPathComponent,
                                    to: nextURL.lastPathComponent,
                                    inParent: eventParentURL)))

                        i += 2

                        continue
                    }
                }

                if event.flags.contains(.ItemIsFile) {
                    fsEvents.append(FSEvent(path: event.path, eventType: .directory(eventParentURL)))
                } else if event.flags.contains(.ItemIsDir) {
                    fsEvents.append(FSEvent(path: event.path, eventType: .directory(eventURL)))
                }

                i += 1
            }

//            Swift.print(fsEvents)

            DispatchQueue.main.async {
                fsEvents.forEach { fsEvent in
                    switch fsEvent.eventType {
                    case let .rename(from: from, to: to, inParent: parentURL):
                        self.applyChangesToDirectory(atPath: parentURL.path, pathMapping: [to: from])
                    case .directory(let url):
                        self.applyChangesToDirectory(atPath: url.path)
                    }
                }
            }
        }
    }

    private func applyChangesToDirectory(atPath path: Path, pathMapping: [String: String] = [:]) {
        if directoryContentsCache[path] == nil {
            outlineView.reloadItem(path, reloadChildren: true)
            outlineView.sizeToFit()
            return
        }

        let nextFileNames = contentsOfDirectory(atPath: path)
        let prevFileNames = directoryContentsCache[path] ?? []

        outlineView.beginUpdates()

        directoryContentsCache[path] = nextFileNames

        let diff = prevFileNames.diff(nextFileNames)

        // Process deletions first, since these will affect the indexes of insertions
        diff.elements.forEach { element in
            switch element {
            case let .delete(at: index):
                outlineView.removeItems(
                    at: IndexSet(integer: index),
                    inParent: path,
                    withAnimation: NSTableView.AnimationOptions.slideUp)
            default:
                break
            }
        }

        diff.elements.forEach { element in
            switch element {
            case let .insert(at: index):
                outlineView.insertItems(
                    at: IndexSet(integer: index),
                    inParent: path,
                    withAnimation: NSTableView.AnimationOptions.slideDown)
            default:
                break
            }
        }

        outlineView.endUpdates()

        // Filter out moves before firing created/deleted events
        let extendedDiff = prevFileNames.extendedDiff(nextFileNames, isEqual: { prev, next in
            if let found = pathMapping[next] {
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
                self.onDeleteFile?(url.path)
            case let .insert(at: index):
                let url = URL(fileURLWithPath: path).appendingPathComponent(nextFileNames[index])
                self.onCreateFile?(url.path)
            case .move:
                // Renames don't necessarily cause the position to change. Handle renames afterwards
                // since we know which files have been renamed from the filesystem events
                break
            }
        }

        pathMapping.forEach { key, value in
            let prevURL = URL(fileURLWithPath: path).appendingPathComponent(value)
            let nextURL = URL(fileURLWithPath: path).appendingPathComponent(key)
            self.onRenameFile?(prevURL.path, nextURL.path)
        }
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
        guard let path = item as? String else { return false }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return isDir.boolValue
        } else {
            return false
        }
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
}

// MARK: - FileTreeRowView

private class FileTreeRowView: NSTableRowView {
    public var drawsContextMenuOutline = false {
        didSet {
            if drawsContextMenuOutline != oldValue {
                needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if drawsContextMenuOutline {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3)
            path.lineWidth = 2
            if #available(OSX 10.14, *) {
                NSColor.controlAccentColor.set()
            } else {
                NSColor.selectedControlColor.set()
            }
            path.stroke()
        }
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

        return options
    }
}

// MARK: - NSOutlineViewDelegate

extension FileTree: NSOutlineViewDelegate {

    public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let rowView = FileTreeRowView()

        guard let path = item as? String else { return rowView }

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
}

// MARK: - NSMenuDelegate

extension FileTree: NSMenuDelegate {
    public func menuDidClose(_ menu: NSMenu) {
        if let contextMenuForPath = self.contextMenuForPath {
            self.contextMenuForPath = nil

            let row = outlineView.row(forItem: contextMenuForPath)

            if let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) as? FileTreeRowView {
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

                if newName != name {
                    let newPath = URL(fileURLWithPath: path)
                        .deletingLastPathComponent()
                        .appendingPathComponent(newName)
                        .path
                    do {
                        try FileManager.default.moveItem(atPath: path, toPath: newPath)
                    } catch {
                        Swift.print("Failed to rename \(path) to \(newPath)")
                    }
                }

                fileTree.endRenamingFile()
            }

            return view
        }

        return fileTree
    }
}
