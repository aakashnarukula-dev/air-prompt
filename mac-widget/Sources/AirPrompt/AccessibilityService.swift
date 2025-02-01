import ApplicationServices
import AppKit

@MainActor
final class AccessibilityService {
    static let shared = AccessibilityService()

    private let directTextRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        "AXSearchField",
        kAXComboBoxRole as String
    ]
    private let editableAttribute = "AXEditable"
    private let webAreaRole = "AXWebArea"

    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return AXIsProcessTrusted()
    }

    func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    func paste() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return true
    }

    func focusedTextInput() -> Bool {
        let app = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return false }
        let axElement = unsafeDowncast(element, to: AXUIElement.self)
        return isEditableTextElement(axElement)
    }

    private func isEditableTextElement(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute as String, on: element)
        if let role, directTextRoles.contains(role) {
            return true
        }

        if boolAttribute(editableAttribute, on: element) == true {
            return true
        }

        // Many modern apps expose custom editors via a generic role while still
        // surfacing that the focused element accepts a mutable value/selection.
        if isAttributeSettable(kAXValueAttribute as String, on: element) {
            return true
        }

        if isAttributeSettable(kAXSelectedTextRangeAttribute as String, on: element) {
            return true
        }

        return role == webAreaRole && boolAttribute(kAXFocusedAttribute as String, on: element) == true
    }

    private func stringAttribute(_ name: String, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func boolAttribute(_ name: String, on element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private func isAttributeSettable(_ name: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, name as CFString, &settable)
        return result == .success && settable.boolValue
    }
}
