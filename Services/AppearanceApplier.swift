import AppKit
import QuartzCore

enum AppearanceApplier {
    static func apply(_ appearance: AppAppearance, animated: Bool) {
        let target = appearance.nsAppearance

        guard animated,
              let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView,
              contentView.bounds.width > 0,
              contentView.bounds.height > 0,
              let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
        else {
            NSApp.appearance = target
            return
        }

        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        let snapshot = NSImage(size: contentView.bounds.size)
        snapshot.addRepresentation(rep)

        let contentRectInWindow = contentView.convert(contentView.bounds, to: nil)
        let overlayFrame = window.convertToScreen(contentRectInWindow)

        let overlayWindow = NSWindow(
            contentRect: overlayFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.level = .floating

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: overlayFrame.size))
        imageView.image = snapshot
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        overlayWindow.contentView = imageView

        overlayWindow.orderFront(nil)

        NSApp.appearance = target

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlayWindow.animator().alphaValue = 0
        }, completionHandler: {
            overlayWindow.orderOut(nil)
        })
    }
}
