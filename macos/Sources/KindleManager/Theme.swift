import SwiftUI

enum AppPalette {
    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x0A1014) : Color(nsColor: .windowBackgroundColor)
    }

    static func chrome(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x10181D) : Color(nsColor: .windowBackgroundColor)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x19262B) : Color(nsColor: .controlBackgroundColor)
    }

    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x121D22) : Color(nsColor: .controlBackgroundColor)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x86C9BB) : .accentColor
    }

    static func base(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x6C7B8B) : .secondary
    }

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? base(scheme).opacity(0.32) : Color.secondary.opacity(0.18)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x97A7AC) : .secondary
    }

    static func hover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct WindowConfigurator: NSViewRepresentable {
    final class Coordinator {
        var monitor: Any?

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view)
            installDragMonitor(for: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view) }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.isMovableByWindowBackground = true
        window.toolbar?.showsBaselineSeparator = false
    }

    private func installDragMonitor(for view: NSView, coordinator: Coordinator) {
        guard coordinator.monitor == nil else { return }
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = view.window,
                  event.window === window,
                  event.clickCount == 1,
                  event.locationInWindow.y >= window.contentLayoutRect.maxY,
                  let hit = window.contentView?.superview?.hitTest(event.locationInWindow),
                  isDraggableTitleArea(hit)
            else { return event }

            window.performDrag(with: event)
            return nil
        }
    }

    private func isDraggableTitleArea(_ hit: NSView) -> Bool {
        var current: NSView? = hit
        while let view = current {
            let name = String(describing: type(of: view))
            if name.contains("ToolbarTitle") || name.contains("Titlebar") {
                return true
            }
            if name.contains("Widget") || name.contains("Button") || name.contains("Segmented")
                || name.contains("Popup") || name.contains("ToolbarItemViewer") {
                return false
            }
            current = view.superview
        }
        return false
    }
}
