//
//  FileTree.swift
//  LonaStudio
//
//  Created by Devin Abbott on 8/17/18.
//  Copyright © 2018 Devin Abbott. All rights reserved.
//

import AppKit
import Foundation

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

            addTableColumn(column)
            outlineTableColumn = column
            columnAutoresizingStyle = .uniformColumnAutoresizingStyle

            focusRingType = .none
            rowSizeStyle = .custom
            headerView = nil

            // registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: "component.element")])
        }
    }
}

public class FileTree: NSBox {

    // MARK: Lifecycle

    public init(rootPath: String? = nil) {
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

        initialized = true
    }

    // MARK: Public

    public var sortFiles: ((String, String) -> Bool)? { didSet { update() } }

    public var filterFiles: ((String) -> Bool)? { didSet { update() } }

    public var showHiddenFiles = false { didSet { update() } }

    public var rootPath = "/" {
        didSet {
            if !initialized { return }

            outlineView.autosaveName = autosaveName

            update()
        }
    }

    // MARK: Private

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

    func setUpViews() {
        boxType = .custom
        borderType = .lineBorder
        contentViewMargins = .zero
        borderWidth = 0

        fillColor = .clear

        outlineView.autosaveExpandedItems = true
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.autosaveName = autosaveName

        outlineView.reloadData()

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.addSubview(outlineView)
        scrollView.documentView = outlineView

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

let rowHeight: CGFloat = 40
let thumbnailSize: CGFloat = 36
let thumbnailMargin: CGFloat = 10

private class FileTreeCellView: NSTableCellView {

    public var onChangeBackgroundStyle: ((NSView.BackgroundStyle) -> Void)?

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { onChangeBackgroundStyle?(backgroundStyle) }
    }
}

extension FileTree: NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let path = item as? String else { return NSView() }

        let view = FileTreeCellView(frame: NSRect(x: 0, y: 0, width: 200, height: rowHeight))
        let textView = NSTextField(labelWithString: URL(fileURLWithPath: path).lastPathComponent)
        textView.frame.origin.y = (rowHeight - textView.intrinsicContentSize.height) / 2
        textView.frame.origin.x = thumbnailSize + (thumbnailMargin * 2) - 4
        let image = NSWorkspace.shared.icon(forFile: path)
        image.resizingMode = .stretch
        image.size = NSSize(width: thumbnailSize, height: thumbnailSize)
        let imageView = NSImageView(image: image)
        imageView.frame = NSRect(x: thumbnailMargin, y: (rowHeight - thumbnailSize) / 2, width: thumbnailSize, height: thumbnailSize)

        view.addSubview(textView)
        view.addSubview(imageView)

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

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return rowHeight
    }
}

