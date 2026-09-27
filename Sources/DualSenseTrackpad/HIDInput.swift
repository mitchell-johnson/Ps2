#if canImport(IOKit)
import DualSenseCore
import Foundation
import IOKit.hid

/// Watches for DualSense controllers (USB or Bluetooth) and forwards their raw input reports.
final class HIDInput {
    /// Identifies one connected controller for as long as it stays connected.
    typealias ControllerID = Int

    /// Called on the main run loop with each raw input report (first byte is the report ID).
    var onReport: ((_ controller: ControllerID, _ report: [UInt8]) -> Void)?
    var onConnectionChange: ((_ controller: ControllerID, _ name: String, _ connected: Bool) -> Void)?

    private let manager: IOHIDManager
    private var devices: [DeviceHandle] = []
    private var nextControllerID: ControllerID = 0

    private final class DeviceHandle {
        let id: ControllerID
        let device: IOHIDDevice
        let buffer: UnsafeMutablePointer<UInt8>
        let bufferSize = 128
        weak var owner: HIDInput?

        init(id: ControllerID, device: IOHIDDevice, owner: HIDInput) {
            self.id = id
            self.device = device
            self.owner = owner
            buffer = .allocate(capacity: bufferSize)
            buffer.initialize(repeating: 0, count: bufferSize)
        }

        deinit {
            buffer.deallocate()
        }
    }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = DualSenseReport.productIDs.map { productID -> [String: Any] in
            [kIOHIDVendorIDKey: DualSenseReport.vendorID, kIOHIDProductIDKey: productID]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
    }

    deinit {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Starts listening. Returns false if macOS refused access (Input Monitoring permission).
    func start() -> Bool {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDInput>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDInput>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
    }

    private func attach(_ device: IOHIDDevice) {
        guard !devices.contains(where: { $0.device === device }) else { return }
        let handle = DeviceHandle(id: nextControllerID, device: device, owner: self)
        nextControllerID += 1
        devices.append(handle)

        enableFullReports(device)

        IOHIDDeviceRegisterInputReportCallback(
            device, handle.buffer, handle.bufferSize,
            { context, _, _, _, reportID, report, length in
                guard let context else { return }
                let handle = Unmanaged<DeviceHandle>.fromOpaque(context).takeUnretainedValue()
                var bytes = Array(UnsafeBufferPointer(start: report, count: length))
                // Normalise so the report ID is always the first byte.
                if bytes.first.map(UInt32.init) != reportID {
                    bytes.insert(UInt8(truncatingIfNeeded: reportID), at: 0)
                }
                handle.owner?.onReport?(handle.id, bytes)
            },
            Unmanaged.passUnretained(handle).toOpaque()
        )
        onConnectionChange?(handle.id, name(of: device), true)
    }

    private func detach(_ device: IOHIDDevice) {
        guard let index = devices.firstIndex(where: { $0.device === device }) else { return }
        let handle = devices.remove(at: index)
        IOHIDDeviceRegisterInputReportCallback(device, handle.buffer, handle.bufferSize, nil, nil)
        onConnectionChange?(handle.id, name(of: device), false)
    }

    /// Over Bluetooth the controller only sends a basic report (no touchpad) until the
    /// calibration feature report is read. Harmless over USB.
    private func enableFullReports(_ device: IOHIDDevice) {
        var buffer = [UInt8](repeating: 0, count: 64)
        buffer[0] = DualSenseReport.calibrationFeatureReportID
        var length = CFIndex(buffer.count)
        IOHIDDeviceGetReport(
            device, kIOHIDReportTypeFeature,
            CFIndex(DualSenseReport.calibrationFeatureReportID), &buffer, &length
        )
    }

    private func name(of device: IOHIDDevice) -> String {
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
        return [product ?? "DualSense", transport.map { "(\($0))" }]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
#endif
