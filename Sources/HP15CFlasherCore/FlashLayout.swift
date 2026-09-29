/// ATSAM4L flash map used by the HP 15c Collector's Edition.
///
/// SAM-BA lives in flash at 0x0000–0x4000. Application firmware starts at
/// 0x4000. Writing below that address can brick the calculator until a
/// debugger rewrites the bootloader.
public enum FlashLayout {
    public static let bootloaderStart: UInt32 = 0x0000
    public static let bootloaderSize: UInt32 = 0x4000
    public static let applicationStart: UInt32 = 0x4000
    /// Size used by SAM-BA 2.18 when reading the 15c CE application image.
    public static let applicationSize: UInt32 = 0x1C000

    public static var applicationEnd: UInt32 {
        applicationStart + applicationSize
    }

    public static var expectedFirmwareByteCount: Int {
        Int(applicationSize)
    }

    /// Returns whether `[address, address + length)` stays inside application flash.
    public static func isSafeApplicationRange(address: UInt32, length: UInt32) -> Bool {
        guard length > 0 else { return false }
        guard address >= applicationStart else { return false }
        let end = address.addingReportingOverflow(length)
        guard !end.overflow else { return false }
        return end.partialValue <= applicationEnd
    }
}
