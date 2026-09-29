import Foundation

public struct SerialPort: Equatable, Sendable {
    public let path: String

    public var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    public init(path: String) {
        self.path = path
    }

    public var isLikelyProgrammingCable: Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("cu.usbmodem") || lower.hasPrefix("cu.usbserial")
    }
}

public protocol SerialPortListing: Sendable {
    func listPorts() throws -> [SerialPort]
}

/// Lists `/dev/cu.*` nodes. The 15c CE programming cable appears as CDC ACM
/// (`cu.usbmodem…`) only after ERASE+RESET puts the calculator in SAM-BA mode.
public struct DeviceSerialPortListing: SerialPortListing {
    private let deviceDirectory: URL

    public init(deviceDirectory: URL = URL(fileURLWithPath: "/dev", isDirectory: true)) {
        self.deviceDirectory = deviceDirectory
    }

    public func listPorts() throws -> [SerialPort] {
        let names = try FileManager.default.contentsOfDirectory(atPath: deviceDirectory.path)
        return names
            .filter { $0.hasPrefix("cu.") }
            .map { SerialPort(path: deviceDirectory.appendingPathComponent($0).path) }
            .sorted { $0.path < $1.path }
    }
}

public extension Array where Element == SerialPort {
    var programmingCables: [SerialPort] {
        filter(\.isLikelyProgrammingCable)
    }
}
