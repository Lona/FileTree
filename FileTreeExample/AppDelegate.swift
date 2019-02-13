//
//  AppDelegate.swift
//  FileTree
//
//  Created by Devin Abbott on 8/17/18.
//  Copyright © 2018 BitDisco, Inc. All rights reserved.
//

import Cocoa
import FileTree

private func isDirectory(path: FileTree.Path) -> Bool {
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
        return isDir.boolValue
    } else {
        return false
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!

    var fileTree = FileTree.makeDefaultTree(rootPath: "/Users/devinabbott/Projects/FileTree")

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        window.contentView = contentView

        contentView.addSubview(fileTree)

        contentView.topAnchor.constraint(equalTo: fileTree.topAnchor).isActive = true
        contentView.bottomAnchor.constraint(equalTo: fileTree.bottomAnchor).isActive = true
        contentView.leadingAnchor.constraint(equalTo: fileTree.leadingAnchor).isActive = true
        contentView.trailingAnchor.constraint(equalTo: fileTree.trailingAnchor).isActive = true

        fileTree.onAction = { path in
            Swift.print("Click \(path)")
        }

        fileTree.onSelect = { path in
            Swift.print("Selected \(path)")
        }

        fileTree.onRenameFile = { oldPath, newPath, options in
            let ownEvent = options.contains(.ownEvent)
            Swift.print("Renamed \(oldPath) to \(newPath) [\(ownEvent)]")
        }

        fileTree.onCreateFile = { path, options in
            let ownEvent = options.contains(.ownEvent)
            Swift.print("Create file \(path) [\(ownEvent)]")
        }

        fileTree.onDeleteFile = { path, options in
            let ownEvent = options.contains(.ownEvent)
            Swift.print("Delete file \(path) [\(ownEvent)]")
        }

        fileTree.menuForFile = { [unowned self] path in
            let menu = NSMenu(title: "Menu")

            menu.addItem(withTitle: "Reveal in Finder", action: #selector(self.handleRevealInFinder), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())

            if isDirectory(path: path) {
                menu.addItem(withTitle: "New File", action: #selector(self.handleNewFile), keyEquivalent: "")
                menu.addItem(withTitle: "New Directory", action: #selector(self.handleNewDirectory), keyEquivalent: "")
                menu.addItem(NSMenuItem.separator())
            }

            if path != self.fileTree.rootPath {
                menu.addItem(withTitle: "Rename", action: #selector(self.handleRenameFile), keyEquivalent: "")
                menu.addItem(withTitle: "Delete", action: #selector(self.handleDeleteFile), keyEquivalent: "")
            }

            menu.items.forEach { item in item.representedObject = path }

            return menu
        }
    }

    @objc func handleRevealInFinder(_ sender: AnyObject) {
        guard let sender = sender as? NSMenuItem,
            let path = sender.representedObject as? FileTree.Path else { return }

        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: parentPath)
    }

    func promptForName(messageText: String, placeholderText: String) -> String? {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let textView = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 20))
        textView.stringValue = ""
        textView.placeholderString = placeholderText
        alert.accessoryView = textView
        alert.window.initialFirstResponder = textView

        alert.layout()

        let response = alert.runModal()

        if response == NSApplication.ModalResponse.alertFirstButtonReturn {
            return textView.stringValue
        } else {
            return nil
        }
    }

    @objc func handleNewFile(_ sender: AnyObject) {
        guard let sender = sender as? NSMenuItem, let path = sender.representedObject as? FileTree.Path else { return }

        guard let newFileName = promptForName(
            messageText: "Enter a new file name",
            placeholderText: "File name") else { return }

        let newFilePath =  path + "/" + newFileName

        Swift.print("New file \(newFilePath)")

//        fileTree.createFile(atPath: newFilePath, contents: Data())

        FileManager.default.createFile(atPath: newFilePath, contents: Data(), attributes: nil)
//
//        fileTree.reloadData()
    }

    @objc func handleNewDirectory(_ sender: AnyObject) {
        guard let sender = sender as? NSMenuItem, let path = sender.representedObject as? FileTree.Path else { return }

        guard let newFileName = promptForName(
            messageText: "Enter a new directory name",
            placeholderText: "Directory name") else { return }

        let newFilePath =  path + "/" + newFileName

        Swift.print("New directory \(newFilePath)")

        do {
            try FileManager.default.createDirectory(
                atPath: newFilePath,
                withIntermediateDirectories: true,
                attributes: nil)

            fileTree.reloadData()
        } catch {
            Swift.print("Failed to create directory \(newFileName)")
        }

    }

    @objc func handleRenameFile(_ sender: AnyObject) {
        guard let sender = sender as? NSMenuItem, let path = sender.representedObject as? FileTree.Path else { return }

        if let cellView = fileTree.beginRenamingFile(atPath: path) as? FileTree.DefaultCellView {
            cellView.onBeginRenaming?()
        }
    }

    @objc func handleDeleteFile(_ sender: AnyObject) {
        guard let sender = sender as? NSMenuItem, let path = sender.representedObject as? FileTree.Path else { return }

        let alert = NSAlert()
        alert.messageText = "Are you sure you want to delete \(path)?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == NSApplication.ModalResponse.alertFirstButtonReturn {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                Swift.print("Failed to delete \(path)")
            }
        }
    }

    @objc func handleMenuItem() {
        Swift.print("Handle menu item")
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

