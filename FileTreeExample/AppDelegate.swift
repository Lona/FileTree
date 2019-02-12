//
//  AppDelegate.swift
//  FileTree
//
//  Created by Devin Abbott on 8/17/18.
//  Copyright © 2018 BitDisco, Inc. All rights reserved.
//

import Cocoa
import FileTree

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!

    var fileTree = FileTree(rootPath: "/Users/devinabbott/Projects/FileTree")

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

        fileTree.menuForFile = { path in
            Swift.print("Menu for \(path)")

            let menu = NSMenu(title: "Menu")

            menu.addItem(withTitle: "Item 1", action: #selector(self.handleMenuItem), keyEquivalent: "")
            menu.addItem(withTitle: "Item 2", action: #selector(self.handleMenuItem), keyEquivalent: "")

            return menu
        }
    }

    @objc func handleMenuItem() {
        Swift.print("Handle menu item")
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

