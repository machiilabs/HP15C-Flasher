import SwiftUI
import HP15CFlasherCore

struct BatchView: View {
    @EnvironmentObject private var store: FlasherStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if store.batchPhase == .setup {
                        setupBody
                    } else {
                        runBody
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.wizard.isBusy, let progress = store.progress {
                labeledProgress(
                    store.progressCaption ?? "Working",
                    value: progress,
                    tint: store.progressIsVerify ? .green : (store.progressCaption == "Flashing" ? .blue : Color.accentColor),
                    identity: store.progressBarID
                )
                if store.progressCaption == "Flashing", let header = store.flashPageHeader {
                    flashPagePreview(header: header, lines: store.flashPageLines)
                }
            }

            if let error = store.lastError, store.batchPhase == .error {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
            footer
            Text("\(Bundle.main.appVersionLabel) · Mach II Labs · offline · no telemetry · free forever")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.appTitle)
                    .font(.largeTitle.weight(.semibold))
                Text(store.batchPhase == .setup
                     ? "BATCH — sequential flash"
                     : "BATCH — unit \(max(store.batchUnitNumber, 1))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("BATCH")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.22), in: Capsule())
        }
    }

    @ViewBuilder
    private var setupBody: some View {
        Text("Flash many Collector’s Editions in sequence with the same firmware. Choose settings once, then repeat ERASE+RESET for each unit.")
            .fixedSize(horizontal: false, vertical: true)
        Text("For experienced operators. Not for first-time users.")
            .foregroundStyle(.secondary)

        Divider()

        Text("Firmware")
            .font(.headline)
        Text("Choose a 114,688 (0x1C000) byte .bin file. This app does not download HP firmware.")
            .foregroundStyle(.secondary)
        if store.wizard.firmwareOK {
            Button("Choose Firmware…", action: store.chooseFirmware)
        } else {
            Button("Choose Firmware…", action: store.chooseFirmware)
                .buttonStyle(.borderedProminent)
        }
        if store.wizard.firmwareOK, let name = store.firmwareURL?.lastPathComponent {
            Text(name)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Text("Expected checksum: \(store.expectedChecksumShort)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Divider()

        Text("Backup for each unit")
            .font(.headline)
        Picker("Backup", selection: $store.batchBackupChoice) {
            Text("Skip backup").tag(BatchBackupChoice.skip)
            Text("Save to folder…").tag(BatchBackupChoice.autoSave)
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if store.batchBackupChoice == .autoSave {
            HStack {
                Button("Choose folder…", action: store.chooseBatchBackupFolder)
                if let folder = store.batchBackupFolder {
                    Text(folder.path)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Each unit saves as hp15c-YYYYMMDD-HHMMSS-NNN.bin in that folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var runBody: some View {
        switch store.batchPhase {
        case .waiting:
            Text("Hold ERASE, press RESET, then release ERASE. The app connects automatically.")
            connectionStatus
        case .backingUp, .flashing:
            Text(store.batchPhase == .backingUp ? "Saving backup…" : "Writing firmware…")
            connectionStatus
        case .unitDone:
            Text("Flashed and verified.")
                .foregroundStyle(.green)
            Text("Expected checksum on calculator: \(store.expectedChecksumShort) (test menu 2.C).")
            Text("Press RESET on the cable, then turn the calculator ON. “Pr Error” is expected.")
                .foregroundStyle(.secondary)
            connectionStatus
        case .error:
            Text("Batch step failed. Fix the issue, then retry or stop.")
            connectionStatus
        case .setup:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack {
            Button("Back to welcome", action: store.returnToWelcome)
            Spacer()
            if store.batchPhase == .setup {
                Button("Start batch", action: store.startBatch)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!store.canStartBatch)
            } else if store.batchPhase == .unitDone {
                Button("Next unit", action: store.prepareNextBatchUnit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("Stop batch", action: store.stopBatch)
            } else if store.batchPhase == .error {
                Button("Retry", action: store.retryBatchUnit)
                    .buttonStyle(.borderedProminent)
                Button("Stop batch", action: store.stopBatch)
            } else if store.batchPhase == .waiting {
                Button("Stop batch", action: store.stopBatch)
            }
        }
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
        }
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
}
