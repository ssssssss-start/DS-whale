import AppKit

enum WhiteBrightnessSettings {
    // User-approved screen calibration, 2026-10-23. Saved adjustments take priority.
    static let defaultPercent = 94.0
    private static func read(_ key: String) -> Double {
        let value = (UserDefaults.standard.object(forKey:key) as? NSNumber)?.doubleValue ?? defaultPercent
        return value.isFinite ? max(50,min(100,value)) : defaultPercent
    }
    static var current: Double {
        get { read("whaleWhiteBrightness") }
        set { UserDefaults.standard.set(max(50,min(100,newValue)),forKey:"whaleWhiteBrightness") }
    }
    static var reference: Double {
        get { read("whaleWhiteBrightnessReference") }
        set { UserDefaults.standard.set(max(50,min(100,newValue)),forKey:"whaleWhiteBrightnessReference") }
    }
}

final class WhiteBrightnessPanel: NSPanel {
    private let slider = NSSlider(value:100,minValue:50,maxValue:100,target:nil,action:nil)
    private let valueLabel = NSTextField(labelWithString:"")
    private let referenceLabel = NSTextField(labelWithString:"")
    var onChange: ((Double) -> Void)?

    init() {
        super.init(contentRect:NSRect(x:0,y:0,width:360,height:210),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        title = "White Brightness"; isReleasedWhenClosed = false
        level = .floating; hidesOnDeactivate = false
        let content = contentView!
        let help = NSTextField(wrappingLabelWithString:"Adjust the apron, headband and other bright whites. Changes appear live and are saved automatically.")
        help.frame = NSRect(x:20,y:146,width:320,height:46); content.addSubview(help)
        slider.frame = NSRect(x:20,y:106,width:252,height:28)
        slider.isContinuous = true; slider.target = self; slider.action = #selector(adjust)
        slider.setAccessibilityLabel("White brightness percent")
        content.addSubview(slider)
        valueLabel.frame = NSRect(x:280,y:110,width:60,height:22)
        valueLabel.font = .monospacedDigitSystemFont(ofSize:14,weight:.medium); content.addSubview(valueLabel)
        referenceLabel.frame = NSRect(x:20,y:72,width:320,height:22)
        referenceLabel.textColor = .secondaryLabelColor; content.addSubview(referenceLabel)
        let restore = NSButton(title:"Restore Reference",target:self,action:#selector(restoreReference))
        restore.frame = NSRect(x:16,y:20,width:158,height:32); content.addSubview(restore)
        let save = NSButton(title:"Use as Reference",target:self,action:#selector(saveReference))
        save.frame = NSRect(x:180,y:20,width:164,height:32); content.addSubview(save)
        refresh()
    }
    func refresh() {
        slider.doubleValue = WhiteBrightnessSettings.current
        valueLabel.stringValue = "\(Int(slider.doubleValue.rounded()))%"
        referenceLabel.stringValue = "Saved reference: \(Int(WhiteBrightnessSettings.reference.rounded()))%"
    }
    @objc private func adjust() {
        let value = slider.doubleValue.rounded()
        WhiteBrightnessSettings.current = value
        valueLabel.stringValue = "\(Int(value))%"
        onChange?(value)
    }
    @objc private func saveReference() {
        WhiteBrightnessSettings.reference = WhiteBrightnessSettings.current
        refresh()
    }
    @objc private func restoreReference() {
        WhiteBrightnessSettings.current = WhiteBrightnessSettings.reference
        refresh(); onChange?(WhiteBrightnessSettings.current)
    }
}

extension AppDelegate {
    @objc func showWhiteBrightness() {
        guard characterScene.uses3D else {
            let alert = NSAlert(); alert.messageText = "Enable 3D Character first"
            alert.informativeText = "White brightness adjusts the 3D character. Choose 3D Character (Original Detail) in the actions menu."
            NSApp.activate(ignoringOtherApps:true); alert.runModal(); return
        }
        if brightnessPanel == nil {
            let panel = WhiteBrightnessPanel()
            panel.onChange = { [weak self] value in self?.characterScene.whale3D?.setWhiteBrightness(value) }
            panel.center(); brightnessPanel = panel
        }
        brightnessPanel?.refresh(); brightnessPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
}
