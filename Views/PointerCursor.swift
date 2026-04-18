import SwiftUI
import AppKit

extension View {
    /// Shows the macOS pointing-hand cursor while the pointer is over the view.
    /// Applies to custom interactive surfaces (drop zones, plain buttons) where
    /// AppKit would not swap the cursor on its own.
    func pointingHandCursor() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
