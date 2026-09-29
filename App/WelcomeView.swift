import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var store: FlasherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("15CE Flasher")
                    .font(.largeTitle.weight(.semibold))
                Text("Choose how you want to run this session.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                modeCard(
                    mode: .demo,
                    title: "DEMO",
                    badge: store.hasCompletedDemo ? nil : "Recommended",
                    detail: "Walk through the full wizard against a simulated calculator on this Mac. No cable. Nothing is written to a real calculator."
                )
                modeCard(
                    mode: .flash,
                    title: "FLASH",
                    badge: nil,
                    detail: "Talk to a real post-2015 Voyager calculator over the pogo cable. User memory will be wiped."
                )
                modeCard(
                    mode: .batch,
                    title: "BATCH",
                    badge: nil,
                    detail: "Flash many Collector’s Editions in sequence with the same firmware. For experienced operators only. Each unit still needs ERASE+RESET; user memory is wiped every time."
                )
                modeCard(
                    mode: .probe,
                    title: "Connection Probe",
                    badge: nil,
                    detail: "Test cable detection on real hardware without choosing firmware or flashing. Confirms SAM-BA sees the calculator before you start FLASH or BATCH."
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Disclaimer")
                    .font(.headline)
                Text(Self.disclaimer)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Continue") {
                    store.beginChosenSession()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }

            Text("\(Bundle.main.appVersionLabel) · Mach II Labs · offline · no telemetry · free forever")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity, alignment: .topLeading)
    }

    private func modeCard(mode: FlasherMode, title: String, badge: String?, detail: String) -> some View {
        let selected = store.selectedMode == mode
        return Button {
            store.selectedMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    Text(title)
                        .font(.title3.weight(.semibold))
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private static let disclaimer = "15CE Flasher and related documentation are provided as is, without warranty of any kind. Although we have employed several safeguards to help keep this software safe, flashing firmware can wipe user memory, leave the calculator unusable, or permanently brick the device. You are solely responsible for backups, choosing a correct firmware file, and following the app’s instructions. If the instructions are not clear in DEMO mode, do not execute in FLASH mode. Mach II Labs is not liable for damage, data loss, or repair costs arising from use of this software."
}
