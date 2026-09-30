import Foundation
@testable import HP15CFlasherCore
import XCTest

final class WizardStateTests: XCTestCase {
    func testCableAlwaysAllowsAdvance() {
        var state = WizardState()
        XCTAssertTrue(state.canAdvance)
        state.advance()
        XCTAssertEqual(state.step, .programmingMode)
    }

    func testCannotLeaveProgrammingModeWithoutSupportedChip() {
        var state = WizardState()
        state.step = .programmingMode
        XCTAssertFalse(state.canAdvance)
        state.advance()
        XCTAssertEqual(state.step, .programmingMode)

        state.identitySupported = true
        XCTAssertTrue(state.canAdvance)
        state.advance()
        XCTAssertEqual(state.step, .backup)
    }

    func testBackupRequiresResolvedOrSkip() {
        var state = WizardState()
        state.step = .backup
        XCTAssertFalse(state.canAdvance)
        state.backupResolved = true
        XCTAssertTrue(state.canAdvance)
    }

    func testCannotFlashAdvanceWithoutFirmwareAndSuccess() {
        var state = WizardState()
        state.step = .firmware
        XCTAssertFalse(state.canAdvance)

        state.firmwareOK = true
        state.advance()
        XCTAssertEqual(state.step, .flash)
        XCTAssertFalse(state.canAdvance)

        state.flashSucceeded = true
        state.advance()
        XCTAssertEqual(state.step, .finish)
        XCTAssertTrue(state.canAdvance)

        state.advance()
        XCTAssertEqual(state.step, .checksum)
        XCTAssertFalse(state.canAdvance)
        XCTAssertEqual(WizardStep.count, 7)
    }

    func testBusyBlocksBackAndAdvance() {
        var state = WizardState()
        state.identitySupported = true
        state.step = .programmingMode
        state.isBusy = true
        XCTAssertFalse(state.canAdvance)
        XCTAssertFalse(state.canGoBack)
        state.isBusy = false
        XCTAssertTrue(state.canGoBack)
        state.goBack()
        XCTAssertEqual(state.step, .cable)
        XCTAssertFalse(state.canGoBack)
    }

    func testCompletedStepsAreThoseAlreadyLeft() {
        var state = WizardState()
        XCTAssertFalse(state.isComplete(.cable))
        XCTAssertTrue(state.isUpcoming(.programmingMode))

        state.identitySupported = true
        state.advance()
        state.advance()
        XCTAssertEqual(state.step, .backup)
        XCTAssertTrue(state.isComplete(.cable))
        XCTAssertTrue(state.isComplete(.programmingMode))
        XCTAssertFalse(state.isComplete(.backup))
        XCTAssertFalse(state.isUpcoming(.backup))
        XCTAssertTrue(state.isUpcoming(.firmware))
    }

    func testFirmwareFileMustBe112KBBeforeFlash() throws {
        var state = WizardState()
        state.step = .firmware
        XCTAssertThrowsError(try FirmwareImage.validate(Data(count: 16)))
        let valid = Data(count: FlashLayout.expectedFirmwareByteCount)
        XCTAssertNoThrow(try FirmwareImage.validate(valid))
        state.firmwareOK = true
        XCTAssertTrue(state.canAdvance)
    }
}

final class VoyagerFirmwareChecksumTests: XCTestCase {
    func testRepeatedByteFromAdditiveSum() {
        var payload = Data(repeating: 0x01, count: 9)
        payload.append(0x09)
        payload.append(contentsOf: Data(repeating: 0, count: 8))
        XCTAssertEqual(VoyagerFirmwareChecksum.displayedValue(of: payload), 0x0909)
        XCTAssertEqual(VoyagerFirmwareChecksum.formatted(of: payload), "0909h")
    }

    func testOfficialStyle0A0APattern() {
        var payload = Data(repeating: 0x02, count: 5)
        payload.append(0x0A)
        XCTAssertEqual(VoyagerFirmwareChecksum.formatted(of: payload), "0A0Ah")
        XCTAssertEqual(VoyagerFirmwareChecksum.testMenuDisplay(of: payload), "ChE - - 0A0Ah")
    }

    func testKnownFirmwareListLoads() {
        XCTAssertFalse(KnownFirmware.all.isEmpty)
        XCTAssertEqual(KnownFirmware.find(0x9090)?.model, "15c Collector’s Edition")
        XCTAssertEqual(KnownFirmware.find(0x0E0E)?.model, "16c Collector’s Edition")
        XCTAssertNil(KnownFirmware.find(0x1234))
    }

    func testEveryKnownChecksumRepeatsItsByte() {
        // The calculator shows the 8-bit sum twice, so a real checksum is always XYXYh.
        for entry in KnownFirmware.all {
            XCTAssertEqual(entry.checksum >> 8, entry.checksum & 0xFF, VoyagerFirmwareChecksum.formatted(entry.checksum))
        }
    }

    func testKnownFirmwareParseRejectsBadLists() {
        let bad = [
            #"{"firmware":[{"checksum":"0x9090","model":"15c Collector’s Edition","fileName":"x","description":"a"},{"checksum":"9090","model":"15c Collector’s Edition","fileName":"x","description":"b"}]}"#,
            #"{"firmware":[{"checksum":"0x9090","model":"15C","fileName":"x","description":"a"}]}"#,
            #"{"firmware":[{"checksum":"0xZZ","model":"15c Collector’s Edition","fileName":"x","description":"a"}]}"#,
            #"{"firmware":[{"checksum":"0x9090","model":"15c Collector’s Edition","fileName":"HP 15c","description":"a"}]}"#,
            #"{"firmware":[{"checksum":"0x9090","model":"15c Collector’s Edition","description":"a"}]}"#,
        ]
        for json in bad {
            XCTAssertThrowsError(try KnownFirmware.parse(Data(json.utf8)), json)
        }
    }

    func testModelName() {
        XCTAssertEqual(KnownFirmware.find(0x9090)?.modelName, "HP 15c Collector’s Edition")
        XCTAssertEqual(KnownFirmware.find(0x0E0E)?.modelName, "HP 16c Collector’s Edition")
        XCTAssertEqual(KnownFirmwareEntry(checksum: 0x1111, model: "12c", fileName: "x", description: "x").modelName, "HP 12c")
    }

    func testDefaultBackupFileName() {
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 9, day: 29, hour: 12).date!
        XCTAssertEqual(BackupChecksumAssessment(displayed: 0x9090).defaultBackupFileName(on: date), "hp15c-ce-original-9090h-20260929.bin")
        XCTAssertEqual(BackupChecksumAssessment(displayed: 0x0E0E).defaultBackupFileName(on: date), "hp16c-ce-original-0E0Eh-20260929.bin")
        XCTAssertEqual(BackupChecksumAssessment(displayed: 0x1212).defaultBackupFileName(on: date), "firmware-1212h-20260929.bin")
    }

    func testBackupNamesKnownFirmware() {
        let assessment = VoyagerFirmwareChecksum.backupAssessment(of: Data([0x0A, 0x0A]))
        XCTAssertTrue(assessment.isRecognized)
        XCTAssertTrue(assessment.message.contains("June 2024"))
        XCTAssertTrue(assessment.message.contains("safe to proceed"))
        XCTAssertFalse(assessment.summary.contains("safe to proceed"))
        XCTAssertTrue(assessment.summary.hasSuffix("backup and restore."))
    }

    func testBackupOfUnlistedFirmwareIsNotBlamedOnTheUser() {
        let assessment = VoyagerFirmwareChecksum.backupAssessment(of: Data([0x01, 0x01]))
        XCTAssertFalse(assessment.isRecognized)
        XCTAssertTrue(assessment.message.hasPrefix("Checksum 0101h."))
        XCTAssertTrue(assessment.message.contains("not in the list of known versions"))
    }

    func testFirmwareFileAgainstBackup() {
        let cases: [(onCalculator: UInt16, file: UInt16, kind: FirmwareFileAssessment.Kind)] = [
            (0x0A0A, 0x0A0A, .alreadyOnCalculator),
            (0x0A0A, 0x9090, .known),
            (0x9090, 0x0E0E, .otherModel),
            (0x0E0E, 0x0A0A, .otherModel),
            (0x0E0E, 0x8989, .known),
            (0x8989, 0x9090, .otherModel),
            (0x1212, 0x0E0E, .known),
            (0x9090, 0x1212, .unrecognized),
        ]
        for c in cases {
            let assessment = FirmwareFileAssessment(displayed: c.file, backup: BackupChecksumAssessment(displayed: c.onCalculator))
            XCTAssertEqual(assessment.kind, c.kind, "\(c.onCalculator) -> \(c.file)")
        }
    }

    func testCautionOnlyWhenModelCannotBeConfirmed() {
        let checked = FirmwareFileAssessment(displayed: 0x0A0A, backup: BackupChecksumAssessment(displayed: 0x9090))
        XCTAssertFalse(checked.isCaution)
        XCTAssertTrue(checked.message.contains("safe to proceed"))
        XCTAssertEqual(checked.summary, "Checksum 0A0Ah: \(KnownFirmware.find(0x0A0A)!.displayName).")

        let skipped = VoyagerFirmwareChecksum.firmwareFileAssessment(of: Data([0x0E, 0x0E]), backup: nil, backupSkipped: true)
        XCTAssertEqual(skipped.kind, .known)
        XCTAssertTrue(skipped.isCaution)
        XCTAssertTrue(skipped.message.contains("Make sure your calculator is an HP 16c"))
    }

    func testOtherModelNamesBothModels() {
        let assessment = FirmwareFileAssessment(displayed: 0x0E0E, backup: BackupChecksumAssessment(displayed: 0x9090))
        XCTAssertTrue(assessment.isCaution)
        XCTAssertTrue(assessment.message.contains("16c Collector’s Edition original firmware"))
        XCTAssertTrue(assessment.message.contains("Your calculator has HP 15c Collector’s Edition firmware"))
    }
}

final class BatchBackupNamingTests: XCTestCase {
    func testNumberedBackupFilename() {
        XCTAssertEqual(
            BatchBackupNaming.filename(sessionStamp: "20260904-141530", unitNumber: 1),
            "hp15c-20260904-141530-001.bin"
        )
        XCTAssertEqual(
            BatchBackupNaming.filename(sessionStamp: "20260904-141530", unitNumber: 12),
            "hp15c-20260904-141530-012.bin"
        )
    }

    func testNumberedBackupFileURL() {
        let folder = URL(fileURLWithPath: "/tmp/backups")
        let url = BatchBackupNaming.fileURL(in: folder, sessionStamp: "20260904-141530", unitNumber: 3)
        XCTAssertEqual(url.lastPathComponent, "hp15c-20260904-141530-003.bin")
        XCTAssertEqual(url.deletingLastPathComponent().path, "/tmp/backups")
    }
}

final class SimulatedCalculatorTests: XCTestCase {
    func testFlashPageWriteFormatsLittleEndianWords() {
        var page = Data(repeating: 0, count: 4)
        page[0] = 0x90
        page[1] = 0x90
        page[2] = 0x0A
        page[3] = 0x0A
        let write = FlashPageWrite(flashOffset: 0x04000, pageIndex: 0, pageCount: 224, pageData: page)
        XCTAssertEqual(write.header, "Page 1 of 224 · 0x04000")
        XCTAssertEqual(write.formattedWordLines(), ["9090 0A0A"])
    }

    func testDelayedWriteReportsIncreasingProgress() throws {
        let sim = SimulatedCalculatorTransport(operationDelay: 0.002, preloadApplication: true)
        let client = SambaClient(transport: sim)
        try client.connect()

        var image = Data(count: FlashLayout.expectedFirmwareByteCount)
        image[0] = 0x5A

        var samples: [Double] = []
        let started = Date()
        try FlashCalw(samba: client).writeApplication(image, progress: { fraction in
            samples.append(fraction)
        })
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertGreaterThan(elapsed, 0.3)
        XCTAssertGreaterThan(samples.count, 5)
        let pairs = zip(samples, samples.dropFirst())
        XCTAssertTrue(pairs.allSatisfy { $0 <= $1 })
        XCTAssertEqual(samples.last, 1.0)
    }

    func testFlasherConnectsToSimulatedPort() throws {
        let sim = SimulatedCalculatorTransport(preloadApplication: true)
        let flasher = Flasher(
            ports: SimulatedPortListing(),
            openTransport: { _ in sim }
        )
        let connected = try flasher.connect()
        XCTAssertTrue(connected.identity.isSupported15C)
        XCTAssertEqual(connected.port.path, SimulatedCalculatorTransport.demoPort.path)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sim-backup-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        try flasher.read(to: url, client: connected.client)
        let saved = try Data(contentsOf: url)
        XCTAssertEqual(saved.count, FlashLayout.expectedFirmwareByteCount)
        XCTAssertEqual(VoyagerFirmwareChecksum.backupAssessment(of: saved).known?.checksum, 0x9090)
    }

    func testSimulatedSequentialFlashWrites() throws {
        let sim = SimulatedCalculatorTransport(operationDelay: 0, preloadApplication: true)
        let flasher = Flasher(
            ports: SimulatedPortListing(),
            openTransport: { _ in sim },
            flashCommandSettleSeconds: 0
        )
        var image = Data(count: FlashLayout.expectedFirmwareByteCount)
        image[0] = 0x5A
        image[1] = 0xA5

        for _ in 0..<2 {
            let connected = try flasher.connect()
            defer { connected.client.close() }
            try FlashCalw(samba: connected.client).writeApplication(image, verify: true)
        }
    }
}
