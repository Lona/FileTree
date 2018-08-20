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
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

