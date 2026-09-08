import AppKit

/// Borderless, transparent, always-on-top window that hosts the pet layer.
final class PetWindow: NSWindow {
    init(size: CGSize) {   // size = window size incl. bubble headroom
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = PetView(frame: NSRect(origin: .zero, size: size))
        NotificationCenter.default.addObserver(forName: NSWindow.willMoveNotification, object: self, queue: .main) { [weak self] _ in self?.onDragStart?() }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in self?.onDragEnd?() }
    }
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    let sprite = CALayer()
    private let bubble = CALayer()
    private let bubbleText = CATextLayer()
    private var bubbleTimer: Timer?
    var onFileDrop: (([URL]) -> Void)?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onLongPress: (() -> Void)?
    private var pressStart = Date.distantPast
    private var pressOrigin = NSPoint.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        sprite.frame = CGRect(origin: .zero, size: Sprites.size)   // bottom of the window
        sprite.contentsGravity = .resizeAspect
        sprite.magnificationFilter = .linear
        sprite.contentsScale = 2
        layer?.addSublayer(sprite)

        bubble.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.96).cgColor
        bubble.borderColor = NSColor(calibratedRed: 0.87, green: 0.59, blue: 0.32, alpha: 1).cgColor
        bubble.borderWidth = 1.5
        bubble.cornerRadius = 10
        bubble.isHidden = true
        bubbleText.alignmentMode = .center
        bubbleText.fontSize = 12
        bubbleText.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        bubbleText.foregroundColor = NSColor(calibratedRed: 0.3, green: 0.2, blue: 0.12, alpha: 1).cgColor
        bubbleText.contentsScale = 2
        bubbleText.truncationMode = .end
        bubble.addSublayer(bubbleText)
        layer?.addSublayer(bubble)
        registerForDraggedTypes([.fileURL])
    }

    /// Show a short speech bubble above the pet for a few seconds.
    func say(_ text: String, for seconds: TimeInterval = 2.5) {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let w = min(max((text as NSString).size(withAttributes: [.font: font]).width + 18, 40), bounds.width)
        let h: CGFloat = 24
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bubble.frame = CGRect(x: (bounds.width - w) / 2, y: Sprites.size.height + 4, width: w, height: h)
        bubbleText.frame = CGRect(x: 0, y: (h - 15) / 2 - 1, width: w, height: 16)
        bubbleText.string = text
        bubble.isHidden = false
        CATransaction.commit()
        bubbleTimer?.invalidate()
        bubbleTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self?.bubble.isHidden = true
            CATransaction.commit()
        }
    }

    /// Scale the whole pet (window is resized by the controller).
    func apply(scale: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        sprite.frame = CGRect(origin: .zero, size: CGSize(width: Sprites.size.width * scale, height: Sprites.size.height * scale))
        CATransaction.commit()
    }

    // MARK: file drop -> fetch
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls)
        return true
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no implicit fade animations
        sprite.contents = image
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        pressStart = Date(); pressOrigin = window?.frame.origin ?? .zero
        super.mouseDown(with: event)   // keeps window-background dragging working
    }
    override func mouseUp(with event: NSEvent) {
        let moved = (window?.frame.origin ?? .zero) != pressOrigin
        if !moved && Date().timeIntervalSince(pressStart) > 0.5 { onLongPress?(); return }   // petting
        if event.clickCount == 2 { onDoubleClick?() }
        else if event.clickCount == 1 { onClick?() }
    }
}
