import ArgumentParser
import Foundation
import HP15CFlasherCore

@main
struct HP15CFlasherCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hp15c-flasher",
        abstract: "Flash post-2015 Voyager firmware (HP 15c CE, 16c CE, 12c) from macOS.",
        discussion: """
        The programming cable must be in SAM-BA mode (hold ERASE, press RESET, \
        release ERASE) before the calculator appears as a USB serial device.

        Writes always start at 0x4000 so the ATSAM4L bootloader is left intact.
        """,
        version: "1.0.0",
        subcommands: [List.self, Info.self, Validate.self, Backup.self, Flash.self]
    )
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List serial ports that look like the HP programming cable."
    )

    func run() throws {
        let flasher = Flasher()
        let cables = try flasher.listProgrammingCables()
        if cables.isEmpty {
            FileHandle.standardError.write(
                Data("No programming cable detected.\n".utf8)
            )
            throw ExitCode.failure
        }
        for port in cables {
            print(port.path)
        }
    }
}

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check that a .bin is the expected 112 KB application image."
    )

    @Argument(help: "Path to a firmware .bin file.")
    var firmware: String

    func run() throws {
        let url = URL(fileURLWithPath: firmware)
        let image = try FirmwareImage.load(from: url)
        print(
            "OK \(image.byteCount) bytes (\(image.url.lastPathComponent)); write address 0x\(String(FlashLayout.applicationStart, radix: 16))"
        )
    }
}

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Identify the chip in SAM-BA programming mode."
    )

    func run() throws {
        let connected = try Flasher().connect()
        defer { connected.client.close() }
        print("Port: \(connected.port.path)")
        print("SAM-BA: \(connected.client.version)")
        print("Chip: \(connected.identity.name)")
        print(String(format: "CIDR: 0x%08X  EXID: 0x%08X  CPUID: 0x%08X",
                     connected.identity.cidr, connected.identity.exid, connected.identity.cpuid))
        if !connected.identity.isSupported15C {
            throw FlasherError.unsupportedDevice(
                name: connected.identity.name,
                cidr: connected.identity.cidr,
                exid: connected.identity.exid
            )
        }
    }
}

struct Backup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read application flash into a .bin (requires cable)."
    )

    @Argument(help: "Output .bin path.")
    var output: String

    func run() throws {
        try Flasher().read(to: URL(fileURLWithPath: output), progress: CLIProgress.report)
        CLIProgress.finish()
        print("Wrote \(output)")
    }
}

struct Flash: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write a .bin to application flash at 0x4000 (requires cable)."
    )

    @Argument(help: "Path to a firmware .bin file.")
    var firmware: String

    func run() throws {
        try Flasher().write(firmwareURL: URL(fileURLWithPath: firmware), progress: CLIProgress.report)
        CLIProgress.finish()
        print("Flashed and verified \(firmware)")
        print("Press RESET on the cable, then turn the calculator ON. Pr Error is expected.")
    }
}

enum CLIProgress {
    static func report(_ fraction: Double, _ phase: FlashProgressPhase) {
        let name: String
        switch phase {
        case .reading: name = "Reading"
        case .writing: name = "Writing"
        case .verifying: name = "Verifying"
        }
        let pct = Int((fraction * 100).rounded(.down))
        FileHandle.standardError.write(Data("\r\(name) \(pct)%".utf8))
    }

    static func finish() {
        FileHandle.standardError.write(Data("\n".utf8))
    }
}
