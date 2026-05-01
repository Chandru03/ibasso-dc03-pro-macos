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
    case invalidRawReport

    var description: String {
        switch self {
        case .noDevice:
            return "DC03 Pro not found"
        case .openFailed(let status):
            return "Open failed \(String(format: "0x%08x", status))"
        case .sendFailed(let status):
            return "Send failed \(String(format: "0x%08x", status))"
        case .invalidRawReport:
            return "Raw report must be 16 bytes"
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

private func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

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

private func parseRawReport(_ raw: String) throws -> [UInt8] {
    let cleaned = raw
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: ",", with: "")
    guard cleaned.count == 32 else {
        throw DC03Error.invalidRawReport
    }

    var result: [UInt8] = []
    var index = cleaned.startIndex
    while index < cleaned.endIndex {
        let next = cleaned.index(index, offsetBy: 2)
        guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
            throw DC03Error.invalidRawReport
        }
        result.append(byte)
        index = next
    }
    return result
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
    private let logLabel = NSTextField(labelWithString: "No reports sent yet")
    private let volumeSlider = NSSlider(value: 75, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let balanceSlider = NSSlider(value: 0, minValue: -50, maxValue: 50, target: nil, action: nil)
    private let filterPopup = NSPopUpButton()
    private let gainPopup = NSPopUpButton()
    private let outputPopup = NSPopUpButton()
    private let rawField = NSTextField(string: "11118860000005090000000200000000")
    var onStatusChange: ((Bool) -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 570))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildUI()
        refreshStatus()
    }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let title = NSTextField(labelWithString: appName)
        title.font = .boldSystemFont(ofSize: 18)
        root.addArrangedSubview(title)

        statusLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(statusLabel)

        let refresh = button("Refresh Device", action: #selector(refreshPressed))
        root.addArrangedSubview(refresh)

        root.addArrangedSubview(separator())

        let presetsLabel = sectionLabel("Presets")
        root.addArrangedSubview(presetsLabel)
        let presetGrid = NSStackView()
        presetGrid.orientation = .vertical
        presetGrid.spacing = 8
        for preset in presets {
            let item = NSButton(title: preset.name, target: self, action: #selector(presetPressed(_:)))
            item.bezelStyle = .rounded
            item.identifier = NSUserInterfaceItemIdentifier(preset.name)
            presetGrid.addArrangedSubview(item)
        }
        root.addArrangedSubview(presetGrid)

        root.addArrangedSubview(separator())

        filterPopup.addItems(withTitles: filterNames.enumerated().map { "\($0.offset): \($0.element)" })
        gainPopup.addItems(withTitles: ["Low", "Medium", "High"])
        outputPopup.addItems(withTitles: ["Normal", "Power saving"])
        root.addArrangedSubview(row("Filter", filterPopup, button("Apply", action: #selector(applyFilter))))
        root.addArrangedSubview(row("Gain", gainPopup, button("Apply", action: #selector(applyGain))))
        root.addArrangedSubview(row("Output", outputPopup, button("Apply", action: #selector(applyOutput))))

        root.addArrangedSubview(separator())

        root.addArrangedSubview(sliderRow("Volume", volumeSlider))
        root.addArrangedSubview(sliderRow("Balance", balanceSlider))
        root.addArrangedSubview(button("Apply Volume + Balance", action: #selector(applyVolume)))

        root.addArrangedSubview(separator())

        root.addArrangedSubview(sectionLabel("Raw 16-byte report"))
        rawField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        root.addArrangedSubview(rawField)
        root.addArrangedSubview(button("Send Raw Report", action: #selector(sendRaw)))

        logLabel.textColor = .secondaryLabelColor
        logLabel.lineBreakMode = .byTruncatingMiddle
        root.addArrangedSubview(logLabel)

        let quit = button("Quit", action: #selector(quit))
        root.addArrangedSubview(quit)
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func row(_ label: String, _ control: NSView, _ action: NSButton) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.widthAnchor.constraint(equalToConstant: 58).isActive = true
        control.widthAnchor.constraint(equalToConstant: 172).isActive = true
        let stack = NSStackView(views: [title, control, action])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        return stack
    }

    private func sliderRow(_ label: String, _ slider: NSSlider) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.widthAnchor.constraint(equalToConstant: 58).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 242).isActive = true
        let stack = NSStackView(views: [title, slider])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        return stack
    }

    @objc private func refreshPressed() {
        refreshStatus()
    }

    private func refreshStatus() {
        let available = DC03Device.isAvailable()
        statusLabel.stringValue = available ? "DC03 Pro detected" : "DC03 Pro not detected"
        statusLabel.textColor = available ? .systemGreen : .systemRed
        onStatusChange?(available)
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

    @objc private func sendRaw() {
        do {
            let report = try parseRawReport(rawField.stringValue)
            send("Raw", [report])
        } catch {
            logLabel.stringValue = String(describing: error)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func send(_ label: String, _ reports: [[UInt8]]) {
        do {
            try DC03Device.send(reports)
            logLabel.stringValue = "\(label) sent: \(hexString(reports.last ?? []))"
            refreshStatus()
        } catch {
            logLabel.stringValue = String(describing: error)
            refreshStatus()
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let controller = ControlViewController()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem.button?.title = "DC03"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        controller.onStatusChange = { [weak self] available in
            self?.statusItem.button?.title = available ? "DC03 *" : "DC03"
        }

        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            let available = DC03Device.isAvailable()
            self?.statusItem.button?.title = available ? "DC03 *" : "DC03"
        }
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
