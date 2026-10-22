import AppKit

extension AppDelegate {
    var settings: ProactiveSettings { voice.proactiveSettings }
    func addProactiveMenu() {
        proactiveItem = actions.addItem(withTitle: "Proactive Voice", action: #selector(toggleProactive), keyEquivalent: "")
        companionItem = actions.addItem(withTitle: "Companion Check-ins", action: #selector(toggleCompanion), keyEquivalent: "")
        followItem = actions.addItem(withTitle: "Follow Next Conversation", action: #selector(followNext), keyEquivalent: "")
        actions.addItem(withTitle: "Stop Following", action: #selector(stopFollowing), keyEquivalent: "")
        dndItem = NSMenuItem(title: settings.dndTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (title, tag) in [("For 30 Minutes",30),("For 1 Hour",60),("Until Turned Off",-1),("Turn Off",0)] {
            let item = submenu.addItem(withTitle: title, action: #selector(setDND(_:)), keyEquivalent: "")
            item.tag = tag; item.target = self
        }
        dndItem.submenu = submenu; actions.addItem(dndItem)
        actions.addItem(withTitle: "Focus for 30 Minutes", action: #selector(focus), keyEquivalent: "")
        actions.addItem(withTitle: "Quiet Hours…", action: #selector(quietHours), keyEquivalent: "")
        actions.addItem(withTitle: "Recent Messages", action: #selector(recentMessages), keyEquivalent: "")
        hostStatusItem = actions.addItem(withTitle: "Waiting for proactive plugin", action: nil, keyEquivalent: "")
        actions.addItem(.separator())
    }
    func updateProactiveMenu() {
        proactiveItem.state = settings.proactive ? .on : .off
        companionItem.state = settings.companion ? .on : .off
        dndItem.title = settings.dndTitle
    }
    func setupProactive() {
        settings.onChange = { [weak self] in self?.voice.settingsChanged(); self?.updateProactiveMenu() }
        settings.muted = characterScene.feedback.muted
        characterScene.onInteraction = { [weak self] in
            self?.settings.active = true; self?.settings.interact(); self?.voice.stopAll()
        }
        voice.onInbox = { [weak self] inbox in
            self?.inbox = inbox
            self?.followItem.toolTip = nil
            if inbox["followNext"] as? Bool == true { self?.followItem.title = "Waiting for Next User Conversation…" }
            else if let session = inbox["followedSession"] as? String {
                let title = inbox["followedTitle"] as? String ?? String(session.suffix(16))
                self?.followItem.title = "Following: " + title
                self?.followItem.toolTip = session
            }
            else { self?.followItem.title = "Follow Next Conversation" }
            self?.refreshMessages()
        }
        voice.onHostStatus = { [weak self] status in self?.hostStatusItem.title = status }
        voice.onProactivePlayback = { [weak self] kind in
            guard let self, self.settings.reason == nil else { return }
            if kind == "task_complete" || kind == "reminder" {
                _ = self.characterScene.interaction.begin(.greeting, at: ProcessInfo.processInfo.systemUptime)
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.settings.active = false })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.settings.active = true })
    }
    @objc func toggleProactive() { settings.interact(); settings.proactive.toggle() }
    @objc func toggleCompanion() { settings.interact(); settings.companion.toggle() }
    @objc func followNext() { settings.interact(); voice.sendControl("follow_next") }
    @objc func stopFollowing() { voice.sendControl("unfollow") }
    @objc func focus() { settings.setDND(minutes: 30) }
    @objc func setDND(_ sender: NSMenuItem) { settings.setDND(minutes: sender.tag == -1 ? nil : sender.tag) }
    @objc func quietHours() {
        let alert = NSAlert()
        alert.messageText = "Quiet Hours"
        alert.informativeText = "Use local time HH:mm. Equal times disable quiet hours. This affects proactive voice; direct replies and global Sound stay independent."
        let view = NSStackView(); view.orientation = .vertical; view.spacing = 8
        func format(_ value: Int) -> String { String(format:"%02d:%02d",value/60,value%60) }
        let start = NSTextField(string: format(settings.quietStart)), end = NSTextField(string: format(settings.quietEnd))
        start.placeholderString = "Start (23:00)"; end.placeholderString = "End (09:00)"
        view.addArrangedSubview(start); view.addArrangedSubview(end); view.frame = NSRect(x:0,y:0,width:320,height:60)
        alert.accessoryView = view; alert.addButton(withTitle:"Save"); alert.addButton(withTitle:"Cancel")
        NSApp.activate(ignoringOtherApps:true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        func parse(_ text: String) -> Int? {
            let parts = text.split(separator:":"); guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
            return h * 60 + m
        }
        guard let a = parse(start.stringValue), let b = parse(end.stringValue) else {
            let error = NSAlert(); error.messageText = "Use valid times such as 23:00 and 09:00."; error.runModal(); return
        }
        settings.quietStart = a; settings.quietEnd = b
    }
    @objc func recentMessages() {
        if messagesWindow == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:560,height:420), styleMask:[.titled,.closable,.resizable], backing:.buffered, defer:false)
            window.title = "Whale — Recent Messages"; window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame:window.contentView!.bounds); scroll.hasVerticalScroller = true; scroll.autoresizingMask = [.width,.height]
            let text = NSTextView(frame:scroll.bounds); text.isEditable = false; text.isSelectable = true
            text.font = .systemFont(ofSize:14); text.textContainerInset = NSSize(width:16,height:16)
            text.autoresizingMask = [.width]; text.isVerticallyResizable = true; text.textContainer?.widthTracksTextView = true
            scroll.documentView = text; window.contentView?.addSubview(scroll)
            messagesWindow = window; messagesText = text; window.center()
        }
        refreshMessages(); messagesWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        for item in inbox["messages"] as? [[String:Any]] ?? [] where item["read"] as? Bool != true {
            if let id = item["id"] as? String { voice.sendControl("mark_read", id:id) }
        }
    }
    func refreshMessages() {
        guard let text = messagesText else { return }
        let items = inbox["messages"] as? [[String:Any]] ?? []
        text.string = items.isEmpty ? "No messages yet.\n\nFollow a conversation to receive task reports. Create explicit reminders using whale_create_reminder in the followed conversation. Companion Check-ins are optional." : items.map { item in
            let date = Date(timeIntervalSince1970:(item["at"] as? Double ?? 0)/1000)
            let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .short
            let origin = item["source"] as? String ?? "Whale Companion"
            return "\(formatter.string(from:date)) · \(item["kind"] as? String ?? "")\n\(item["text"] as? String ?? "")\nStatus: \(item["status"] as? String ?? "") · \(item["reason"] as? String ?? "")\nSource: \(origin)"
        }.joined(separator:"\n\n────────────────\n\n")
    }
}
