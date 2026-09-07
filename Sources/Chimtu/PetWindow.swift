import AppKit

/// Borderless, transparent, always-on-top window that hosts the pet layer.
final class PetWindow: NSWindow {
    init(size: CGSize) {
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
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    let sprite = CALayer()
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        sprite.frame = bounds
        sprite.contentsGravity = .resizeAspect
        sprite.magnificationFilter = .linear
        sprite.contentsScale = 2
        layer?.addSublayer(sprite)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no implicit fade animations
        sprite.contents = image
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 1 { onClick?() }
    }
}
