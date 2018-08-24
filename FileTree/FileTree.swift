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

private extension NSTableColumn {
    convenience init(title: String, resizingMask: ResizingOptions = .autoresizingMask) {
        self.init(identifier: NSUserInterfaceItemIdentifier(rawValue: title))
        self.title = title
        self.resizingMask = resizingMask
    }
}

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

    public var defaultRowHeight: CGFloat = 28.0 { didSet { update() } }

    public var defaultThumbnailSize: CGFloat = 24.0 { didSet { update() } }

    public var defaultThumbnailMargin: CGFloat = 4.0 { didSet { update() } }

    public var defaultFont: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular))

    /** Determine the name to display based on the file's full path. */
    public var displayNameForFile: ((Path) -> Name)? { didSet { update() } }

    /** Sets the height of the row. If not provided, height is set to `defaultRowHeight`. */
    public var rowHeightForFile: ((Path) -> CGFloat)? { didSet { update() } }

    public var rowViewForFile: ((Path) -> NSView)? { didSet { update() } }

    public var imageForFile: ((Path, NSSize) -> NSImage)? { didSet { update() } }

    public var sortFiles: ((Name, Name) -> Bool)? { didSet { update() } }

    public var filterFiles: ((Name) -> Bool)? { didSet { update() } }

    public var showHiddenFiles = false { didSet { update() } }

    public var rootPath = "/" {
        didSet {
            if !initialized { return }

            outlineView.autosaveName = autosaveName

            setUpWitness()

            update()
        }
    }

    // MARK: Private

    private var witness: Witness?

    private var initialized = false
    private var outlineView = NSOutlineView(style: .singleColumn)
    private var scrollView = NSScrollView(frame: .zero)

    private var autosaveName: NSTableView.AutosaveName {
        return NSTableView.AutosaveName(rawValue: rootPath)
    }

    private func contentsOfDirectory(atPath path: String) -> [String] {
        var children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []

        if let filterFiles = filterFiles {
            children = children.filter(filterFiles)
        } else if !showHiddenFiles {
            children = children.filter { name in
                return !name.starts(with: ".")
            }
        }

        if let sortComparator = sortFiles {
            children = children.sorted(by: sortComparator)
        } else {
            children = children.sorted()
        }

        return children
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

extension FileTree {
    private func setUpWitness() {
//        Swift.print("Watching events at", rootPath)

        self.witness = Witness(paths: [rootPath], flags: .FileEvents, latency: 0) { events in
//            print("file system events received: \(events)")
            DispatchQueue.main.async {
                events.forEach { event in
                    if event.flags.contains(.ItemCreated) {
//                        Swift.print("Create event", event)
                        self.createFile(atPath: event.path)
                    } else if event.flags.contains(.ItemRemoved) {
//                        Swift.print("Delete event", event)
                        self.deleteFile(atPath: event.path)
                    }
                }
            }
        }
    }

    private func deleteFile(atPath path: Path) {
        onDeleteFile?(path)

//        let url = URL(fileURLWithPath: path)

//        Swift.print("Delete file", url.lastPathComponent)

        guard let parent = outlineView.parent(forItem: path) else { return }

        outlineView.reloadItem(parent, reloadChildren: true)
        outlineView.sizeToFit()

    }

    private func createFile(atPath path: Path) {
        onCreateFile?(path)

        let url = URL(fileURLWithPath: path)

//        Swift.print("Create file", url.lastPathComponent)

        let parentUrl = url.deletingLastPathComponent()
        let parentPath = parentUrl.path

//        Swift.print("Try to find \(parentPath)")

        guard let parent = first(where: { ($0 as? String) == parentPath }) else { return }

        outlineView.reloadItem(parent, reloadChildren: true)
        outlineView.sizeToFit()
    }

    private func first(where: (Any) -> Bool) -> Any? {
        func firstChild(_ item: Any, where: (Any) -> Bool) -> Any? {
            if `where`(item) { return item }

            let childCount = outlineView.numberOfChildren(ofItem: item)

            for i in 0..<childCount {
                if
                    let child = outlineView.child(i, ofItem: item),
                    let found = firstChild(child, where: `where`) {
                    return found
                }
            }

            return nil
        }

        guard let root = outlineView.child(0, ofItem: nil) else { return nil }

        return firstChild(root, where: `where`)
    }
}

extension FileTree: NSOutlineViewDataSource {

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return 1 }
        guard let path = item as? String else { return 0 }
        return contentsOfDirectory(atPath: path).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return rootPath }
        let path = item as! String
        return path + "/" + contentsOfDirectory(atPath: path)[index]
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

private class FileTreeCellView: NSTableCellView {

    public var onChangeBackgroundStyle: ((NSView.BackgroundStyle) -> Void)?

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { onChangeBackgroundStyle?(backgroundStyle) }
    }
}

extension FileTree: NSOutlineViewDelegate {

    private func rowHeightForFile(atPath path: String) -> CGFloat {
        return rowHeightForFile?(path) ?? defaultRowHeight
    }

    private func imageForFile(atPath path: String, size: NSSize) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: size.width, height: size.height)
        return image
    }

    private func rowViewForFile(atPath path: String) -> NSView {
        let rowHeight = rowHeightForFile(atPath: path)
        let thumbnailSize = defaultThumbnailSize
        let thumbnailMargin = defaultThumbnailMargin
        let name = displayNameForFile?(path) ?? URL(fileURLWithPath: path).lastPathComponent

        let view = FileTreeCellView()

        let textView = NSTextField(labelWithString: name)
        let imageSize = NSSize(width: thumbnailSize, height: thumbnailSize)
        let imageView = NSImageView(image: imageForFile?(path, imageSize) ?? imageForFile(atPath: path, size: imageSize))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(x: thumbnailMargin, y: (rowHeight - thumbnailSize) / 2, width: thumbnailSize, height: thumbnailSize)

        view.addSubview(textView)
        view.addSubview(imageView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: thumbnailMargin).isActive = true
        imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: thumbnailMargin * 2 + thumbnailSize).isActive = true
        textView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        textView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        textView.font = defaultFont
        textView.maximumNumberOfLines = 1
        textView.lineBreakMode = .byTruncatingMiddle

        view.onChangeBackgroundStyle = { style in
            switch style {
            case .light:
                textView.textColor = .black
            case .dark:
                textView.textColor = .white
            default:
                break
            }
        }

        return view
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let path = item as? String else { return NSView() }

        return rowViewForFile?(path) ?? rowViewForFile(atPath: path)
    }

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let path = item as? String else { return defaultRowHeight }

        return rowHeightForFile(atPath: path)
    }
}

