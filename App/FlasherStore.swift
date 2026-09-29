import AppKit
import Foundation
import SwiftUI
import HP15CFlasherCore

enum FlasherMode: String, CaseIterable {
    case demo
    case flash
    case batch
    case probe
}

enum BatchPhase: Equatable {
    case setup
    case waiting
    case backingUp
    case flashing
    case unitDone
    case error
}

enum BatchBackupChoice: String, Equatable {
    case skip
    case autoSave
}

@MainActor
final class FlasherStore: ObservableObject {
    @Published var wizard = WizardState()
    @Published var status = "Waiting for programming cable…"
    @Published var portPath: String?
    @Published var identity: DeviceIdentity?
    @Published var sambaVersion: String?
    @Published var firmwareURL: URL?
    @Published var firmwareDetail = "No firmware selected."
    @Published var expectedChecksumLabel = "ChE - - ----h"
    @Published var backupSkipped = false
    @Published var backupFileName: String?
    /// Firmware read from the calculator on step 3, before the user decides whether to save it.
    @Published var currentFirmware: Data?
    @Published var backupAssessment: BackupChecksumAssessment?
    @Published var firmwareAssessment: FirmwareFileAssessment?
    @Published var progress: Double?
    @Published var progressCaption: String?
    @Published var progressIsVerify = false
    @Published var progressBarID = 0
    @Published var flashPageHeader: String?
    @Published var flashPageLines: [String] = []
    @Published var lastError: String?
    @Published var successMessage: String?
    @Published var confirmFlash = false
    @Published var confirmSkipBackup = false
    @Published var usingSimulator = false
    @Published var showWelcome = true
    @Published var selectedMode: FlasherMode = FlasherStore.savedMode()
    @Published var hasCompletedDemo = UserDefaults.standard.bool(forKey: FlasherStore.demoCompletedDefaultsKey)
    @Published var batchPhase: BatchPhase = .setup
    @Published var batchUnitNumber = 0
    @Published var batchBackupChoice: BatchBackupChoice = .skip
    @Published var batchBackupFolder: URL?

    var isBatchSession: Bool {
        !showWelcome && selectedMode == .batch
    }

    var isProbeSession: Bool {
        !showWelcome && selectedMode == .probe
    }

    var probePortName: String? {
        guard let path = portPath else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard name.lowercased().hasPrefix("cu.usbmodem") else { return nil }
        return name
    }

    var canStartBatch: Bool {
        wizard.firmwareOK && (batchBackupChoice == .skip || batchBackupFolder != nil)
    }

    private var batchSessionStamp: String?
    private var batchUnitWorkTask: Task<Void, Never>?

    private var client: SambaClient?
    private var pollTask: Task<Void, Never>?
    private var flasher = Flasher()
    private var simulator: SimulatedCalculatorTransport?
    private var simulatorHotKeyMonitor: Any?
    private var demoConnectAfter: Date?

    private static let modeDefaultsKey = "flasherMode"
    private static let demoCompletedDefaultsKey = "demoModeCompleted"
    private static let batchFirmwarePathKey = "batchFirmwarePath"
    private static let demoCableDetectedSeconds: TimeInterval = 3

    private static func savedMode() -> FlasherMode {
        if let raw = UserDefaults.standard.string(forKey: modeDefaultsKey),
           let mode = FlasherMode(rawValue: raw) {
            return mode
        }
        return .demo
    }

    private func resetWizardForNewSession() {
        wizard = WizardState()
        firmwareURL = nil
        firmwareDetail = "No firmware selected."
        expectedChecksumLabel = "ChE - - ----h"
        firmwareAssessment = nil
        clearCurrentFirmware()
        wizard.flashSucceeded = false
        lastError = nil
        successMessage = nil
        progress = nil
        progressCaption = nil
        clearFlashPagePreview()
        identity = nil
        portPath = nil
        sambaVersion = nil
        demoConnectAfter = nil
    }

    var canBackup: Bool {
        !wizard.isBusy && client != nil && identity?.isSupported15C == true
    }

    /// Window title and heading while the app is open. FLASH and DEMO follow the calculator found
    /// on step 3; BATCH follows the firmware every unit receives. Welcome and Connection Probe stay
    /// 15CE Flasher, and so does the app's own name (menu bar, Dock, Finder).
    var appTitle: String {
        let model: String?
        if showWelcome || isProbeSession {
            model = nil
        } else if isBatchSession {
            model = firmwareAssessment?.known?.model
        } else {
            model = backupAssessment?.known?.model
        }
        switch model {
        case "16c Collector’s Edition": return "16CE Flasher"
        case "12c": return "12c Flasher"
        default: return "15CE Flasher"
        }
    }

    /// The calculator named by the flashed file, or else by the firmware found on step 3.
    var flashedModelName: String? {
        firmwareAssessment?.known?.modelName ?? backupAssessment?.known?.modelName
    }

    var canSaveBackup: Bool {
        !wizard.isBusy && currentFirmware != nil
    }

    var canFlash: Bool {
        canBackup && wizard.firmwareOK && wizard.backupResolved
    }

    var chipLabel: String {
        identity?.name ?? "Not connected"
    }

    /// Test-menu checksum of the chosen file, for example `0A0Ah`.
    var expectedChecksumShort: String {
        let prefix = "ChE - - "
        guard expectedChecksumLabel.hasPrefix(prefix) else { return "----h" }
        return String(expectedChecksumLabel.dropFirst(prefix.count))
    }

    var stepBanner: (text: String, caution: Bool)? {
        switch wizard.step {
        case .backup:
            // Shown in the step's "Your current firmware" box instead.
            return nil
        case .firmware:
            // Shown in the step's "Selected firmware" box instead.
            return nil
        case .flash:
            // "Flashed and verified." is shown in a green box on step 5.
            return nil
        default:
            return nil
        }
    }

    func start() {
        installSimulatorHotKey()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if !self.showWelcome, !self.isPanelOpen {
                    if self.isProbeSession {
                        await self.refreshProbeConnection()
                    } else if self.isBatchSession {
                        await self.refreshBatchConnection()
                        await self.runBatchStepIfReady()
                    } else {
                        await self.refreshConnection()
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// True while a file chooser or save dialog is up. The connection poll pauses so no
    /// serial I/O or reconnect runs underneath the dialog.
    private var isPanelOpen = false

    private func runPanel(_ panel: NSSavePanel) -> NSApplication.ModalResponse {
        isPanelOpen = true
        defer { isPanelOpen = false }
        return panel.runModal()
    }

    func beginChosenSession() {
        UserDefaults.standard.set(selectedMode.rawValue, forKey: Self.modeDefaultsKey)
        if selectedMode == .batch {
            beginBatchSession()
        } else if selectedMode == .probe {
            resetWizardForNewSession()
            showWelcome = false
            setUsingSimulator(false)
            status = "Waiting for programming cable…"
        } else {
            resetWizardForNewSession()
            showWelcome = false
            setUsingSimulator(selectedMode == .demo)
        }
    }

    func beginBatchSession() {
        batchUnitWorkTask?.cancel()
        batchUnitWorkTask = nil
        resetBatchSession()
        showWelcome = false
        setUsingSimulator(false)
        restoreBatchFirmware()
    }

    private func saveBatchFirmwarePath(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.batchFirmwarePathKey)
    }

    private func restoreBatchFirmware() {
        guard let path = UserDefaults.standard.string(forKey: Self.batchFirmwarePathKey),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            if UserDefaults.standard.string(forKey: Self.batchFirmwarePathKey) != nil {
                UserDefaults.standard.removeObject(forKey: Self.batchFirmwarePathKey)
            }
            return
        }
        applyFirmware(from: URL(fileURLWithPath: path))
    }

    private func resetBatchSession() {
        batchPhase = .setup
        batchUnitNumber = 0
        batchBackupChoice = .skip
        batchBackupFolder = nil
        batchSessionStamp = nil
        firmwareURL = nil
        firmwareDetail = "No firmware selected."
        expectedChecksumLabel = "ChE - - ----h"
        wizard = WizardState()
        firmwareAssessment = nil
        lastError = nil
        successMessage = nil
        progress = nil
        progressCaption = nil
        clearFlashPagePreview()
        identity = nil
        portPath = nil
        sambaVersion = nil
        demoConnectAfter = nil
        disconnect()
    }

    func chooseBatchBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose backup folder"
        panel.message = "Each unit’s backup is saved here as hp15c-YYYYMMDD-HHMMSS-NNN.bin."
        guard runPanel(panel) == .OK, let url = panel.url else { return }
        batchBackupFolder = url
    }

    func startBatch() {
        guard canStartBatch else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        batchSessionStamp = formatter.string(from: Date())
        batchUnitNumber = 1
        batchPhase = .waiting
        lastError = nil
        successMessage = nil
        status = "Waiting for SAM-BA. Hold ERASE, press RESET, then release ERASE."
        disconnect()
    }

    func prepareNextBatchUnit() {
        batchUnitNumber += 1
        batchPhase = .waiting
        lastError = nil
        successMessage = nil
        status = "Waiting for SAM-BA. Hold ERASE, press RESET, then release ERASE."
        disconnect()
    }

    func retryBatchUnit() {
        batchPhase = .waiting
        lastError = nil
        successMessage = nil
        status = "Waiting for SAM-BA. Hold ERASE, press RESET, then release ERASE."
        disconnect()
    }

    func stopBatch() {
        batchUnitWorkTask?.cancel()
        batchUnitWorkTask = nil
        wizard.isBusy = false
        progress = nil
        progressCaption = nil
        clearFlashPagePreview()
        disconnect()
        NSApp.terminate(nil)
    }

    func returnToWelcome() {
        batchUnitWorkTask?.cancel()
        batchUnitWorkTask = nil
        disconnect()
        wizard.identitySupported = false
        wizard.isBusy = false
        lastError = nil
        successMessage = nil
        progress = nil
        progressCaption = nil
        demoConnectAfter = nil
        batchPhase = .setup
        batchUnitNumber = 0
        batchSessionStamp = nil
        firmwareURL = nil
        firmwareDetail = "No firmware selected."
        expectedChecksumLabel = "ChE - - ----h"
        wizard.firmwareOK = false
        firmwareAssessment = nil
        showWelcome = true
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        removeSimulatorHotKey()
        disconnect()
    }

    func advance() {
        wizard.advance()
        if wizard.step == .programmingMode {
            status = usingSimulator
                ? "Cable detected. Hold ERASE, press RESET, then release ERASE."
                : "Waiting for SAM-BA…"
            Task { await refreshConnection() }
        }
        if wizard.step == .backup, currentFirmware == nil, !wizard.backupResolved {
            checkCurrentFirmware()
        }
        if usingSimulator, wizard.step == .checksum {
            markDemoCompleted()
        }
    }

    private func markDemoCompleted() {
        guard !hasCompletedDemo else { return }
        hasCompletedDemo = true
        UserDefaults.standard.set(true, forKey: Self.demoCompletedDefaultsKey)
    }

    func goBack() {
        if wizard.step == .programmingMode {
            disconnect()
            wizard.identitySupported = false
            demoConnectAfter = nil
            clearCurrentFirmware()
        }
        wizard.goBack()
    }

    func chooseFirmware() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose firmware"
        panel.message = "Select a 114,688 (0x1C000) byte file with a .bin extension. This app does not download firmware."
        guard runPanel(panel) == .OK, let url = panel.url else { return }
        applyFirmware(from: url)
    }

    func applyFirmware(from url: URL) {
        do {
            let image = try FirmwareImage.load(from: url)
            firmwareURL = image.url
            let checksum = VoyagerFirmwareChecksum.formatted(of: image.data)
            expectedChecksumLabel = VoyagerFirmwareChecksum.testMenuDisplay(of: image.data)
            firmwareDetail = "\(image.url.lastPathComponent) — \(image.byteCount) bytes, write at 0x04000, checksum \(checksum)"
            wizard.firmwareOK = true
            lastError = nil
            refreshFirmwareAssessment(selected: image.data)
            if isBatchSession {
                saveBatchFirmwarePath(image.url)
            }
        } catch {
            firmwareURL = nil
            firmwareDetail = error.localizedDescription
            expectedChecksumLabel = "ChE - - ----h"
            wizard.firmwareOK = false
            firmwareAssessment = nil
            lastError = error.localizedDescription
            if isBatchSession,
               UserDefaults.standard.string(forKey: Self.batchFirmwarePathKey) == url.path {
                UserDefaults.standard.removeObject(forKey: Self.batchFirmwarePathKey)
            }
        }
    }

    /// Step 3: read the firmware on the calculator and name it from the known list.
    func checkCurrentFirmware() {
        guard !wizard.isBusy else { return }
        clearCurrentFirmware()
        let existing = client
        let tool = flasher
        beginBusy(statusText: "Reading firmware…", caption: "Checking current firmware")
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let samba = try await FlasherStore.preparedClient(existing: existing, tool: tool, store: self)
                let data = try tool.readApplication(client: samba) { fraction, _ in
                    Task { @MainActor in
                        self.progress = fraction
                        self.progressCaption = "Checking current firmware"
                        self.progressIsVerify = false
                    }
                }
                await MainActor.run {
                    self.finishBusySuccess("Firmware checked.") {
                        self.currentFirmware = data
                        self.backupAssessment = VoyagerFirmwareChecksum.backupAssessment(of: data)
                        self.refreshSelectedFirmwareAssessment()
                    }
                }
            } catch {
                await MainActor.run { self.finishBusyFailure(error) }
            }
        }
    }

    /// Saves the firmware already read on step 3. Nothing is read from the calculator again.
    func backup() {
        guard let currentFirmware, let backupAssessment else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = backupAssessment.defaultBackupFileName()
        panel.title = "Save current firmware"
        panel.canCreateDirectories = true
        guard runPanel(panel) == .OK, let url = panel.url else { return }
        do {
            try currentFirmware.write(to: url)
        } catch {
            lastError = error.localizedDescription
            return
        }
        lastError = nil
        successMessage = "Backup saved."
        backupSkipped = false
        backupFileName = url.lastPathComponent
        wizard.backupResolved = true
    }

    func skipBackup() {
        confirmSkipBackup = false
        backupSkipped = true
        backupFileName = nil
        wizard.backupResolved = true
    }

    private func clearCurrentFirmware() {
        currentFirmware = nil
        backupAssessment = nil
        backupSkipped = false
        backupFileName = nil
        wizard.backupResolved = false
        refreshSelectedFirmwareAssessment()
    }

    private func refreshSelectedFirmwareAssessment() {
        if let firmwareURL, let selected = try? Data(contentsOf: firmwareURL) {
            refreshFirmwareAssessment(selected: selected)
        }
    }

    func done() {
        if usingSimulator {
            markDemoCompleted()
        }
        NSApp.terminate(nil)
    }

    func completionDetail(for step: WizardStep) -> String? {
        guard wizard.isComplete(step) else { return nil }
        switch step {
        case .cable:
            return "Pogo cable seated"
        case .programmingMode:
            var parts: [String] = []
            if identity?.isSupported15C == true {
                parts.append(chipLabel)
            }
            if let portPath {
                parts.append(portPath)
            }
            return parts.isEmpty ? "SAM-BA connected" : "Connected \(parts.joined(separator: " · "))"
        case .backup:
            let checksum = backupAssessment.map { " · " + VoyagerFirmwareChecksum.formatted($0.displayed) } ?? ""
            if backupSkipped { return "Backup skipped" + checksum }
            if let backupFileName { return "Saved \(backupFileName)" + checksum }
            return "Backup saved" + checksum
        case .firmware:
            if let name = firmwareURL?.lastPathComponent {
                return "Loaded firmware \(name)"
            }
            return "Firmware selected"
        case .flash:
            return "Flashed and verified at 0x04000"
        case .finish:
            return "RESET, then ON. Pr Error expected"
        case .checksum:
            return nil
        }
    }

    func flash() {
        guard let firmwareURL else { return }
        confirmFlash = false
        performFlash { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.wizard.flashSucceeded = true
            case .failure:
                break
            }
        }
    }

    func performFlash(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let firmwareURL else { return }
        let url = firmwareURL
        let existing = client
        let tool = flasher
        beginBusy(statusText: "Writing firmware…", caption: "Flashing")
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let samba = try await FlasherStore.preparedClient(existing: existing, tool: tool, store: self)
                try tool.write(firmwareURL: url, client: samba, verify: true) { fraction, phase in
                    Task { @MainActor in
                        self.applyFlashProgress(fraction, phase)
                    }
                } pageProgress: { page in
                    Task { @MainActor in
                        self.applyFlashPageWrite(page)
                    }
                }
                await MainActor.run {
                    self.finishFlashSuccess()
                    completion(.success(()))
                }
            } catch {
                await MainActor.run {
                    self.finishBusyFailure(error)
                    completion(.failure(error))
                }
            }
        }
    }

    func performBackup(to url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let existing = client
        let tool = flasher
        beginBusy(statusText: "Reading firmware…", caption: "Backing up")
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let samba = try await FlasherStore.preparedClient(existing: existing, tool: tool, store: self)
                try tool.read(to: url, client: samba) { fraction, _ in
                    Task { @MainActor in
                        self.progress = fraction
                        self.progressCaption = "Backing up"
                        self.progressIsVerify = false
                    }
                }
                await MainActor.run {
                    self.finishBusySuccess("Backup saved.") {}
                    completion(.success(()))
                }
            } catch {
                await MainActor.run {
                    self.finishBusyFailure(error)
                    completion(.failure(error))
                }
            }
        }
    }

    private func installSimulatorHotKey() {
        guard simulatorHotKeyMonitor == nil else { return }
        simulatorHotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isSimulatorToggle(event) else { return event }
            Task { @MainActor in
                guard let self else { return }
                if self.showWelcome {
                    self.cycleWelcomeMode()
                } else if !self.isBatchSession && !self.isProbeSession {
                    self.setUsingSimulator(!self.usingSimulator)
                }
            }
            return nil
        }
    }

    /// ⌘⇧S only. Ignores repeats and leftover modifier combinations.
    private static func isSimulatorToggle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !event.isARepeat, event.keyCode == 1 else { return false }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return mods == [.command, .shift]
    }

    private func removeSimulatorHotKey() {
        if let simulatorHotKeyMonitor {
            NSEvent.removeMonitor(simulatorHotKeyMonitor)
            self.simulatorHotKeyMonitor = nil
        }
    }

    private func cycleWelcomeMode() {
        switch selectedMode {
        case .demo: selectedMode = .flash
        case .flash: selectedMode = .batch
        case .batch: selectedMode = .probe
        case .probe: selectedMode = .demo
        }
    }

    func setUsingSimulator(_ enabled: Bool) {
        disconnect()
        wizard.identitySupported = false
        demoConnectAfter = nil
        usingSimulator = enabled
        if selectedMode != .batch && selectedMode != .probe {
            selectedMode = enabled ? .demo : .flash
            UserDefaults.standard.set(selectedMode.rawValue, forKey: Self.modeDefaultsKey)
        }
        if enabled {
            let sim = SimulatedCalculatorTransport(operationDelay: 0.010, preloadApplication: true)
            simulator = sim
            flasher = Flasher(
                ports: SimulatedPortListing(),
                openTransport: { _ in sim },
                flashCommandSettleSeconds: 0
            )
            status = "DEMO: connecting simulated calculator…"
            Task { await refreshConnection() }
        } else {
            simulator = nil
            flasher = Flasher()
            status = "Waiting for programming cable…"
        }
    }

    private func refreshFirmwareAssessment(selected: Data) {
        // The step 3 check knows the calculator's firmware even when the backup was skipped.
        firmwareAssessment = VoyagerFirmwareChecksum.firmwareFileAssessment(
            of: selected,
            backup: backupAssessment,
            backupSkipped: false
        )
    }

    private func beginBusy(statusText: String, caption: String?) {
        wizard.isBusy = true
        lastError = nil
        successMessage = nil
        progress = 0
        progressCaption = caption
        progressIsVerify = false
        status = statusText
        clearFlashPagePreview()
    }

    private func clearFlashPagePreview() {
        flashPageHeader = nil
        flashPageLines = []
    }

    private func applyFlashPageWrite(_ page: FlashPageWrite) {
        flashPageHeader = page.header
        flashPageLines = page.formattedWordLines()
    }

    private func finishBusySuccess(_ message: String, extra: () -> Void) {
        wizard.isBusy = false
        progress = 1
        progressCaption = nil
        progressIsVerify = false
        clearFlashPagePreview()
        successMessage = message
        status = "Connected: \(chipLabel)"
        extra()
    }

    /// Step 5: keep page 224 and the full verification bar after flash completes.
    private func finishFlashSuccess() {
        wizard.isBusy = false
        progress = 1
        progressCaption = "Verifying"
        progressIsVerify = true
        successMessage = "Flashed and verified."
        status = "Connected: \(chipLabel)"
    }

    private func finishBusyFailure(_ error: Error) {
        wizard.isBusy = false
        progress = nil
        progressCaption = nil
        progressIsVerify = false
        clearFlashPagePreview()
        lastError = error.localizedDescription
        status = "Operation failed."
        disconnect()
        wizard.identitySupported = false
    }

    private func applyFlashProgress(_ fraction: Double, _ phase: FlashProgressPhase) {
        switch phase {
        case .writing:
            progress = min(1, fraction)
            progressCaption = "Flashing"
            progressIsVerify = false
            status = "Writing firmware…"
        case .verifying:
            if !progressIsVerify {
                progress = nil
                progressBarID += 1
                progressCaption = "Verifying"
                progressIsVerify = true
                status = "Verifying firmware…"
            }
            progress = fraction
        case .reading:
            break
        }
    }

    /// Ping/connect on the caller’s executor so flash sleeps never run on the UI thread.
    private nonisolated static func preparedClient(
        existing: SambaClient?,
        tool: Flasher,
        store: FlasherStore
    ) async throws -> SambaClient {
        if let existing {
            do {
                try existing.ping(timeout: 2.0)
                return existing
            } catch {
                await MainActor.run {
                    store.status = "Reconnecting to SAM-BA…"
                    store.disconnect()
                }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        do {
            let connected = try tool.connect(timeout: 3.0)
            await MainActor.run { store.adopt(connected) }
            return connected.client
        } catch {
            if case FlasherError.sambaTimeout = error {
                throw FlasherError.sambaTimeout(
                    "Timed out reconnecting to SAM-BA. Leave the cable plugged in. If Status is not Connected, hold ERASE, press RESET, then release ERASE."
                )
            }
            throw error
        }
    }

    private func adopt(_ connected: ConnectedTarget) {
        client = connected.client
        identity = connected.identity
        portPath = connected.port.path
        sambaVersion = connected.client.version
        wizard.identitySupported = connected.identity.isSupported15C
    }

    private func refreshConnection() async {
        if wizard.isBusy { return }
        // Step 1 is seating the cable. Do not open serial there.
        if wizard.step == .cable { return }
        let cables = (try? flasher.listProgrammingCables()) ?? []
        let modems = cables.filter { $0.name.lowercased().hasPrefix("cu.usbmodem") }
        if cables.isEmpty {
            if client != nil {
                disconnect()
                wizard.identitySupported = false
            }
            status = "Waiting for programming cable…"
            portPath = nil
            return
        }
        if let existing = client {
            if await probePing(existing) {
                return
            }
            disconnect()
            wizard.identitySupported = false
        }
        portPath = modems.first?.path ?? cables.first?.path
        if usingSimulator {
            if demoConnectAfter == nil {
                demoConnectAfter = Date().addingTimeInterval(Self.demoCableDetectedSeconds)
            }
            if let until = demoConnectAfter, Date() < until {
                status = "Cable detected. Hold ERASE, press RESET, then release ERASE."
                return
            }
        }
        if modems.isEmpty {
            status = "Cable detected. Hold ERASE, press RESET, then release ERASE."
            return
        }
        if !usingSimulator {
            status = "Waiting for SAM-BA…"
        }
        let tool = flasher
        let probed = await probeConnect(tool)
        switch probed {
        case .success(let connected):
            adopt(connected)
            if connected.identity.isSupported15C {
                status = "Connected: \(connected.identity.name)"
                lastError = nil
            } else {
                status = "Unsupported chip: \(connected.identity.name)"
                lastError = FlasherError.unsupportedDevice(
                    name: connected.identity.name,
                    cidr: connected.identity.cidr,
                    exid: connected.identity.exid
                ).localizedDescription
            }
        case .failure:
            disconnect()
            wizard.identitySupported = false
            portPath = modems.first?.path ?? cables.first?.path
            status = "Waiting for SAM-BA. Hold ERASE, press RESET, then release ERASE."
        }
    }

    /// Handshake off the main thread. A wedged CDC node must not stall the poll loop.
    private func probeConnect(_ tool: Flasher) async -> Result<ConnectedTarget, Error> {
        await withCheckedContinuation { continuation in
            let gate = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    gate.finish(.success(try tool.connect(timeout: 1.5)))
                } catch {
                    gate.finish(.failure(error))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                gate.finish(.failure(FlasherError.sambaTimeout()))
            }
        }
    }

    /// CHIPID read off the main thread. Detects RESET leaving SAM-BA while USB stays up.
    private func probePing(_ client: SambaClient) async -> Bool {
        await withCheckedContinuation { continuation in
            let gate = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try client.ping(timeout: 1.5)
                    gate.finish(true)
                } catch {
                    gate.finish(false)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
                gate.finish(false)
            }
        }
    }

    private func setStatusIfChanged(_ newStatus: String) {
        guard status != newStatus else { return }
        status = newStatus
    }

    private func refreshProbeConnection() async {
        guard isProbeSession else { return }
        if wizard.isBusy { return }

        let cables = (try? flasher.listProgrammingCables()) ?? []
        let modems = cables.filter { $0.name.lowercased().hasPrefix("cu.usbmodem") }
        let wasConnected = identity?.isSupported15C == true

        if cables.isEmpty {
            releaseClient()
            identity = nil
            portPath = nil
            sambaVersion = nil
            lastError = nil
            setStatusIfChanged("No programming cable detected")
            return
        }

        if modems.isEmpty {
            releaseClient()
            identity = nil
            sambaVersion = nil
            lastError = nil
            portPath = cables.first?.path
            setStatusIfChanged("Cable detected. Hold ERASE, press RESET, then release ERASE.")
            return
        }

        portPath = modems.first?.path

        let probed = await probeConnect(flasher)
        switch probed {
        case .success(let connected):
            let sameChip = identity?.cidr == connected.identity.cidr
                && identity?.exid == connected.identity.exid
            identity = connected.identity
            portPath = connected.port.path
            sambaVersion = connected.client.version
            releaseClient()
            if connected.identity.isSupported15C {
                if !wasConnected || !sameChip {
                    setStatusIfChanged("Connected: \(connected.identity.name)")
                }
                lastError = nil
            } else {
                setStatusIfChanged("Unsupported chip: \(connected.identity.name)")
                lastError = FlasherError.unsupportedDevice(
                    name: connected.identity.name,
                    cidr: connected.identity.cidr,
                    exid: connected.identity.exid
                ).localizedDescription
            }
        case .failure:
            releaseClient()
            identity = nil
            sambaVersion = nil
            lastError = nil
            portPath = modems.first?.path
            if wasConnected {
                setStatusIfChanged("Waiting for SAM-BA. Hold ERASE, press RESET, then release ERASE.")
            } else if !status.hasPrefix("Waiting") && !status.hasPrefix("Cable detected") {
                setStatusIfChanged("Waiting for SAM-BA. Hold ERASE, press RESET, then release ERASE.")
            }
        }
    }

    private func refreshBatchConnection() async {
        guard batchPhase == .waiting || batchPhase == .error else { return }
        if wizard.isBusy || batchUnitWorkTask != nil { return }

        let cables = (try? flasher.listProgrammingCables()) ?? []
        let modems = cables.filter { $0.name.lowercased().hasPrefix("cu.usbmodem") }
        if cables.isEmpty {
            if client != nil {
                disconnect()
            }
            status = "Waiting for programming cable…"
            portPath = nil
            return
        }
        if let existing = client {
            if await probePing(existing) {
                return
            }
            disconnect()
        }
        portPath = modems.first?.path ?? cables.first?.path
        if modems.isEmpty {
            status = "Cable detected. Hold ERASE, press RESET, then release ERASE."
            return
        }
        status = "Waiting for SAM-BA…"
        let tool = flasher
        let probed = await probeConnect(tool)
        switch probed {
        case .success(let connected):
            adopt(connected)
            if connected.identity.isSupported15C {
                status = "Connected: \(connected.identity.name)"
                lastError = nil
            } else {
                status = "Unsupported chip: \(connected.identity.name)"
                lastError = FlasherError.unsupportedDevice(
                    name: connected.identity.name,
                    cidr: connected.identity.cidr,
                    exid: connected.identity.exid
                ).localizedDescription
                batchPhase = .error
            }
        case .failure:
            disconnect()
            portPath = modems.first?.path ?? cables.first?.path
            status = "Waiting for SAM-BA. Hold ERASE, press RESET, then release ERASE."
        }
    }

    private func runBatchStepIfReady() async {
        guard batchPhase == .waiting else { return }
        guard batchUnitWorkTask == nil, !wizard.isBusy else { return }
        guard client != nil, identity?.isSupported15C == true else { return }
        startBatchUnitWork()
    }

    private func startBatchUnitWork() {
        guard batchPhase == .waiting, batchUnitWorkTask == nil, !wizard.isBusy else { return }
        guard firmwareURL != nil else { return }
        let url = firmwareURL!
        batchUnitWorkTask?.cancel()
        batchUnitWorkTask = Task { [weak self] in
            guard let self else { return }
            let firmwareURL = url
            if self.batchBackupChoice == .autoSave,
               let folder = self.batchBackupFolder,
               let stamp = self.batchSessionStamp {
                await MainActor.run {
                    self.batchPhase = .backingUp
                    self.lastError = nil
                }
                let backupURL = BatchBackupNaming.fileURL(
                    in: folder,
                    sessionStamp: stamp,
                    unitNumber: self.batchUnitNumber
                )
                let backupResult = await self.runBackupOperation(to: backupURL)
                if Task.isCancelled { return }
                if case .failure(let error) = backupResult {
                    await MainActor.run {
                        self.batchPhase = .error
                        self.lastError = error.localizedDescription
                        self.batchUnitWorkTask = nil
                    }
                    return
                }
            }
            await MainActor.run {
                self.batchPhase = .flashing
                self.lastError = nil
            }
            let flashResult = await self.runFlashOperation(firmwareURL: firmwareURL)
            if Task.isCancelled { return }
            await MainActor.run {
                switch flashResult {
                case .success:
                    self.batchPhase = .unitDone
                    self.successMessage = "Unit \(self.batchUnitNumber) flashed and verified."
                    self.status = "Unit \(self.batchUnitNumber) complete."
                    self.disconnect()
                case .failure(let error):
                    self.batchPhase = .error
                    self.lastError = error.localizedDescription
                }
                self.batchUnitWorkTask = nil
            }
        }
    }

    private func runBackupOperation(to url: URL) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            performBackup(to: url) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func runFlashOperation(firmwareURL: URL) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            performFlash { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func releaseClient() {
        client?.close()
        client = nil
    }

    private func disconnect() {
        releaseClient()
        identity = nil
        portPath = nil
        sambaVersion = nil
    }
}

private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: T) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: value)
    }
}
