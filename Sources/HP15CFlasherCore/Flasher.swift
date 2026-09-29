import Foundation

public struct FlashPlan: Equatable {
    public let image: FirmwareImage
    public let address: UInt32
    public let port: SerialPort?

    public var byteCount: Int { image.byteCount }
}

public enum FlashProgressPhase: Sendable {
    case reading
    case writing
    case verifying
}

public struct FlashPageWrite: Sendable, Equatable {
    public let flashOffset: UInt32
    public let pageIndex: Int
    public let pageCount: Int
    public let pageData: Data

    public init(flashOffset: UInt32, pageIndex: Int, pageCount: Int, pageData: Data) {
        self.flashOffset = flashOffset
        self.pageIndex = pageIndex
        self.pageCount = pageCount
        self.pageData = pageData
    }

    public var header: String {
        String(format: "Page %d of %d · 0x%05X", pageIndex + 1, pageCount, flashOffset)
    }

    /// Application page as little-endian 16-bit words (four hex digits each).
    public func formattedWordLines(wordsPerLine: Int = 16) -> [String] {
        var lines: [String] = []
        var words: [String] = []
        var index = 0
        while index + 1 < pageData.count {
            let word = UInt16(pageData[index]) | (UInt16(pageData[index + 1]) << 8)
            words.append(String(format: "%04X", word))
            index += 2
            if words.count == wordsPerLine {
                lines.append(words.joined(separator: " "))
                words.removeAll(keepingCapacity: true)
            }
        }
        if !words.isEmpty {
            lines.append(words.joined(separator: " "))
        }
        return lines
    }
}

public typealias FlashProgress = (_ fraction: Double, _ phase: FlashProgressPhase) -> Void
public typealias FlashPageProgress = @Sendable (FlashPageWrite) -> Void

/// Coordinates cable detection, image checks, and SAM-BA flash I/O.
public struct Flasher {
    public var ports: SerialPortListing
    public var requireExactFirmwareSize: Bool
    public var openTransport: (SerialPort) throws -> ByteTransport
    /// Official SAM-BA delay after `G#` before the first mailbox poll (10 ms).
    public var flashCommandSettleSeconds: TimeInterval

    public init(
        ports: SerialPortListing = DeviceSerialPortListing(),
        requireExactFirmwareSize: Bool = true,
        openTransport: @escaping (SerialPort) throws -> ByteTransport = { try POSIXSerialLink(path: $0.path) },
        flashCommandSettleSeconds: TimeInterval = 0.010
    ) {
        self.ports = ports
        self.requireExactFirmwareSize = requireExactFirmwareSize
        self.openTransport = openTransport
        self.flashCommandSettleSeconds = flashCommandSettleSeconds
    }

    public func listProgrammingCables() throws -> [SerialPort] {
        try ports.listPorts().programmingCables
    }

    public func requireProgrammingCable() throws -> SerialPort {
        guard let first = try preferredProgrammingCables().first else {
            throw FlasherError.noProgrammingCable
        }
        return first
    }

    /// `cu.usbmodem` (Atmel SAM-BA CDC) first, then FTDI `cu.usbserial`.
    public func preferredProgrammingCables() throws -> [SerialPort] {
        let cables = try listProgrammingCables()
        return cables.sorted { lhs, rhs in
            let l = lhs.name.lowercased()
            let r = rhs.name.lowercased()
            return Self.portPriority(l) < Self.portPriority(r)
        }
    }

    private static func portPriority(_ name: String) -> Int {
        if name.hasPrefix("cu.usbmodem") { return 0 }
        if name.hasPrefix("cu.usbserial") { return 1 }
        return 2
    }

    public func planWrite(firmwareURL: URL, address: UInt32 = FlashLayout.applicationStart) throws -> FlashPlan {
        let image = try FirmwareImage.load(from: firmwareURL, requireExactSize: requireExactFirmwareSize)
        guard FlashLayout.isSafeApplicationRange(address: address, length: UInt32(image.byteCount)) else {
            throw FlasherError.writeWouldTouchBootloader(address: address)
        }
        let port = try? requireProgrammingCable()
        return FlashPlan(image: image, address: address, port: port)
    }

    /// Opens the cable, enters SAM-BA mode, and reads CHIPID.
    /// Only `cu.usbmodem` (Atmel CDC). The pogo FTDI `cu.usbserial` is not SAM-BA.
    public func connect(timeout: TimeInterval = 3.0) throws -> ConnectedTarget {
        let cables = try preferredProgrammingCables().filter {
            $0.name.lowercased().hasPrefix("cu.usbmodem")
        }
        guard !cables.isEmpty else {
            throw FlasherError.noProgrammingCable
        }
        var lastError: Error = FlasherError.noProgrammingCable
        for port in cables {
            do {
                return try openAndIdentify(port, timeout: timeout)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func openAndIdentify(_ port: SerialPort, timeout: TimeInterval) throws -> ConnectedTarget {
        let transport = try openTransport(port)
        let client = SambaClient(transport: transport)
        do {
            try client.connect(timeout: timeout)
            let identity = try FlashCalw(samba: client).identify()
            return ConnectedTarget(port: port, client: client, identity: identity)
        } catch {
            client.close()
            throw error
        }
    }

    public func write(
        firmwareURL: URL,
        address: UInt32 = FlashLayout.applicationStart,
        client: SambaClient? = nil,
        verify: Bool = true,
        progress: FlashProgress? = nil,
        pageProgress: FlashPageProgress? = nil
    ) throws {
        let plan = try planWrite(firmwareURL: firmwareURL, address: address)
        if client == nil, plan.port == nil {
            throw FlasherError.noProgrammingCable
        }
        try withClient(client) { samba in
            let flash = FlashCalw(samba: samba, commandSettleSeconds: flashCommandSettleSeconds)
            try flash.writeApplication(
                plan.image.data,
                progress: { progress?($0, .writing) },
                verifyProgress: { progress?($0, .verifying) },
                pageProgress: pageProgress,
                verify: verify
            )
        }
    }

    public func verify(
        firmwareURL: URL,
        address: UInt32 = FlashLayout.applicationStart,
        client: SambaClient? = nil,
        progress: FlashProgress? = nil
    ) throws {
        let plan = try planWrite(firmwareURL: firmwareURL, address: address)
        try withClient(client) { samba in
            try FlashCalw(samba: samba).verifyApplication(
                plan.image.data,
                progress: { progress?($0, .verifying) }
            )
        }
    }

    @discardableResult
    public func read(to fileURL: URL, client: SambaClient? = nil, progress: FlashProgress? = nil) throws -> Data {
        let saved = try readApplication(client: client, progress: progress)
        try saved.write(to: fileURL)
        return saved
    }

    /// Reads the application region (`0x04000`, 112 KB) without writing a file.
    public func readApplication(client: SambaClient? = nil, progress: FlashProgress? = nil) throws -> Data {
        var saved = Data()
        try withClient(client) { samba in
            let flash = FlashCalw(samba: samba)
            let identity = try flash.identify()
            guard identity.isSupported15C else {
                throw FlasherError.unsupportedDevice(name: identity.name, cidr: identity.cidr, exid: identity.exid)
            }
            saved = try flash.readApplication { progress?($0, .reading) }
        }
        return saved
    }

    private func withClient(_ existing: SambaClient?, body: (SambaClient) throws -> Void) throws {
        if let existing {
            try body(existing)
            return
        }
        let connected = try connect()
        defer { connected.client.close() }
        guard connected.identity.isSupported15C else {
            throw FlasherError.unsupportedDevice(
                name: connected.identity.name,
                cidr: connected.identity.cidr,
                exid: connected.identity.exid
            )
        }
        try body(connected.client)
    }
}

public struct ConnectedTarget {
    public let port: SerialPort
    public let client: SambaClient
    public let identity: DeviceIdentity
}
