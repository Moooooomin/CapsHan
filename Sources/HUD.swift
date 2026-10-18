import Cocoa

/// A small rounded popup at the bottom center of the screen, like the Caps Lock
/// indicator in Logitech Options+. It never takes focus or mouse clicks.
/// Theme, design, glass look, size and duration are read from Settings every time it is shown.
final class HUD {
    private struct Layout: Equatable {
        let style: HUDStyle
        let scale: CGFloat
    }

    private let baseSize = NSSize(width: 150, height: 112)
    private let panel: NSPanel
    private let content = NSView()
    private let stack: NSStackView
    private let glyphLabel = NSTextField(labelWithString: "")
    private let captionLabel = NSTextField(labelWithString: "")
    private var appliedLayout: Layout?
    private var glassView: NSView?
    private var generation = 0

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: baseSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.alphaValue = 0

        glyphLabel.textColor = .labelColor
        glyphLabel.alignment = .center
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.alignment = .center

        stack = NSStackView(views: [glyphLabel, captionLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    func show(glyph: String, caption: String) {
        applySettings()
        glyphLabel.stringValue = glyph
        captionLabel.stringValue = caption
        moveToActiveScreen()

        generation += 1
        let shownGeneration = generation
        let fade = Settings.hudFadeDuration
        panel.orderFrontRegardless()
        // Fading the whole window also fades the glass; fading only the content view
        // would leave the glass outline behind.
        animateAlpha(to: 1, duration: fade, timing: .easeOut)

        // The display time starts once the popup is fully visible.
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + Settings.hudDuration) { [weak self] in
            guard let self, self.generation == shownGeneration else { return }
            self.animateAlpha(to: 0, duration: fade, timing: .easeIn) { [weak self] in
                // A newer popup may have started while this one was fading out.
                guard let self, self.generation == shownGeneration else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func animateAlpha(to alpha: CGFloat, duration: TimeInterval,
                              timing: CAMediaTimingFunctionName, completion: (() -> Void)? = nil) {
        guard duration > 0 else {
            panel.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: timing)
            panel.animator().alphaValue = alpha
        }, completionHandler: completion)
    }

    // MARK: Appearance

    private func applySettings() {
        panel.appearance = Settings.hudTheme.appearance
        let layout = Layout(style: Settings.hudStyle, scale: CGFloat(Settings.hudScale))
        if layout != appliedLayout {
            rebuild(layout)
        }
        applyGlassLook()
    }

    /// Rebuilds the background when the design or size changes.
    private func rebuild(_ layout: Layout) {
        appliedLayout = layout
        let size = NSSize(width: baseSize.width * layout.scale, height: baseSize.height * layout.scale)
        let bounds = NSRect(origin: .zero, size: size)
        let cornerRadius = 24 * layout.scale
        panel.setContentSize(size)
        glyphLabel.font = .systemFont(ofSize: 48 * layout.scale, weight: .medium)
        captionLabel.font = .systemFont(ofSize: 13 * layout.scale, weight: .medium)
        stack.spacing = 2 * layout.scale

        content.removeFromSuperview()
        content.frame = bounds

        if layout.style == .liquidGlass, #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            panel.contentView = glass
            glassView = glass
        } else {
            let blur = NSVisualEffectView(frame: bounds)
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.maskImage = HUD.roundedMask(size: size, radius: cornerRadius)
            // Pin with constraints: once NSGlassEffectView has hosted `content` it switches
            // it to Auto Layout, and without these it would collapse to 0×0 in the corner.
            content.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                content.topAnchor.constraint(equalTo: blur.topAnchor),
                content.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            ])
            panel.contentView = blur
            glassView = nil
        }
        panel.invalidateShadow()
    }

    /// Glass variant and "liquid strength": below 100% the glass is tinted toward
    /// white (light) or black (dark), which frosts it; at 100% it is untinted glass.
    private func applyGlassLook() {
        let isDark = panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var clearGlass = false

        if #available(macOS 26, *), let glass = glassView as? NSGlassEffectView {
            clearGlass = Settings.glassStyle == .clear
            glass.style = clearGlass ? .clear : .regular
            let frost = (1 - Settings.liquidStrength) * 0.6
            glass.tintColor = frost > 0.01 ? (isDark ? NSColor.black : NSColor.white).withAlphaComponent(frost) : nil
        }

        // Clear glass lets busy backgrounds through, so give the text a soft halo.
        var halo: NSShadow?
        if clearGlass {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = .zero
            shadow.shadowColor = (isDark ? NSColor.black : NSColor.white).withAlphaComponent(0.6)
            halo = shadow
        }
        glyphLabel.shadow = halo
        captionLabel.shadow = halo
    }

    /// Bottom center of the screen the mouse pointer is on.
    private func moveToActiveScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: area.midX - size.width / 2,
                             y: area.minY + max(60, area.height * 0.1))
        panel.setFrameOrigin(origin)
    }

    private static func roundedMask(size: NSSize, radius: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
    }
}

extension HUDTheme {
    /// nil follows the system light/dark setting.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
