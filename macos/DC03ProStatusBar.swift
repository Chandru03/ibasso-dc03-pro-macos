import AppKit
import Foundation
import IOKit.hid

private let appName = "DC03 Pro Control"
private let vendorID = 0x262a
private let productID = 0x187e

private enum DC03Error: Error, CustomStringConvertible {
    case noDevice
    case openFailed(IOReturn)
    case sendFailed(IOReturn)

    var description: String {
        switch self {
        case .noDevice:
            return "DC03 Pro not found"
        case .openFailed(let status):
            return "Open failed \(String(format: "0x%08x", status))"
        case .sendFailed(let status):
            return "Send failed \(String(format: "0x%08x", status))"
        }
    }
}

private struct Preset {
    let name: String
    let filter: UInt8
    let gain: UInt8
    let output: UInt8
    let volume: UInt8
    let balance: Int
}

private let presets: [Preset] = [
    Preset(name: "Reference", filter: 0, gain: 0, output: 0, volume: 72, balance: 0),
    Preset(name: "Wide-ish", filter: 4, gain: 1, output: 0, volume: 70, balance: 0),
    Preset(name: "IEM Quiet", filter: 1, gain: 0, output: 1, volume: 58, balance: 0),
    Preset(name: "Punch", filter: 2, gain: 2, output: 0, volume: 76, balance: 0),
]

private let filterNames = [
    "Fast roll-off",
    "Slow roll-off",
    "Short delay fast",
    "Short delay slow",
    "NOS",
]

private let volumeSteps: [UInt8] = [
    255, 155, 150, 145, 140, 135, 130, 125, 120, 115,
    110, 109, 108, 107, 106, 105, 104, 103, 102, 101,
    100, 99, 98, 97, 96, 95, 94, 93, 92, 91,
    90, 88, 86, 84, 82, 80, 78, 76, 74, 72,
    70, 68, 66, 64, 62, 60, 58, 56, 54, 52,
    50, 49, 48, 47, 46, 45, 44, 43, 42, 41,
    40, 39, 38, 37, 36, 35, 34, 33, 32, 31,
    30, 29, 28, 27, 26, 25, 24, 23, 22, 21,
    20, 19, 18, 17, 16, 15, 14, 13, 12, 11,
    10, 9, 8, 7, 6, 5, 4, 3, 2, 1,
    0,
]

private func writeRegister(
    seq: UInt8,
    deviceAddress: UInt8,
    offset1: UInt8,
    offset2: UInt8,
    offset3: UInt8,
    offset4: UInt8,
    value: UInt8
) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: 16)
    report[0] = seq
    report[1] = 0x11
    report[2] = 0x88
    report[3] = deviceAddress
    report[6] = 0x05
    report[7] = offset1
    report[8] = offset2
    report[9] = offset3
    report[10] = offset4
    report[11] = value
    return report
}

private func writeTwoByteOffset(
    seq: UInt8,
    deviceAddress: UInt8,
    offset1: UInt8,
    offset2: UInt8,
    value: UInt8
) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: 16)
    report[0] = seq
    report[1] = 0x11
    report[2] = 0xa0
    report[3] = deviceAddress
    report[4] = offset1
    report[5] = offset2
    report[6] = 0x01
    report[7] = value
    return report
}

private func digitalFilterReports(_ value: UInt8) -> [[UInt8]] {
    [
        writeRegister(seq: 0x11, deviceAddress: 0x60, offset1: 0x09, offset2: 0, offset3: 0, offset4: 0, value: value),
        writeRegister(seq: 0x12, deviceAddress: 0x62, offset1: 0x09, offset2: 0, offset3: 0, offset4: 0, value: value),
    ]
}

private func gainReports(_ appValue: UInt8) -> [[UInt8]] {
    let registerValue: UInt8
    switch appValue {
    case 0:
        registerValue = 0x00
    case 1:
        registerValue = 0x20
    default:
        registerValue = 0x31
    }
    return [
        writeRegister(seq: 0x15, deviceAddress: 0x60, offset1: 0x08, offset2: 0, offset3: 0, offset4: 0, value: registerValue),
        writeRegister(seq: 0x16, deviceAddress: 0x62, offset1: 0x08, offset2: 0, offset3: 0, offset4: 0, value: registerValue),
    ]
}

private func outputReports(_ appValue: UInt8) -> [[UInt8]] {
    let registerValue: UInt8 = appValue == 1 ? 0x1e : 0x1c
    return [
        writeRegister(seq: 0x17, deviceAddress: 0x60, offset1: 0x0b, offset2: 0, offset3: 0, offset4: 0, value: registerValue),
        writeRegister(seq: 0x18, deviceAddress: 0x62, offset1: 0x0b, offset2: 0, offset3: 0, offset4: 0, value: registerValue),
    ]
}

private func channelVolumeReports(
    left: UInt8,
    right: UInt8,
    leftCommands: (UInt8, UInt8, UInt8, UInt8),
    rightCommands: (UInt8, UInt8, UInt8, UInt8)
) -> [[UInt8]] {
    let (left1, left2, leftDsd1, leftDsd2) = leftCommands
    let (right1, right2, rightDsd1, rightDsd2) = rightCommands
    return [
        writeRegister(seq: left1, deviceAddress: 0x60, offset1: 0x09, offset2: 0, offset3: 1, offset4: 0, value: left),
        writeRegister(seq: left2, deviceAddress: 0x60, offset1: 0x09, offset2: 0, offset3: 2, offset4: 0, value: left),
        writeRegister(seq: right1, deviceAddress: 0x62, offset1: 0x09, offset2: 0, offset3: 1, offset4: 0, value: right),
        writeRegister(seq: right2, deviceAddress: 0x62, offset1: 0x09, offset2: 0, offset3: 2, offset4: 0, value: right),
        writeRegister(seq: leftDsd1, deviceAddress: 0x60, offset1: 0x07, offset2: 0, offset3: 0, offset4: 0, value: left),
        writeRegister(seq: leftDsd2, deviceAddress: 0x60, offset1: 0x07, offset2: 0, offset3: 1, offset4: 0, value: left),
        writeTwoByteOffset(seq: 0x13, deviceAddress: 0xa2, offset1: 0, offset2: 0x10, value: left),
        writeRegister(seq: rightDsd1, deviceAddress: 0x62, offset1: 0x07, offset2: 0, offset3: 0, offset4: 0, value: right),
        writeRegister(seq: rightDsd2, deviceAddress: 0x62, offset1: 0x07, offset2: 0, offset3: 1, offset4: 0, value: right),
        writeTwoByteOffset(seq: 0x14, deviceAddress: 0xa2, offset1: 0, offset2: 0x11, value: right),
    ]
}

private func volumeReports(volume: UInt8, balance: Int) -> [[UInt8]] {
    let safeVolume = min(100, Int(volume))
    let safeBalance = min(255, max(-255, balance))
    let base = Int(volumeSteps[safeVolume])
    let left: Int
    let right: Int

    if base == 255 {
        left = base
        right = base
    } else if safeBalance >= 0 {
        left = base
        right = max(0, base - safeBalance)
    } else {
        left = max(0, base + safeBalance)
        right = base
    }

    let leftByte = UInt8(clamping: left)
    let rightByte = UInt8(clamping: right)

    if safeBalance == 0 {
        return channelVolumeReports(left: leftByte, right: rightByte, leftCommands: (0x01, 0x02, 0x09, 0x0a), rightCommands: (0x03, 0x04, 0x0b, 0x0c))
    } else if safeBalance > 0 {
        return channelVolumeReports(left: leftByte, right: rightByte, leftCommands: (0x01, 0x02, 0x09, 0x0a), rightCommands: (0x07, 0x08, 0x0f, 0x10))
    }
    return channelVolumeReports(left: leftByte, right: rightByte, leftCommands: (0x05, 0x06, 0x0d, 0x0e), rightCommands: (0x03, 0x04, 0x0b, 0x0c))
}

private func presetReports(_ preset: Preset) -> [[UInt8]] {
    digitalFilterReports(preset.filter)
        + gainReports(preset.gain)
        + outputReports(preset.output)
        + volumeReports(volume: preset.volume, balance: preset.balance)
}

private final class DC03Device {
    static func matchingDevices() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID,
            kIOHIDPrimaryUsagePageKey: 0x0c,
            kIOHIDPrimaryUsageKey: 0x01,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }
        return Array(set)
    }

    static func isAvailable() -> Bool {
        !matchingDevices().isEmpty
    }

    static func send(_ reports: [[UInt8]]) throws {
        guard let device = matchingDevices().first else {
            throw DC03Error.noDevice
        }

        let openStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess else {
            throw DC03Error.openFailed(openStatus)
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        for report in reports {
            var mutableReport = report
            let status = mutableReport.withUnsafeMutableBufferPointer { buffer in
                IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeOutput,
                    CFIndex(0),
                    buffer.baseAddress!,
                    buffer.count
                )
            }
            guard status == kIOReturnSuccess else {
                throw DC03Error.sendFailed(status)
            }
            usleep(20_000)
        }
    }
}

private final class ControlViewController: NSViewController {
    private let statusLabel = NSTextField(labelWithString: "Checking...")
    private let statusDot = NSView()
    private let feedbackLabel = NSTextField(labelWithString: "")
    private let volumeValueLabel = NSTextField(labelWithString: "75")
    private let balanceValueLabel = NSTextField(labelWithString: "0")
    private let volumeSlider = NSSlider(value: 75, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let balanceSlider = NSSlider(value: 0, minValue: -50, maxValue: 50, target: nil, action: nil)
    private let filterPopup = NSPopUpButton()
    private let gainPopup = NSPopUpButton()
    private let outputPopup = NSPopUpButton()
    var onStatusChange: ((Bool) -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 368, height: 500))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        buildUI()
        refreshStatus()
    }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        root.addArrangedSubview(headerView())
        root.addArrangedSubview(presetsView())

        filterPopup.addItems(withTitles: filterNames.enumerated().map { "\($0.offset): \($0.element)" })
        gainPopup.addItems(withTitles: ["Low", "Medium", "High"])
        outputPopup.addItems(withTitles: ["Normal", "Power saving"])
        root.addArrangedSubview(settingsView())

        volumeSlider.target = self
        volumeSlider.action = #selector(sliderChanged)
        balanceSlider.target = self
        balanceSlider.action = #selector(sliderChanged)
        root.addArrangedSubview(volumeView())

        feedbackLabel.font = .systemFont(ofSize: 12)
        feedbackLabel.textColor = .secondaryLabelColor
        feedbackLabel.alignment = .center
        root.addArrangedSubview(feedbackLabel)
    }

    private func headerView() -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 12
        container.alignment = .centerY

        let icon = symbolBadge("waveform", size: 38)
        container.addArrangedSubview(icon)

        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.spacing = 3

        let title = NSTextField(labelWithString: appName)
        title.font = .systemFont(ofSize: 17, weight: .medium)
        title.textColor = .labelColor
        titleStack.addArrangedSubview(title)

        let statusStack = NSStackView()
        statusStack.orientation = .horizontal
        statusStack.spacing = 6
        statusStack.alignment = .centerY
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusStack.addArrangedSubview(statusDot)
        statusStack.addArrangedSubview(statusLabel)
        titleStack.addArrangedSubview(statusStack)

        container.addArrangedSubview(titleStack)
        titleStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let refresh = iconButton("arrow.clockwise", action: #selector(refreshPressed))
        container.addArrangedSubview(refresh)
        return container
    }

    private func presetsView() -> NSView {
        let content = cardStack(title: "Presets")
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.spacing = 8

        for chunkStart in stride(from: 0, to: presets.count, by: 2) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            for preset in presets[chunkStart..<min(chunkStart + 2, presets.count)] {
                let item = NSButton(title: preset.name, target: self, action: #selector(presetPressed(_:)))
                item.bezelStyle = .rounded
                item.controlSize = .large
                item.font = .systemFont(ofSize: 13, weight: .medium)
                item.identifier = NSUserInterfaceItemIdentifier(preset.name)
                row.addArrangedSubview(item)
                item.widthAnchor.constraint(equalToConstant: 154).isActive = true
            }
            rows.addArrangedSubview(row)
        }

        content.addArrangedSubview(rows)
        return content.enclosingCard()
    }

    private func settingsView() -> NSView {
        let content = cardStack(title: "Sound")
        content.addArrangedSubview(controlRow("Filter", control: filterPopup, actionTitle: "Set", action: #selector(applyFilter)))
        content.addArrangedSubview(controlRow("Gain", control: gainPopup, actionTitle: "Set", action: #selector(applyGain)))
        content.addArrangedSubview(controlRow("Output", control: outputPopup, actionTitle: "Set", action: #selector(applyOutput)))
        return content.enclosingCard()
    }

    private func volumeView() -> NSView {
        let content = cardStack(title: "Level")
        content.addArrangedSubview(sliderRow("Volume", volumeSlider, valueLabel: volumeValueLabel))
        content.addArrangedSubview(sliderRow("Balance", balanceSlider, valueLabel: balanceValueLabel))
        let apply = primaryButton("Apply Level", action: #selector(applyVolume))
        content.addArrangedSubview(apply)
        return content.enclosingCard()
    }

    private func cardStack(title: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        let label = sectionLabel(title)
        stack.addArrangedSubview(label)
        return stack
    }

    private func symbolBadge(_ symbolName: String, size: CGFloat) -> NSView {
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        badge.layer?.cornerRadius = 11
        badge.widthAnchor.constraint(equalToConstant: size).isActive = true
        badge.heightAnchor.constraint(equalToConstant: size).isActive = true

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])

        return badge
    }

    private func iconButton(_ symbolName: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: "Refresh") ?? NSImage(), target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.imagePosition = .imageOnly
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    private func primaryButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .medium)
        return button
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func controlRow(_ label: String, control: NSView, actionTitle: String, action: Selector) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 13)
        title.textColor = .labelColor
        title.widthAnchor.constraint(equalToConstant: 56).isActive = true
        control.widthAnchor.constraint(equalToConstant: 178).isActive = true
        let actionButton = primaryButton(actionTitle, action: action)
        actionButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
        let stack = NSStackView(views: [title, control, actionButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        return stack
    }

    private func sliderRow(_ label: String, _ slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 13)
        title.textColor = .labelColor
        title.widthAnchor.constraint(equalToConstant: 56).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 202).isActive = true
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
        let stack = NSStackView(views: [title, slider, valueLabel])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        return stack
    }

    @objc private func refreshPressed() {
        refreshStatus()
    }

    private func refreshStatus() {
        let available = DC03Device.isAvailable()
        statusLabel.stringValue = available ? "Connected" : "Connect your DC03 Pro"
        statusDot.layer?.backgroundColor = available ? NSColor.systemGreen.cgColor : NSColor.systemGray.cgColor
        onStatusChange?(available)
    }

    @objc private func sliderChanged() {
        volumeValueLabel.stringValue = "\(Int(volumeSlider.doubleValue.rounded()))"
        balanceValueLabel.stringValue = "\(Int(balanceSlider.doubleValue.rounded()))"
    }

    @objc private func presetPressed(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let preset = presets.first(where: { $0.name == id }) else {
            return
        }
        filterPopup.selectItem(at: Int(preset.filter))
        gainPopup.selectItem(at: Int(preset.gain))
        outputPopup.selectItem(at: Int(preset.output))
        volumeSlider.doubleValue = Double(preset.volume)
        balanceSlider.doubleValue = Double(preset.balance)
        send("Preset \(preset.name)", presetReports(preset))
    }

    @objc private func applyFilter() {
        send("Filter \(filterPopup.indexOfSelectedItem)", digitalFilterReports(UInt8(filterPopup.indexOfSelectedItem)))
    }

    @objc private func applyGain() {
        send("Gain \(gainPopup.titleOfSelectedItem ?? "")", gainReports(UInt8(gainPopup.indexOfSelectedItem)))
    }

    @objc private func applyOutput() {
        send("Output \(outputPopup.titleOfSelectedItem ?? "")", outputReports(UInt8(outputPopup.indexOfSelectedItem)))
    }

    @objc private func applyVolume() {
        let volume = UInt8(clamping: Int(volumeSlider.doubleValue.rounded()))
        let balance = Int(balanceSlider.doubleValue.rounded())
        send("Volume \(volume), balance \(balance)", volumeReports(volume: volume, balance: balance))
    }

    private func send(_ label: String, _ reports: [[UInt8]]) {
        do {
            try DC03Device.send(reports)
            feedbackLabel.stringValue = "\(label) applied"
            refreshStatus()
        } catch {
            feedbackLabel.stringValue = "Unable to apply setting"
            refreshStatus()
        }
    }
}

private extension NSStackView {
    func enclosingCard() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 16
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        container.layer?.borderWidth = 1

        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)

        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topAnchor.constraint(equalTo: container.topAnchor),
            bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let controller = ControlViewController()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        updateStatusIcon(available: DC03Device.isAvailable())
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        controller.onStatusChange = { [weak self] available in
            self?.updateStatusIcon(available: available)
        }

        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            let available = DC03Device.isAvailable()
            self?.updateStatusIcon(available: available)
        }
    }

    private func updateStatusIcon(available: Bool) {
        let symbolName = available ? "waveform.circle.fill" : "waveform.circle"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: appName)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.title = ""
        statusItem.button?.toolTip = available ? "DC03 Pro connected" : "DC03 Pro Control"
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
