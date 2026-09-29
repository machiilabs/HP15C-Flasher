import Foundation

public enum FlasherError: Error, Equatable, LocalizedError {
    case firmwareNotFound(URL)
    case firmwareEmpty
    case firmwareTooLarge(actual: Int, maximum: Int)
    case firmwareWrongSize(actual: Int, expected: Int)
    case writeWouldTouchBootloader(address: UInt32)
    case noProgrammingCable
    case serialOpenFailed(String)
    case serialPortClosed
    case sambaTimeout(String = "")
    case sambaProtocol(String)
    case unsupportedDevice(name: String, cidr: UInt32, exid: UInt32)
    case verifyMismatch
    case flashControllerError(status: UInt32)
    case appletFailed(status: UInt32)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .firmwareNotFound(let url):
            return "Firmware file not found: \(url.path)"
        case .firmwareEmpty:
            return "Firmware file is empty."
        case .firmwareTooLarge(let actual, let maximum):
            return "Firmware is \(actual) bytes; maximum application size is \(maximum) bytes."
        case .firmwareWrongSize(let actual, let expected):
            return "Firmware is \(actual) bytes; expected \(expected) bytes (0x\(String(expected, radix: 16)))."
        case .writeWouldTouchBootloader(let address):
            return "Refusing write at 0x\(String(address, radix: 16)); bootloader occupies 0x0000–0x3FFF."
        case .noProgrammingCable:
            return "No HP programming cable detected. Put the calculator in programming mode and reconnect."
        case .serialOpenFailed(let path):
            return "Could not open serial port \(path)."
        case .serialPortClosed:
            return "The programming cable disconnected. Hold ERASE, press RESET, then release ERASE and wait for the port to reappear."
        case .sambaTimeout(let detail):
            if detail.isEmpty {
                return "Timed out talking to SAM-BA. Leave the cable plugged in. If Status is not Connected, hold ERASE, press RESET, then release ERASE."
            }
            return detail
        case .sambaProtocol(let detail):
            return "SAM-BA protocol error: \(detail)"
        case .unsupportedDevice(let name, let cidr, let exid):
            return String(
                format: "Unsupported chip %@ (CIDR=0x%08X EXID=0x%08X). This tool is for post-2015 Voyager calculators (15c CE, 16c CE, 12c) with an ATSAM4LC2C.",
                name, cidr, exid
            )
        case .verifyMismatch:
            return "Verify failed: flash contents do not match the firmware file. Leave the cable in programming mode and try again."
        case .flashControllerError(let status):
            return String(format: "FLASHCALW reported an error (FSR=0x%08X).", status)
        case .appletFailed(let status):
            return String(
                format: "SAM-BA flash applet failed (status=0x%08X). Leave the cable plugged in. If Status is not Connected, hold ERASE, press RESET, then release ERASE.",
                status
            )
        case .notConnected:
            return "Not connected to a programming cable."
        }
    }
}
