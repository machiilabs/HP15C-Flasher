import Foundation

/// Checksum shown on the HP 15c CE test menu (`g`+`ENTER`+`ON`, then `2`).
///
/// The ARM Voyager 2.C screen displays an 8-bit additive checksum as a
/// repeated byte (for example `0A0Ah`). Two matching halves are the whole
/// scheme — collision odds are 1 in 256.
public enum VoyagerFirmwareChecksum {
    /// Trailing `0x00` padding is ignored; the last remaining byte is the
    /// stored checksum. The displayed value is that byte duplicated.
    public static func displayedValue(of data: Data) -> UInt16 {
        let payload = trimmingTrailingZeros(data)
        guard payload.count >= 2 else { return 0 }
        let sum = payload.dropLast().reduce(UInt16(0)) { ($0 &+ UInt16($1)) & 0xFF }
        return (sum << 8) | sum
    }

    public static func formatted(_ value: UInt16) -> String {
        String(format: "%04Xh", value)
    }

    public static func formatted(of data: Data) -> String {
        formatted(displayedValue(of: data))
    }

    /// LCD line after 2.C, for example `ChE - - 0A0Ah`.
    public static func testMenuDisplay(_ value: UInt16) -> String {
        "ChE - - \(formatted(value))"
    }

    public static func testMenuDisplay(of data: Data) -> String {
        testMenuDisplay(displayedValue(of: data))
    }

    public static func backupAssessment(of data: Data) -> BackupChecksumAssessment {
        BackupChecksumAssessment(displayed: displayedValue(of: data))
    }

    public static func firmwareFileAssessment(
        of data: Data,
        backup: BackupChecksumAssessment?,
        backupSkipped: Bool
    ) -> FirmwareFileAssessment {
        FirmwareFileAssessment(
            displayed: displayedValue(of: data),
            backup: backupSkipped ? nil : backup
        )
    }

    static func trimmingTrailingZeros(_ data: Data) -> Data {
        var end = data.count
        while end > 0, data[end - 1] == 0 {
            end -= 1
        }
        return data.prefix(end)
    }
}

/// Result of checking a just-saved backup against the known-firmware list.
/// Does not assume which `.bin` the user will flash next.
public struct BackupChecksumAssessment: Equatable, Sendable {
    public let displayed: UInt16
    /// The firmware now on the calculator, when its checksum is in the known list.
    public let known: KnownFirmwareEntry?

    public init(displayed: UInt16) {
        self.displayed = displayed
        self.known = KnownFirmware.find(displayed)
    }

    public var isRecognized: Bool { known != nil }

    /// Default name for saving this firmware, for example `hp15c-ce-original-9090h-20260929.bin`.
    /// Unlisted firmware gets `firmware-1212h-20260929.bin`.
    public func defaultBackupFileName(on date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        let base = known?.fileName ?? "firmware"
        return "\(base)-\(VoyagerFirmwareChecksum.formatted(displayed))-\(formatter.string(from: date)).bin"
    }

    public var message: String {
        let label = VoyagerFirmwareChecksum.formatted(displayed)
        if let known {
            return "Checksum \(label): \(known.displayName). It is safe to proceed."
        }
        return unlistedMessage
    }

    /// The message without "It is safe to proceed.", for showing again after step 3.
    public var summary: String {
        if let known {
            return "Checksum \(VoyagerFirmwareChecksum.formatted(displayed)): \(known.displayName)."
        }
        return unlistedMessage
    }

    private var unlistedMessage: String {
        let label = VoyagerFirmwareChecksum.formatted(displayed)
        return "Checksum \(label). This firmware is not in the list of known versions. If your calculator runs firmware that isn’t listed yet, or a custom version, proceed at your own risk. If it runs a listed version, the firmware may not have been read correctly."
    }
}

/// Verdict for a `.bin` the user picked to flash — independent of the backup dump’s health.
public struct FirmwareFileAssessment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Chosen file matches the backup already on the calculator.
        case alreadyOnCalculator
        /// Listed, and not known to be for a different model.
        case known
        /// Listed, but for a different model than the listed firmware in the backup.
        case otherModel
        /// Not in the known list.
        case unrecognized
    }

    public let kind: Kind
    public let displayed: UInt16
    /// The chosen file, when its checksum is in the known list.
    public let known: KnownFirmwareEntry?
    /// The firmware on the calculator, from the backup. Nil when the backup was skipped or is not listed.
    public let onCalculator: KnownFirmwareEntry?

    public init(displayed: UInt16, backup: BackupChecksumAssessment?) {
        self.displayed = displayed
        self.known = KnownFirmware.find(displayed)
        self.onCalculator = backup?.known

        if let backup, backup.displayed == displayed {
            kind = .alreadyOnCalculator
        } else if let known {
            if let onCalculator, onCalculator.model != known.model {
                kind = .otherModel
            } else {
                kind = .known
            }
        } else {
            kind = .unrecognized
        }
    }

    /// Only a listed file checked against listed firmware on the calculator is free of caution.
    public var isCaution: Bool {
        !(kind == .known && onCalculator != nil)
    }

    public var message: String {
        let label = VoyagerFirmwareChecksum.formatted(displayed)
        switch kind {
        case .alreadyOnCalculator:
            return "Checksum \(label). This firmware is already on the calculator. You don’t need to install it again."
        case .otherModel:
            return "Checksum \(label): \(known!.displayName). Your calculator has \(onCalculator!.model) firmware, so this file is for a different model. Are you sure you want to install it?"
        case .known:
            if onCalculator == nil {
                return "Checksum \(label): \(known!.displayName). Make sure your calculator is an \(known!.model)."
            }
            return "Checksum \(label): \(known!.displayName). It is safe to proceed."
        case .unrecognized:
            return "Checksum \(label). This firmware is not in the list of known versions. Make sure it is made for your calculator’s model. Are you sure you want to install it?"
        }
    }

    /// The message without "It is safe to proceed.", for showing again on step 5.
    public var summary: String {
        if kind == .known, onCalculator != nil, let known {
            return "Checksum \(VoyagerFirmwareChecksum.formatted(displayed)): \(known.displayName)."
        }
        return message
    }
}
