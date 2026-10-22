import AppKit

final class VoiceKeyField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command, currentEditor() != nil else { return super.performKeyEquivalent(with:event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": pasteKey(nil); return true
        case "a": currentEditor()?.selectAll(nil); return true
        default: return super.performKeyEquivalent(with:event)
        }
    }
    @objc func pasteKey(_ sender: Any?) {
        window?.makeFirstResponder(self)
        currentEditor()?.paste(sender)
    }
}

final class VoiceKeyInput: NSView {
    let field = VoiceKeyField(frame:NSRect(x:0,y:2,width:292,height:24))
    init() {
        super.init(frame:NSRect(x:0,y:0,width:372,height:28))
        field.placeholderString = "Speech API Key · ⌘V to paste"
        field.setAccessibilityLabel("Speech API Key")
        addSubview(field)
        let paste = NSButton(title:"Paste",target:field,action:#selector(VoiceKeyField.pasteKey(_:)))
        paste.frame = NSRect(x:300,y:0,width:72,height:28)
        paste.toolTip = "Paste your copied key into the secure field"
        addSubview(paste)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
