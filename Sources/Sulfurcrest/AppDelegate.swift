import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dictation = DictationController()

    private var statusItem: NSStatusItem?
    private let statusTitleItem = NSMenuItem(title: "Sulfurcrest", action: nil, keyEquivalent: "")
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // Global right-Command hotkey + dictation state machine. The monitor
        // observes a modifier and works without Accessibility; only paste
        // (synthetic ⌘V) needs it.
        dictation.start()

        // Onboarding drives the permission prompts (with context) instead of
        // firing them unexplained at launch. Show it on first run, or whenever
        // a required permission is still missing.
        let permissionMissing = Permissions.microphoneStatus != .authorized
            || !Permissions.isAccessibilityTrusted
        if !Settings.shared.hasCompletedOnboarding || permissionMissing {
            showOnboarding()
        }

        // Load the Parakeet model into memory (downloads on first run). Mirror
        // progress into ModelStatus so the onboarding window can show it.
        setStatus("Loading model…")
        Task { [weak self] in
            do {
                try await ASRService.shared.warmUp { fraction in
                    Task { @MainActor in
                        ModelStatus.shared.progress = fraction
                        self?.setStatus("Downloading model… \(Int(fraction * 100))%")
                    }
                }
                ModelStatus.shared.markLoaded()
                self?.setStatus(nil)
                self?.dictation.setModelReady(true)
            } catch {
                ModelStatus.shared.failed = true
                self?.setStatus("Model failed to load")
                NSLog("Sulfurcrest: model load failed: \(error)")
            }
        }
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "mic.fill", accessibilityDescription: "Sulfurcrest")

        statusTitleItem.isEnabled = false

        let onboardingItem = NSMenuItem(
            title: "Setup Guide…", action: #selector(showOnboarding), keyEquivalent: "")
        onboardingItem.target = self

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        let menu = NSMenu()
        menu.addItem(statusTitleItem)
        menu.addItem(.separator())
        menu.addItem(onboardingItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Sulfurcrest", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    private func setStatus(_ title: String?) {
        statusTitleItem.title = title ?? "Sulfurcrest — Ready (hold right ⌘)"
    }

    // MARK: - Onboarding window

    @objc private func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentViewController: NSHostingController(
                    rootView: OnboardingView(onDone: { [weak self] in
                        self?.onboardingWindow?.close()
                    })))
            window.title = "Welcome to Sulfurcrest"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.center()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Settings window

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Sulfurcrest Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
