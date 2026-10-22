import AppKit

struct CallAppearance {
    let title: String
    let symbol: String
    let color: NSColor
    static func forPhase(_ phase: String) -> CallAppearance {
        switch phase {
        case "listening": return .init(title:"Listening",symbol:"mic.fill",color:.systemGreen)
        case "permission": return .init(title:"Microphone…",symbol:"mic.badge.plus",color:.systemOrange)
        case "transcribing": return .init(title:"Recognizing…",symbol:"waveform",color:.systemOrange)
        case "thinking", "waiting", "generating": return .init(title:"Thinking…",symbol:"ellipsis.bubble.fill",color:.systemOrange)
        case "speaking": return .init(title:"Speaking",symbol:"waveform",color:.systemCyan)
        case "failed": return .init(title:"Unavailable",symbol:"phone.down.fill",color:.systemRed)
        case "paused", "cancelled": return .init(title:"Paused",symbol:"pause.circle.fill",color:.systemRed)
        default: return .init(title:"Connecting…",symbol:"phone.fill",color:.systemBlue)
        }
    }
}

final class CallStatusView: NSView {
    var onEnd: (() -> Void)?
    private let label = NSTextField(labelWithString:"")
    private let icon = NSImageView()
    private let meter = NSView()
    private let endButton = NSButton()
    var level: Double = 0 { didSet { meter.frame.size.width = CGFloat(max(0.06,min(1,level))) * bounds.width } }
    override init(frame: NSRect) {
        super.init(frame:frame)
        wantsLayer = true; layer?.cornerRadius = 10; layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
        icon.frame = NSRect(x:8,y:8,width:16,height:16); addSubview(icon)
        label.frame = NSRect(x:28,y:6,width:110,height:20)
        label.font = .systemFont(ofSize:11,weight:.semibold); label.textColor = .white; addSubview(label)
        endButton.frame = NSRect(x:140,y:4,width:26,height:24)
        endButton.image = NSImage(systemSymbolName:"phone.down.fill",accessibilityDescription:"End voice call")
        endButton.contentTintColor = .systemRed; endButton.isBordered = false
        endButton.target = self; endButton.action = #selector(endCall)
        endButton.toolTip = "End voice call"; endButton.setAccessibilityLabel("End voice call")
        addSubview(endButton)
        meter.frame = NSRect(x:0,y:0,width:8,height:3); meter.wantsLayer = true; addSubview(meter)
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func endCall() { onEnd?() }
    func update(_ phase: String, reason: String = "") {
        isHidden = phase == "idle"
        let appearance = CallAppearance.forPhase(phase)
        label.stringValue = "☎  " + appearance.title
        icon.image = NSImage(systemSymbolName:appearance.symbol,accessibilityDescription:appearance.title)
        icon.contentTintColor = appearance.color
        meter.layer?.backgroundColor = appearance.color.cgColor
        layer?.borderColor = appearance.color.cgColor; layer?.borderWidth = 1.5
        setAccessibilityLabel("Voice call: " + appearance.title)
        toolTip = reason.isEmpty ? "Voice call: \(appearance.title). Double-click the character to end a desktop call." : reason
        level = phase == "listening" || phase == "speaking" ? level : 0.15
    }
}

func exportCallStatusPreview(to url: URL) throws {
    _ = NSApplication.shared
    let phases = ["connecting","listening","transcribing","thinking","speaking","paused"]
    let root = NSView(frame:NSRect(x:0,y:0,width:350,height:270))
    for (index,phase) in phases.enumerated() {
        let badge = CallStatusView(frame:NSRect(x:12,y:CGFloat(5-index)*43+8,width:172,height:32))
        root.addSubview(badge); badge.update(phase); badge.level = phase == "listening" ? 0.65 : 0.3
        let note = NSTextField(labelWithString:phase)
        note.frame = NSRect(x:196,y:badge.frame.minY+7,width:146,height:18)
        note.font = .systemFont(ofSize:12); root.addSubview(note)
    }
    guard let bitmap = root.bitmapImageRepForCachingDisplay(in:root.bounds) else { throw NSError(domain:"WhaleCallPreview",code:1) }
    root.cacheDisplay(in:root.bounds,to:bitmap)
    guard let data = bitmap.representation(using:.png,properties:[:]) else { throw NSError(domain:"WhaleCallPreview",code:2) }
    try data.write(to:url)
}

final class CharacterClicks {
    private var pending: DispatchWorkItem?
    func cancel() { pending?.cancel(); pending = nil }
    func single(after delay: Double, action: @escaping () -> Void) {
        cancel(); let item = DispatchWorkItem(block:action); pending = item
        DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:item)
    }
    deinit { cancel() }
}
