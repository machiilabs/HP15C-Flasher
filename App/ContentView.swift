import SwiftUI
import HP15CFlasherCore

struct ContentView: View {
    @EnvironmentObject private var store: FlasherStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if store.showWelcome {
                WelcomeView()
            } else if store.isProbeSession {
                ProbeView()
            } else if store.isBatchSession {
                BatchView()
            } else {
                wizardColumn
                    .padding(24)
                    .frame(minWidth: 900, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity, alignment: .topLeading)
            }
        }
            .confirmationDialog(
            store.usingSimulator ? "Flash the simulated calculator?" : "Flash the calculator?",
            isPresented: $store.confirmFlash,
            titleVisibility: .visible
        ) {
            Button("Flash at 0x04000", role: .destructive, action: store.flash)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.usingSimulator
                 ? "DEMO writes only the simulated calculator on this Mac. A real calculator is not changed."
                 : "FLASH writes a real calculator. User memory will be wiped. The bootloader at 0x0000–0x3FFF is not overwritten.")
        }
        .confirmationDialog(
            "Skip backup?",
            isPresented: $store.confirmSkipBackup,
            titleVisibility: .visible
        ) {
            Button("Skip backup", role: .destructive, action: store.skipBackup)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If the new firmware misbehaves, you will not have a copy of what is on the calculator now.")
        }
    }

    private var wizardColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(alignment: .top, spacing: 20) {
                stepSidebar
                VStack(alignment: .leading, spacing: 16) {
                    stepBody
                    if let progress = store.progress,
                       store.wizard.isBusy || (store.wizard.step == .flash && store.wizard.flashSucceeded) {
                        labeledProgress(
                            store.progressCaption ?? "Working",
                            value: progress,
                            tint: store.progressIsVerify ? .green : (store.progressCaption == "Flashing" ? .blue : Color.accentColor),
                            identity: store.progressBarID
                        )
                        if store.wizard.step == .flash, let header = store.flashPageHeader {
                            flashPagePreview(header: header, lines: store.flashPageLines)
                        }
                    }
                    if store.wizard.step == .flash, store.wizard.flashSucceeded {
                        firmwareMessageBox([(label: "", message: "Flashed and verified.")], caution: false)
                    }
                    if let banner = store.stepBanner {
                        wrappingText(banner.text)
                            .foregroundStyle(banner.caution ? Color.orange : Color.green)
                            .textSelection(.enabled)
                    }
                    if let error = store.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    navigation
                    Text("\(Bundle.main.appVersionLabel) · Mach II Labs · offline · no telemetry · free forever")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.appTitle)
                    .font(.largeTitle.weight(.semibold))
                Text(store.usingSimulator
                     ? "DEMO — simulated Collector’s Edition"
                     : "Native SAM-BA programmer for the post-2015 Voyager series")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.usingSimulator {
                Text("DEMO")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
            if store.identity != nil {
                Text(store.chipLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                stepInstruction
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stepInstruction: some View {
        switch store.wizard.step {
        case .cable:
            CableDiagram()
            wrappingText("Open the calculator's battery door and insert the POGO cable. The connector is keyed; the POGO can only be inserted one way. Make sure the plug snaps securely into place.")
            wrappingText("Plug the other end of the cable (USB-A or USB-C) into this Mac.")
            if store.usingSimulator {
                wrappingText("DEMO uses a simulated calculator. You do not need a cable. Follow the same steps so FLASH is familiar later.")
                    .foregroundStyle(.secondary)
            }
            warningBox("Use the POGO cable only on post-2015 Voyager calculators (15c CE, 16c CE, 12c). Do not use the cable on an HP 15c Limited Edition, a pre-2015 12c, an HP 20b, or an HP 30b, as it could permanently damage your calculator.")
        case .programmingMode:
            ProgrammingModeDiagram()
            wrappingText("On the cable's switch box, hold ERASE, press RESET, then release ERASE. The display stays off. The calculator's ON button is ignored in this state.")
            if store.usingSimulator {
                wrappingText("DEMO connects the simulated calculator automatically. Continue when it appears below.")
                    .foregroundStyle(.secondary)
            }
            connectionStatus
            wrappingText("Once your calculator is recognized (“Connected: ATSAM4LC2C” is shown), continue with the next step.")
                .foregroundStyle(.secondary)
        case .backup:
            if store.currentFirmware == nil {
                if store.wizard.isBusy {
                    wrappingText("Checking the firmware on the calculator…")
                } else {
                    wrappingText("Read the firmware on the calculator to see which version it has.")
                    Button("Check Firmware", action: store.checkCurrentFirmware)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                if let assessment = store.backupAssessment {
                    firmwareMessageBox("Your current firmware:", assessment.message, caution: !assessment.isRecognized)
                }
                wrappingText("Do you want to save a backup of this firmware? You can use it to restore the calculator later.")
                HStack {
                    Button("Save Backup…", action: store.backup)
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.canSaveBackup)
                    Button("Skip") { store.confirmSkipBackup = true }
                        .disabled(store.wizard.isBusy)
                }
                if store.wizard.backupResolved, !store.backupSkipped, let name = store.backupFileName {
                    firmwareMessageBox([(label: "", message: "Backup saved as \(name).")], caution: false)
                }
                if store.backupSkipped {
                    firmwareMessageBox(
                        [(label: "", message: "Backup skipped. You may not have a copy of this firmware to restore later.")],
                        caution: false,
                        tone: .amber
                    )
                }
            }
        case .firmware:
            if let current = store.backupAssessment {
                firmwareMessageBox("Your current firmware:", current.summary, caution: !current.isRecognized, tone: .carriedOver)
            }
            wrappingText("Choose a 114,688 (0x1C000) byte file with .bin extension. This app does not download HP firmware.")
            if store.wizard.firmwareOK {
                Button("Choose Firmware…", action: store.chooseFirmware)
                    .disabled(store.wizard.isBusy)
            } else {
                Button("Choose Firmware…", action: store.chooseFirmware)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.wizard.isBusy)
            }
            if store.wizard.firmwareOK, let name = store.firmwareURL?.lastPathComponent {
                wrappingText(name)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            if let assessment = store.firmwareAssessment {
                firmwareMessageBox("Selected firmware:", assessment.message, caution: assessment.isCaution)
            }
        case .flash:
            flashFirmwareSummary
            wrappingText("Write starts at address 0x04000. The SAM-BA bootloader below that address is left intact.")
            if store.wizard.flashSucceeded {
                Button(store.usingSimulator ? "Flash Simulated Calculator" : "Flash Calculator") {
                    store.confirmFlash = true
                }
                .disabled(!store.canFlash)
            } else {
                Button(store.usingSimulator ? "Flash Simulated Calculator" : "Flash Calculator") {
                    store.confirmFlash = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!store.canFlash)
            }
            connectionStatus
        case .finish:
            FinishDiagram()
            wrappingText("Press RESET on the cable switch-box, then turn the calculator ON. “Pr Error” in the display is expected. Press any key to see 0.0000.")
        case .checksum:
            ChecksumDiagram()
            wrappingText("Turn the calculator OFF (press ON button). Hold g and ENTER, then press ON. Release ON, then release g and ENTER.")
            wrappingText("The display shows the test menu: “1.L 2.C 3.H”. Press 2.")
            HStack(alignment: .center, spacing: 8) {
                Text("You should see")
                CalculatorDisplay(store.expectedChecksumLabel)
            }
            wrappingText("That value is the checksum of the installed firmware (the one you just flashed). Press ON a few times to exit the test menu.")
                .foregroundStyle(.secondary)
            wrappingText("If you received the expected checksum of \(store.expectedChecksumShort), then congratulations — you have successfully updated the firmware on your \(store.flashedModelName ?? "calculator").")
            wrappingText("If you received a different checksum, all is not lost. A retry with either the new firmware or the original backup is likely to succeed.")
        }
    }

    private func wrappingText(_ text: String) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledProgress(_ title: String, value: Double, tint: Color? = nil, identity: Int = 0) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(tint ?? Color.accentColor)
                .animation(nil, value: identity)
                .id(identity)
                .accessibilityLabel(title)
        }
    }

    private func warningBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.black)
                .accessibilityHidden(true)
            wrappingText(text)
                .foregroundStyle(.black)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel("Warning. \(text)")
    }

    /// Step 5 repeats both step 4 messages in one box.
    @ViewBuilder
    private var flashFirmwareSummary: some View {
        let current = store.backupAssessment
        let selected = store.firmwareAssessment
        let lines = [
            current.map { ("Your current firmware:", $0.summary) },
            selected.map { ("Selected firmware:", $0.summary) },
        ].compactMap { $0 }
        if !lines.isEmpty {
            firmwareMessageBox(
                lines,
                caution: (current.map { !$0.isRecognized } ?? false) || (selected?.isCaution ?? false),
                tone: .carriedOver
            )
        }
    }

    private func firmwareMessageBox(_ label: String, _ message: String, caution: Bool, tone: MessageTone? = nil) -> some View {
        firmwareMessageBox([(label, message)], caution: caution, tone: tone)
    }

    /// Message colors: green and amber for a message appearing for the first time,
    /// blue (the current sidebar step's colors) for a message carried over from an earlier step.
    private enum MessageTone {
        case green
        /// A caution, or a choice worth noting. Not an error.
        case amber
        case carriedOver
    }

    /// Step 3–5 messages. Without a tone, a new message is green, or amber when it is a caution.
    /// A caution also adds a warning icon.
    private func firmwareMessageBox(
        _ lines: [(label: String, message: String)],
        caution: Bool,
        tone: MessageTone? = nil
    ) -> some View {
        let dark = colorScheme == .dark
        let ink: Color
        let accent: Color
        switch tone ?? (caution ? .amber : .green) {
        case .green:
            ink = dark ? Color(red: 0.62, green: 0.90, blue: 0.68) : Color(red: 0.05, green: 0.33, blue: 0.14)
            accent = sidebarGreen
        case .amber:
            ink = dark ? Color(red: 1.00, green: 0.80, blue: 0.50) : Color(red: 0.45, green: 0.25, blue: 0.00)
            accent = Color(red: 0.96, green: 0.62, blue: 0.04)
        case .carriedOver:
            ink = .primary
            accent = sidebarBlue
        }
        return HStack(alignment: .top, spacing: 8) {
            if caution {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines.indices, id: \.self) { index in
                    (lines[index].label.isEmpty
                        ? Text(lines[index].message)
                        : Text(lines[index].label + " ").bold() + Text(lines[index].message))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(accent.opacity(dark ? 0.18 : (tone == .carriedOver ? 0.10 : 0.14)))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(accent.opacity(0.85), lineWidth: 1.5)
                }
        }
        .accessibilityElement(children: .combine)
    }

    private var sidebarGreen: Color { Color(red: 0.20, green: 0.78, blue: 0.40) }
    private var sidebarBlue: Color { Color(red: 0.18, green: 0.47, blue: 0.98) }

    private var stepSidebar: some View {
        let steps = WizardStep.allCases
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                sidebarRow(step)
                if index < steps.count - 1 {
                    sidebarConnector(after: step)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 196, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func sidebarRow(_ step: WizardStep) -> some View {
        let complete = store.wizard.isComplete(step)
        let upcoming = store.wizard.isUpcoming(step)
        let current = store.wizard.step == step
        return HStack(alignment: .center, spacing: 10) {
            sidebarMarker(step, complete: complete, current: current, upcoming: upcoming)
            Text("\(step.number). \(step.title)")
                .font(.callout.weight(current ? .semibold : .medium))
                .foregroundStyle(upcoming ? Color.secondary : Color.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background {
            if current {
                Capsule(style: .continuous)
                    .fill(sidebarBlue.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    .shadow(color: sidebarBlue.opacity(0.35), radius: 6, y: 1)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(sidebarBlue.opacity(0.85), lineWidth: 1.5)
                    }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(checklistAccessibilityLabel(step, complete: complete, upcoming: upcoming))
    }

    private func sidebarMarker(_ step: WizardStep, complete: Bool, current: Bool, upcoming: Bool) -> some View {
        ZStack {
            if complete {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [sidebarGreen.opacity(0.95), sidebarGreen.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: sidebarGreen.opacity(0.35), radius: 2, y: 1)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            } else if current {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [sidebarBlue.opacity(0.98), sidebarBlue.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: sidebarBlue.opacity(0.4), radius: 3, y: 1)
                Text("\(step.number)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.28 : 0.18))
                Text("\(step.number)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .opacity(upcoming ? 0.85 : 1)
    }

    private func sidebarConnector(after step: WizardStep) -> some View {
        let next = WizardStep(rawValue: step.rawValue + 1)
        let toCurrent = next == store.wizard.step
        let toComplete = next.map { store.wizard.isComplete($0) } ?? false
        let color: Color = {
            if toComplete { return sidebarGreen }
            if toCurrent { return sidebarBlue }
            return Color.secondary.opacity(0.35)
        }()
        return HStack(spacing: 0) {
            Group {
                if toComplete || toCurrent {
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: 16)
                } else {
                    Capsule()
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 2, height: 16)
                }
            }
            .padding(.leading, 18)
            Spacer(minLength: 0)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    private func checklistAccessibilityLabel(_ step: WizardStep, complete: Bool, upcoming: Bool) -> String {
        var label = "\(step.number). \(step.title)"
        if complete {
            label += ", completed"
            if let detail = store.completionDetail(for: step) {
                label += ", \(detail)"
            }
        } else if upcoming {
            label += ", not started"
        } else {
            label += ", current"
        }
        return label
    }

    private func flashPagePreview(header: String, lines: [String]) -> some View {
        let well = colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.18)
        let ink = Color(white: colorScheme == .dark ? 0.86 : 0.92)
        return VStack(alignment: .leading, spacing: 6) {
            Text(header)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flash page data. \(header)")
    }

    private var connectionStatus: some View {
        let well = colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.18)
        let ink = Color(white: colorScheme == .dark ? 0.86 : 0.92)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Status  \(store.status)")
            Text("Port    \(store.portPath ?? "—")")
            Text("SAM-BA  \(store.sambaVersion ?? "—")")
        }
        .font(.system(size: 14, weight: .regular, design: .monospaced))
        .foregroundStyle(ink)
        .textSelection(.enabled)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var navigation: some View {
        HStack {
            if store.wizard.step == .cable {
                Button("Back", action: store.returnToWelcome)
            } else if store.wizard.canGoBack {
                Button("Back", action: store.goBack)
            }
            Spacer()
            if store.wizard.step == .checksum {
                Button("Done", action: store.done)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue", action: store.advance)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.wizard.canAdvance)
            }
        }
    }
}

extension Bundle {
    var appVersionLabel: String {
        let marketing = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(marketing) (\(build))"
    }
}
