//
//  NSOutlineView+Dragging.swift
//  FileTree
//
//  Created by Devin Abbott on 2/13/19.
//  Copyright © 2019 BitDisco, Inc. All rights reserved.
//

import AppKit

enum DropAcceptanceCategory<Element> {
    case into(parent: Element, at: Int?)
    case intoContainer(at: Int?)
    case intoDescendant
}

extension NSOutlineView {
    func shouldAccept<Element>(
        dropping item: Element,
        relativeTo: Element?,
        at proposedIndex: Int,
        isEqual: @escaping (Element, Element) -> Bool
        ) -> DropAcceptanceCategory<Element> {

        let targetIndex: Int? = proposedIndex == -1 ? nil : proposedIndex

        guard let relativeTo = relativeTo else {
            return DropAcceptanceCategory.intoContainer(at: targetIndex)
        }

        func isDescendant(_ descendant: Element, of ancestor: Element) -> Bool {
            var parentItem: Element? = descendant

            while parentItem != nil {
                if isEqual(parentItem!, ancestor) {
                    return true
                }
                parentItem = parent(forItem: parentItem!) as? Element
            }

            return false
        }

        if isDescendant(relativeTo, of: item) {
            return DropAcceptanceCategory.intoDescendant
        }

        return DropAcceptanceCategory.into(parent: relativeTo, at: targetIndex)
    }

    func relativePosition<Element>(
        for element: Element,
        isEqual: @escaping (Element, Element) -> Bool
        ) -> (parent: Element?, index: Int) {
        if let parentItem = parent(forItem: element) as? Element {
            let childItemIndex = childIndex(forItem: element)
            return (parentItem, childItemIndex)
        } else {
            var topLevelIndexCount = 0
            for index in 0..<numberOfRows {
                if let other = item(atRow: index) as? Element, isEqual(other, element) {
                    return (nil, topLevelIndexCount)
                }

                if level(forRow: index) == 0 {
                    topLevelIndexCount += 1
                }
            }

            // Should never happen
            return (nil, row(forItem: element))
        }
    }

    // MARK: Equatable

    func shouldAccept<Element: Equatable>(
        dropping item: Element,
        relativeTo: Element?,
        at proposedIndex: Int
        ) -> DropAcceptanceCategory<Element> {
        return shouldAccept(dropping: item, relativeTo: relativeTo, at: proposedIndex) { a, b in a == b }
    }

    func relativePosition<Element: Equatable>(for element: Element) -> (parent: Element?, index: Int) {
        return relativePosition(for: element) { a, b in a == b }
    }
}
