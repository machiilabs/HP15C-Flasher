import Foundation

/// One firmware the app recognizes by its test-menu checksum.
public struct KnownFirmwareEntry: Equatable, Sendable {
    public let checksum: UInt16
    /// `15c Collector’s Edition`, `16c Collector’s Edition`, or `12c`.
    public let model: String
    /// Start of the default backup name, for example `hp15c-ce-original`.
    public let fileName: String
    /// The firmware version, without the model, for example `original firmware`.
    public let description: String

    /// `HP 15c Collector’s Edition`, `HP 16c Collector’s Edition`, or `HP 12c`.
    public var modelName: String { "HP \(model)" }

    /// Model and version, for example `HP 15c Collector’s Edition original firmware`.
    public var displayName: String { "\(modelName) \(description)" }
}

/// The known-firmware list in `known-firmware.json` (a package resource).
/// The Windows app keeps an identical copy, so edit the JSON rather than adding entries here.
public enum KnownFirmware {
    public static let models = ["15c Collector’s Edition", "16c Collector’s Edition", "12c"]

    public static let all: [KnownFirmwareEntry] = {
        guard let url = Bundle.module.url(forResource: "known-firmware", withExtension: "json") else {
            fatalError("known-firmware.json is missing from the HP15CFlasherCore bundle.")
        }
        do {
            return try parse(Data(contentsOf: url))
        } catch {
            fatalError("known-firmware.json is invalid: \(error)")
        }
    }()

    public static func find(_ checksum: UInt16) -> KnownFirmwareEntry? {
        all.first { $0.checksum == checksum }
    }

    public struct ListError: Error, CustomStringConvertible {
        public let description: String
    }

    private struct File: Decodable {
        struct Item: Decodable {
            let checksum: String
            let model: String
            let fileName: String
            let description: String
        }
        let firmware: [Item]
    }

    static func parse(_ json: Data) throws -> [KnownFirmwareEntry] {
        var entries: [KnownFirmwareEntry] = []
        for item in try JSONDecoder().decode(File.self, from: json).firmware {
            let hex = item.checksum.lowercased().hasPrefix("0x") ? String(item.checksum.dropFirst(2)) : item.checksum
            guard hex.count <= 4, let checksum = UInt16(hex, radix: 16) else {
                throw ListError(description: "Known firmware checksum \"\(item.checksum)\" is not a 4-digit hex value.")
            }
            guard models.contains(item.model) else {
                throw ListError(description: "Known firmware model \"\(item.model)\" must be one of \(models.joined(separator: ", ")).")
            }
            guard !item.fileName.isEmpty,
                  item.fileName.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }) else {
                throw ListError(description: "Known firmware fileName \"\(item.fileName)\" may use only lowercase letters, digits, and hyphens.")
            }
            guard !entries.contains(where: { $0.checksum == checksum }) else {
                throw ListError(description: "Known firmware checksum \(item.checksum) is listed twice.")
            }
            entries.append(KnownFirmwareEntry(checksum: checksum, model: item.model, fileName: item.fileName, description: item.description))
        }
        return entries
    }
}
