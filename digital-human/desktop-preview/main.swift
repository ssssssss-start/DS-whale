import AppKit
import SpriteKit

final class CharacterView: SKView {
    var onScale: ((CGFloat) -> Void)?
    var characterScene: CharacterScene { scene as! CharacterScene }
    private var downPoint: CGPoint?
    private var downOrigin = CGPoint.zero
    private var dragging = false
    private var patted = false
    private var longPress: Timer?
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        downPoint = NSEvent.mouseLocation
        downOrigin = window?.frame.origin ?? .zero
        dragging = false
        patted = false
        let point = characterScene.convertPoint(fromView: convert(event.locationInWindow, from: nil))
        if characterScene.isHead(point) {
            longPress = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                guard let self, self.downPoint != nil, !self.dragging else { return }
                self.patted = true
                self.characterScene.request(.headpat)
            }
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x, dy = current.y - start.y
        if hypot(dx, dy) > 5 { dragging = true; longPress?.invalidate() }
        if dragging { window?.setFrameOrigin(CGPoint(x: downOrigin.x + dx, y: downOrigin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        longPress?.invalidate()
        longPress = nil
        if downPoint != nil && !dragging && !patted { characterScene.request(.poke) }
        downPoint = nil
    }
    override func scrollWheel(with event: NSEvent) {
        guard !event.momentumPhase.contains(.changed) else { return }
        let delta = max(-10, min(10, event.scrollingDeltaY))
        onScale?(delta * (event.hasPreciseScrollingDeltas ? 0.003 : 0.025))
    }
    deinit { longPress?.invalidate() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    var window: NSPanel!
    var statusItem: NSStatusItem!
    var characterScene: CharacterScene!
    let actions = NSMenu()
    let voice = VoicePipeline()
    let voiceChoices = NSMenu()
    var voiceStatusItem: NSMenuItem!
    var proactiveItem: NSMenuItem!
    var companionItem: NSMenuItem!
    var followItem: NSMenuItem!
    var dndItem: NSMenuItem!
    var hostStatusItem: NSMenuItem!
    var inbox: [String: Any] = [:]
    var messagesWindow: NSWindow?
    var messagesText: NSTextView?
    var workspaceObservers: [NSObjectProtocol] = []
    var soundItem: NSMenuItem!
    var motionItem: NSMenuItem!
    var scale: CGFloat = 1
    let baseSize = NSSize(width: 190, height: 234)

    func applicationDidFinishLaunching(_ notification: Notification) {
        for instance in NSRunningApplication.runningApplications(withBundleIdentifier: "local.whale.companion.preview")
            where instance.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            instance.terminate()
        }
        guard let url = Bundle.main.url(forResource: "wave-reference-full", withExtension: "png"),
              let artwork = FullBodyFrames(url: url) else {
            let alert = NSAlert()
            alert.messageText = "Character artwork is missing. Please rebuild the app."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let savedScale = UserDefaults.standard.double(forKey: "characterScale")
        scale = savedScale > 0 ? CGFloat(min(2, max(0.5, savedScale))) : 1
        let size = NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
        var frame = NSRect(x: screen.maxX - size.width - 24, y: screen.minY + 24, width: size.width, height: size.height)
        if UserDefaults.standard.object(forKey: "windowX") != nil {
            let saved = CGPoint(x: UserDefaults.standard.double(forKey: "windowX"), y: UserDefaults.standard.double(forKey: "windowY"))
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(CGRect(origin: saved, size: size)) }) { frame.origin = saved }
        }
        window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Whale Companion"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        let view = CharacterView(frame: NSRect(origin: .zero, size: frame.size))
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = false
        view.toolTip = "Click: poke · Hold head: head pat · Drag: move · Scroll: resize"
        view.setAccessibilityLabel("Whale character")
        characterScene = CharacterScene(size: frame.size, frames: artwork.textures)
        view.presentScene(characterScene)
        view.onScale = { [weak self] delta in guard let self else { return }; self.resize(to: self.scale + delta) }
        characterScene.onInteraction = { [weak self] in self?.voice.cancel() }
        voice.onLevel = { [weak self] level in self?.characterScene.speakingLevel = level }
        voice.onStart = { [weak self] in self?.characterScene.beginSpeaking() }
        voice.onStatus = { [weak self] status in self?.voiceStatusItem?.title = status }
        voice.onTestFailure = { message in
            let alert = NSAlert()
            alert.messageText = "Doubao voice test failed"
            alert.informativeText = message + "\n\nUse the API Key from the Volcengine Doubao Voice console. Check that Speech TTS 2.0 is enabled and this voice is available. Choose Connect Doubao Voice… to paste the key again."
            alert.addButton(withTitle:"OK")
            NSApp.activate(ignoringOtherApps:true); alert.runModal()
        }
        voice.muted = characterScene.feedback.muted
        voice.selectVoice(UserDefaults.standard.string(forKey:"doubaoVoiceID") ?? DoubaoVoice.defaultID)
        buildMenu()
        reloadVoiceConfig(showResult:false)
        setupProactive()
        voice.start()
        view.menu = actions
        window.contentView = view
        let close = NSButton(frame: NSRect(x: frame.width - 26, y: frame.height - 25, width: 22, height: 22))
        close.title = "×"
        close.isBordered = false
        close.font = NSFont.systemFont(ofSize: 18)
        close.toolTip = "Quit Whale Companion"
        close.target = self
        close.action = #selector(quit)
        close.autoresizingMask = [.minXMargin, .minYMargin]
        view.addSubview(close)
        let more = NSButton(frame: NSRect(x: frame.width - 49, y: frame.height - 25, width: 22, height: 22))
        more.title = "⋯"
        more.isBordered = false
        more.font = NSFont.systemFont(ofSize: 18)
        more.setAccessibilityLabel("Whale actions")
        more.toolTip = "Actions and settings"
        more.target = self
        more.action = #selector(openActions(_:))
        more.autoresizingMask = [.minXMargin, .minYMargin]
        view.addSubview(more)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Whale"
        statusItem.menu = actions
        window.orderFrontRegardless()
        if CommandLine.arguments.contains("--voice-connect") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.voice.connect() }
        }
        if CommandLine.arguments.contains("--demo") {
            for (index, behavior) in [Behavior.greeting, .headpat, .poke].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index * 6 + 2)) { [weak self] in self?.characterScene.request(behavior) }
            }
        }
        if CommandLine.arguments.contains("--wave-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.characterScene.request(.greeting) }
        }
    }
    func buildMenu() {
        actions.delegate = self
        addProactiveMenu()
        actions.addItem(withTitle: "Connect Doubao Voice…", action: #selector(connectVoice), keyEquivalent: "")
        actions.addItem(withTitle: "Reload Voice Config…", action: #selector(reloadVoiceConfigMenu), keyEquivalent: "")
        let voices = actions.addItem(withTitle:"Doubao Voice",action:nil,keyEquivalent:"")
        for choice in DoubaoVoice.choices {
            let item = voiceChoices.addItem(withTitle:choice.title,action:#selector(selectDoubaoVoice(_:)),keyEquivalent:"")
            item.representedObject = choice.id; item.target = self
        }
        voices.submenu = voiceChoices
        actions.addItem(withTitle:"Test Voice (Uses API)",action:#selector(testVoice),keyEquivalent:"")
        actions.addItem(withTitle:"Disconnect Voice",action:#selector(disconnectVoice),keyEquivalent:"")
        actions.addItem(withTitle: "Stop Speaking", action: #selector(stopSpeaking), keyEquivalent: "")
        voiceStatusItem = actions.addItem(withTitle: voice.status, action: nil, keyEquivalent: "")
        actions.addItem(.separator())
        actions.addItem(withTitle: "Say Hello", action: #selector(sayHello), keyEquivalent: "")
        actions.addItem(withTitle: "Poke", action: #selector(poke), keyEquivalent: "")
        actions.addItem(withTitle: "Head Pat", action: #selector(headPat), keyEquivalent: "")
        let expressions = NSMenu(title:"Expressions")
        for behavior in Behavior.emotions {
            let item = expressions.addItem(withTitle:behavior.title,action:#selector(showExpression(_:)),keyEquivalent:"")
            item.representedObject = behavior.rawValue; item.target = self
        }
        let expressionItem = actions.addItem(withTitle:"Expressions",action:nil,keyEquivalent:"")
        expressionItem.submenu = expressions
        actions.addItem(.separator())
        soundItem = actions.addItem(withTitle: "Sound", action: #selector(toggleSound), keyEquivalent: "")
        motionItem = actions.addItem(withTitle: "Idle Motion", action: #selector(toggleMotion), keyEquivalent: "")
        actions.addItem(.separator())
        for percent in [50, 75, 100, 125, 150, 200] {
            let item = actions.addItem(withTitle: percent == 100 ? "Size: 100% (Default)" : "Size: \(percent)%", action: #selector(selectSize(_:)), keyEquivalent: "")
            item.tag = percent
        }
        actions.addItem(.separator())
        actions.addItem(withTitle: "Show Whale", action: #selector(showWhale), keyEquivalent: "")
        actions.addItem(withTitle: "Hide Whale", action: #selector(hideWhale), keyEquivalent: "")
        actions.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        for item in actions.items { item.target = self }
    }
    func menuWillOpen(_ menu: NSMenu) {
        updateProactiveMenu()
        soundItem.state = characterScene.feedback.muted ? .off : .on
        motionItem.state = characterScene.idleMotion ? .on : .off
        for item in menu.items where item.tag > 0 { item.state = abs(CGFloat(item.tag) / 100 - scale) < 0.01 ? .on : .off }
        for item in voiceChoices.items { item.state = item.representedObject as? String == voice.selectedVoice ? .on : .off }
    }
    func resize(to requested: CGFloat) {
        scale = min(2, max(0.5, requested))
        let size = NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
        let old = window.frame
        let screen = window.screen?.visibleFrame ?? old
        let x = min(max(old.midX - size.width / 2, screen.minX), screen.maxX - size.width)
        let y = min(max(old.minY, screen.minY), screen.maxY - size.height)
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        UserDefaults.standard.set(Double(scale), forKey: "characterScale")
    }
    func windowDidMove(_ notification: Notification) {
        UserDefaults.standard.set(window.frame.minX, forKey: "windowX")
        UserDefaults.standard.set(window.frame.minY, forKey: "windowY")
    }
    @objc func openActions(_ sender: NSButton) { actions.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.height), in: sender) }
    @objc func connectVoice() { voice.connect() }
    @objc func reloadVoiceConfigMenu() { reloadVoiceConfig(showResult:true) }
    func reloadVoiceConfig(showResult: Bool) {
        var message: String?
        do {
            if try !voice.loadVoiceConfig() {
                if showResult { message = "Fill in doubao_api_key in voice-config.local.json, then choose Reload Voice Config again." }
            }
        } catch {
            voiceStatusItem.title = "Voice config could not be loaded"
            message = (error as? VoiceConfigError)?.message ?? "Cannot load voice config."
        }
        if showResult, let message {
            let alert = NSAlert()
            alert.messageText = "Voice Config"
            alert.informativeText = message + "\n\n" + VoiceConfig.url.path
            alert.addButton(withTitle:"OK")
            NSApp.activate(ignoringOtherApps:true); alert.runModal()
        }
    }
    @objc func testVoice() { voice.testVoice() }
    @objc func disconnectVoice() { voice.disconnect() }
    @objc func selectDoubaoVoice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        voice.selectVoice(id); UserDefaults.standard.set(id,forKey:"doubaoVoiceID")
    }
    @objc func stopSpeaking() { voice.stopAll() }
    @objc func sayHello() { characterScene.request(.greeting) }
    @objc func poke() { characterScene.request(.poke) }
    @objc func headPat() { characterScene.request(.headpat) }
    @objc func showExpression(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let behavior = Behavior(rawValue:raw), behavior.isEmotion else { return }
        settings.interact(); characterScene.request(behavior)
    }
    @objc func toggleSound() { characterScene.feedback.muted.toggle(); voice.muted = characterScene.feedback.muted; settings.muted = characterScene.feedback.muted }
    @objc func toggleMotion() {
        characterScene.idleMotion.toggle()
        UserDefaults.standard.set(!characterScene.idleMotion, forKey: "idleMotionDisabled")
    }
    @objc func selectSize(_ sender: NSMenuItem) { resize(to: CGFloat(sender.tag) / 100) }
    @objc func showWhale() { settings.visible = true; settings.interact(); characterScene.resume(); window.orderFrontRegardless() }
    @objc func hideWhale() { settings.visible = false; voice.stopAll(); characterScene.suspend(); window.orderOut(nil) }
    @objc func quit() { voice.stopAll(); characterScene.feedback.stop(); NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--self-test") {
    runInteractionChecks()
    runEmotionChecks()
    runWaveChecks()
    runTailChecks()
    runProactiveSettingsChecks()
    runVoicePolicyChecks()
    runVoiceStreamChecks()
    runVoiceConfigChecks()
    runDoubaoChecks()
} else if CommandLine.arguments.contains("--ipc-self-test") {
    runVoiceSocketChecks()
} else if CommandLine.arguments.contains("--pcm-audio-check") {
    _ = NSApplication.shared
    try runPCMAudioCheck()
} else if let index = CommandLine.arguments.firstIndex(of: "--export-tail"), CommandLine.arguments.count > index + 1 {
    _ = NSApplication.shared
    do { try exportTailPreview(to:URL(fileURLWithPath:CommandLine.arguments[index+1])) }
    catch { print("Tail preview failed: \(error)"); exit(1) }
} else if let index = CommandLine.arguments.firstIndex(of: "--export-wave"), CommandLine.arguments.count > index + 1 {
    _ = NSApplication.shared
    do { try exportWavePreview(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
    catch { print("Preview export failed: \(error.localizedDescription)"); exit(1) }
} else if let index = CommandLine.arguments.firstIndex(of:"--export-emotions"), CommandLine.arguments.count > index + 1 {
    _ = NSApplication.shared
    do { try exportExpressionPreviews(to:URL(fileURLWithPath:CommandLine.arguments[index + 1]),emotionsOnly:true) }
    catch { print("Emotion preview failed: \(error.localizedDescription)"); exit(1) }
} else if let index = CommandLine.arguments.firstIndex(of:"--export-expressions"), CommandLine.arguments.count > index + 1 {
    _ = NSApplication.shared
    do { try exportExpressionPreviews(to:URL(fileURLWithPath:CommandLine.arguments[index + 1])) }
    catch { print("Expression preview failed"); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
