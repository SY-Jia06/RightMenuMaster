import Cocoa

final class MenuBuilder {

    func buildSeparator() -> NSMenuItem {
        NSMenuItem.separator()
    }

    func buildDisabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func buildItem(title: String, action: Selector, target: AnyObject, represented object: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = object
        return item
    }
}
