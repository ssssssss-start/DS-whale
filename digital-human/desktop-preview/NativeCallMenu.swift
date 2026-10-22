import AppKit

extension AppDelegate {
    func setupNativeCall(in view: CharacterView) {
        let panel = NSPanel(contentRect:callBadge.bounds,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.contentView = callBadge
        callStatusWindow = panel
        window.addChildWindow(panel,ordered:.above); panel.orderOut(nil)
        callBadge.onEnd = { [weak self] in
            guard let self else { return }
            if self.nativeCall.isOpen { self.nativeCall.end() } else { self.voice.endVoiceCall(); self.showCallStatus("idle") }
        }
        nativeCall.send = { [weak self] in self?.voice.sendNative($0) }
        voice.onNativeMessage = { [weak self] in self?.nativeCall.receive($0) }
        voice.onHeartbeat = { [weak self] in
            guard let self else { return }
            if self.nativeCall.isOpen && (!self.settings.active || !self.settings.visible || self.settings.muted) { self.nativeCall.end() }
            self.nativeCall.tick()
        }
        nativeCall.onLevel = { [weak self] in self?.callBadge.level = $0 }
        nativeCall.onChange = { [weak self] phase, reason in
            self?.showCallStatus(phase,reason:reason)
        }
        voice.onCallState = { [weak self] state in
            guard let self, !self.nativeCall.isOpen else { return }
            let phase = state["phase"] as? String ?? "idle"
            let display = phase == "ready" || phase == "finished" ? "listening" : phase == "closed" ? "idle" : phase
            self.showCallStatus(display)
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.nativeCall.end() })
        }
    }
    func showCallStatus(_ phase: String, reason: String = "") {
        callBadge.update(phase,reason:reason); characterScene.callPhase = phase
        positionCallStatus()
        if phase == "idle" || !settings.visible { callStatusWindow?.orderOut(nil) }
        else { callStatusWindow?.orderFrontRegardless() }
    }
    func positionCallStatus() {
        guard let panel = callStatusWindow, let window else { return }
        let screen = window.screen?.visibleFrame ?? window.frame
        let x = min(max(window.frame.midX-panel.frame.width/2,screen.minX),screen.maxX-panel.frame.width)
        let above = window.frame.maxY + 4
        let y = above + panel.frame.height <= screen.maxY ? above : max(screen.minY,window.frame.minY-panel.frame.height-4)
        panel.setFrameOrigin(NSPoint(x:x,y:y))
    }
    @objc func toggleNativeCall() {
        settings.interact(); characterScene.feedback.stop()
        nativeCall.toggle()
    }
    @objc func pauseNativeCall() { nativeCall.pause() }
    @objc func resumeNativeCall() { nativeCall.resume() }
}
