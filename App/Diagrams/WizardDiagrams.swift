import AppKit
import SwiftUI
import HP15CFlasherCore

struct CalculatorDisplay: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary, lineWidth: 1)
            )
    }
}

private enum Step1Layout {
    static let bayAspect: CGFloat = 1.85
    static let bayMaxWidth: CGFloat = 270
    static let bayMaxHeight: CGFloat = 147
    static let bayWidthFrac: CGFloat = 0.93
    static let bayHeightFrac: CGFloat = 0.90
    static let wellWidthFrac: CGFloat = 0.22
    static let wellHeightFrac: CGFloat = 0.26
    static let padClusterWidthFrac: CGFloat = 0.38
    static let padRadiusFrac: CGFloat = 0.075

    static var bayCanvasSize: CGSize {
        let width = min(bayMaxWidth, bayMaxHeight * bayAspect)
        return CGSize(width: width, height: width / bayAspect)
    }

    /// Connector rectangle only — not the keyed wings.
    static var connectorBodyWidth: CGFloat {
        bayCanvasSize.width * bayWidthFrac * wellWidthFrac
    }

    static var padArrayWidth: CGFloat {
        let wellW = connectorBodyWidth
        let wellH = bayCanvasSize.height * bayHeightFrac * wellHeightFrac
        let padR = min(wellW, wellH) * padRadiusFrac
        return wellW * padClusterWidthFrac + padR * 2
    }

    /// Bottom pogo rectangle: midway between the main body and the pad cluster.
    static var pogoNoseWidthFracOfBody: CGFloat {
        ((connectorBodyWidth + padArrayWidth) / 2) / connectorBodyWidth
    }

    static let pogoNoseBottom: CGFloat = 0.865

    static var padDiameterFracOfBody: CGFloat {
        let wellW = connectorBodyWidth
        let wellH = bayCanvasSize.height * bayHeightFrac * wellHeightFrac
        return (min(wellW, wellH) * padRadiusFrac * 2) / wellW
    }

    static var padCenterSpacingFracOfBody: CGFloat {
        padClusterWidthFrac / 2
    }

    static func bayRect(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * 0.035,
            y: size.height * 0.05,
            width: size.width * bayWidthFrac,
            height: size.height * bayHeightFrac
        )
    }

    static func wellRect(in size: CGSize) -> CGRect {
        let bay = bayRect(in: size)
        let wellW = bay.width * wellWidthFrac
        let wellH = bay.height * wellHeightFrac
        return CGRect(
            x: bay.midX - wellW / 2,
            y: bay.maxY - wellH - bay.height * 0.055,
            width: wellW,
            height: wellH
        )
    }

    static func leftKeyRect(in size: CGSize) -> CGRect {
        let well = wellRect(in: size)
        let narrowKeyW = well.height * 0.16
        let keyH = well.height * 0.70
        return CGRect(
            x: well.minX - narrowKeyW,
            y: well.midY - keyH / 2,
            width: narrowKeyW,
            height: keyH
        )
    }

    static func rightKeyRects(in size: CGSize) -> (outer: CGRect, inner: CGRect) {
        let well = wellRect(in: size)
        let wellH = well.height
        let innerW = wellH * 0.1804
        let padTop = wellH * 0.155
        let padRight = wellH * 0.080
        let padBottom = wellH * 0.182
        let innerTop = well.midY - wellH * 0.266
        let innerH = well.maxY - padBottom * 1.5 - innerTop
        let inner = CGRect(x: well.maxX, y: innerTop, width: innerW, height: innerH)
        let outer = CGRect(
            x: well.maxX,
            y: inner.minY - padTop,
            width: innerW + padRight,
            height: well.maxY - (inner.minY - padTop)
        )
        return (outer, inner)
    }
}

struct CableDiagram: View {
    @Environment(\.colorScheme) private var colorScheme

    /// 0 = live Step 1. Depths 0–1 draw a Flasher window on the laptop; 2+ show wallpaper only.
    var nesting: Int = 0

    var body: some View {
        let bay = Step1Layout.bayCanvasSize
        let well = Step1Layout.wellRect(in: bay)
        let leftKey = Step1Layout.leftKeyRect(in: bay)
        let rightKey = Step1Layout.rightKeyRects(in: bay).outer
        let keySpan = rightKey.maxX - leftKey.minX
        let keyMid = (leftKey.minX + rightKey.maxX) / 2
        let plugSize = PogoPlugDrawing.sizeMatching(wingSpan: keySpan)
        let pinTipY = plugSize.height * PogoPlugDrawing.pinTipYFrac
        let gap: CGFloat = 3
        let plugTopInBay = well.minY - gap - pinTipY
        let cableStartInBay = CGPoint(
            x: keyMid,
            y: plugTopInBay + plugSize.height * PogoPlugDrawing.cableTopYFrac
        )
        let rise: CGFloat = 34
        let bend: CGFloat = 16
        let usbSize = CGSize(width: 58, height: 24)
        let laptopSize = CGSize(width: 196, height: 138)
        let extraRight: CGFloat = 14 + usbSize.width + 10 + laptopSize.width + 8
        let laptopAboveRun = laptopSize.height * 0.62
        let extraTop = max(8, 8 + rise + laptopAboveRun - cableStartInBay.y)
        let cableStart = CGPoint(x: cableStartInBay.x, y: extraTop + cableStartInBay.y)
        let runY = cableStart.y - rise
        let usbRect = CGRect(
            x: bay.width + 10,
            y: runY - usbSize.height / 2,
            width: usbSize.width,
            height: usbSize.height
        )
        let afterBend = CGPoint(x: cableStart.x + bend, y: runY)
        let usbEntry = CGPoint(x: usbRect.minX + 2, y: usbRect.midY)
        let controllerSize = CGSize(width: 58, height: 26)
        let controllerRect = CGRect(
            x: (afterBend.x + usbEntry.x) / 2 - controllerSize.width / 2,
            y: runY - controllerSize.height / 2,
            width: controllerSize.width,
            height: controllerSize.height
        )
        let laptopRect = CGRect(
            x: usbRect.maxX + 8,
            y: usbRect.midY - laptopAboveRun,
            width: laptopSize.width,
            height: laptopSize.height
        )
        let canvas = CGSize(
            width: bay.width + extraRight,
            height: max(extraTop + bay.height, laptopRect.maxY + 22, usbRect.maxY + 22)
        )
        let fill = colorScheme == .dark ? Color(white: 0.72) : Color(white: 0.28)
        let metal = colorScheme == .dark ? Color(white: 0.82) : Color(white: 0.55)
        let cordWidth = PogoPlugDrawing.cableNeckWidth(for: plugSize) * 0.45

        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                BatteryBayDrawing()
                    .frame(width: bay.width, height: bay.height)
                    .offset(y: extraTop)
                PogoPlugDrawing()
                    .frame(width: plugSize.width, height: plugSize.height)
                    .offset(x: keyMid - plugSize.width / 2, y: extraTop + plugTopInBay)
                Canvas { context, _ in
                    let start = CGPoint(x: cableStart.x, y: cableStart.y + 4)
                    let upEnd = CGPoint(x: cableStart.x, y: runY + bend)
                    var riser = Path()
                    riser.move(to: start)
                    riser.addLine(to: upEnd)
                    riser.addQuadCurve(to: afterBend, control: CGPoint(x: cableStart.x, y: runY))
                    context.stroke(
                        riser,
                        with: .color(fill),
                        style: StrokeStyle(lineWidth: cordWidth, lineCap: .butt, lineJoin: .round)
                    )
                    var run = Path()
                    run.move(to: afterBend)
                    run.addLine(to: usbEntry)
                    context.stroke(
                        run,
                        with: .color(fill),
                        style: StrokeStyle(lineWidth: cordWidth, lineCap: .butt)
                    )
                    drawController(in: controllerRect, ink: Color.primary.opacity(0.78), context: &context)
                    drawUSBA(in: usbRect, fill: fill, metal: metal, context: &context)
                    drawLaptop(in: laptopRect, ink: Color.primary.opacity(0.78), context: &context)
                }
                .frame(width: canvas.width, height: canvas.height)
                let bezel = Self.laptopBezel(in: laptopRect)
                ZStack {
                    Image("LaptopWallpaper")
                        .resizable()
                        .scaledToFill()
                        .frame(width: bezel.width, height: bezel.height)
                        .clipped()
                        .opacity(0.45)
                    if nesting < 2 {
                        FitToSize {
                            Step1ScreenMiniature(nesting: nesting + 1)
                        }
                        .frame(width: bezel.width * 0.86, height: bezel.height * 0.78)
                        .shadow(color: .black.opacity(0.4), radius: 1.6, y: 0.8)
                    }
                }
                .frame(width: bezel.width, height: bezel.height)
                .clipShape(RoundedRectangle(cornerRadius: 1.2, style: .continuous))
                .offset(x: bezel.minX, y: bezel.minY)
                .allowsHitTesting(false)
                Text("R")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .position(
                        x: controllerRect.minX + controllerRect.width * 0.32,
                        y: controllerRect.minY + controllerRect.height * 0.30
                    )
                Text("E")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .position(
                        x: controllerRect.minX + controllerRect.width * 0.68,
                        y: controllerRect.minY + controllerRect.height * 0.30
                    )
                Text("USB-A/C")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .position(x: usbRect.midX, y: usbRect.maxY + 12)
                Text("This Mac")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .position(x: laptopRect.midX, y: laptopRect.maxY + 12)
            }
            .frame(width: canvas.width, height: canvas.height)
            Text("Seat the pogo plug · keyed, one way only")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel("Battery bay with two coin cells. Pogo plug sits just above the keyed connector and can only be inserted one way. A cord leaves the top of the plug, bends right past a RESET and ERASE controller, and ends in a USB-A/C connector next to this Mac.")
    }

    private func drawController(in rect: CGRect, ink: Color, context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.12)))
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(ink.opacity(0.8)),
            style: StrokeStyle(lineWidth: max(1.0, rect.height / 16), lineJoin: .round)
        )
        let diameter = rect.height * 0.36
        let buttonY = rect.minY + rect.height * 0.66
        drawControllerButton(
            at: CGPoint(x: rect.minX + rect.width * 0.32, y: buttonY),
            diameter: diameter,
            fill: Color(white: 0.92),
            ink: ink,
            context: &context
        )
        drawControllerButton(
            at: CGPoint(x: rect.minX + rect.width * 0.68, y: buttonY),
            diameter: diameter,
            fill: .black,
            ink: ink,
            context: &context
        )
    }

    private func drawControllerButton(
        at center: CGPoint,
        diameter: CGFloat,
        fill: Color,
        ink: Color,
        context: inout GraphicsContext
    ) {
        let r = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        context.fill(Path(ellipseIn: r), with: .color(fill))
        context.stroke(
            Path(ellipseIn: r),
            with: .color(ink.opacity(0.5)),
            style: StrokeStyle(lineWidth: 0.7)
        )
    }

    private func drawUSBA(in rect: CGRect, fill: Color, metal: Color, context: inout GraphicsContext) {
        let strain = CGRect(
            x: rect.minX,
            y: rect.minY + rect.height * 0.16,
            width: rect.width * 0.24,
            height: rect.height * 0.68
        )
        let shell = CGRect(
            x: strain.maxX - 3,
            y: rect.minY,
            width: rect.maxX - (strain.maxX - 3),
            height: rect.height
        )
        context.fill(Path(roundedRect: strain, cornerRadius: 3), with: .color(fill))
        context.fill(Path(roundedRect: shell, cornerRadius: 2.4), with: .color(metal))
        var lip = Path()
        lip.move(to: CGPoint(x: shell.maxX - 1, y: shell.minY + 2))
        lip.addLine(to: CGPoint(x: shell.maxX - 1, y: shell.maxY - 2))
        context.stroke(lip, with: .color(fill.opacity(0.35)), lineWidth: 1)
        let mark = shell.insetBy(dx: shell.width * 0.14, dy: shell.height * 0.16)
        drawUSBTrident(in: mark, color: Color.primary.opacity(0.82), context: &context)
    }

    /// USB trident (circle base, arrow / circle / square), pointing toward the plug tip.
    private func drawUSBTrident(in rect: CGRect, color: Color, context: inout GraphicsContext) {
        let s = min(rect.width, rect.height * 1.15)
        let origin = CGPoint(x: rect.midX - s * 0.42, y: rect.midY)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * s, y: origin.y + y * s)
        }
        let lw = max(1.05, s / 14)
        let stroke = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
        let hub = pt(0.38, 0)
        var arms = Path()
        arms.move(to: pt(0.10, 0))
        arms.addLine(to: hub)
        arms.addLine(to: pt(0.78, 0))
        arms.move(to: hub)
        arms.addLine(to: pt(0.68, -0.34))
        arms.move(to: hub)
        arms.addLine(to: pt(0.68, 0.34))
        context.stroke(arms, with: .color(color), style: stroke)

        let baseR = s * 0.075
        context.fill(Path(ellipseIn: CGRect(x: pt(0.10, 0).x - baseR, y: pt(0.10, 0).y - baseR, width: baseR * 2, height: baseR * 2)), with: .color(color))

        let tip = pt(0.88, 0)
        var arrow = Path()
        arrow.move(to: CGPoint(x: tip.x - s * 0.14, y: tip.y - s * 0.11))
        arrow.addLine(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x - s * 0.14, y: tip.y + s * 0.11))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(color))

        let circR = s * 0.07
        let circ = pt(0.68, -0.34)
        context.stroke(
            Path(ellipseIn: CGRect(x: circ.x - circR, y: circ.y - circR, width: circR * 2, height: circR * 2)),
            with: .color(color),
            style: stroke
        )

        let sq = s * 0.11
        let square = pt(0.68, 0.34)
        context.stroke(
            Path(CGRect(x: square.x - sq / 2, y: square.y - sq / 2, width: sq, height: sq)),
            with: .color(color),
            style: stroke
        )
    }

    private func drawLaptop(in rect: CGRect, ink: Color, context: inout GraphicsContext) {
        let lw = max(1.15, rect.width / 48)
        let line = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
        let baseH = rect.height * 0.20
        let hinge = rect.height * 0.06
        let base = CGRect(
            x: rect.minX,
            y: rect.maxY - baseH,
            width: rect.width,
            height: baseH
        )
        let screen = CGRect(
            x: rect.minX + rect.width * 0.10,
            y: rect.minY,
            width: rect.width * 0.80,
            height: rect.height - baseH - hinge
        )
        context.stroke(Path(roundedRect: screen, cornerRadius: 2.2), with: .color(ink), style: line)
        let bezel = screen.insetBy(dx: screen.width * 0.07, dy: screen.height * 0.07)
        context.fill(Path(roundedRect: bezel, cornerRadius: 1.2), with: .color(Color(white: 0.16)))
        context.stroke(Path(roundedRect: bezel, cornerRadius: 1.2), with: .color(ink.opacity(0.7)), style: line)
        context.stroke(Path(roundedRect: base, cornerRadius: 1.6), with: .color(ink), style: line)
        var hingeLine = Path()
        hingeLine.move(to: CGPoint(x: screen.minX + 2, y: screen.maxY))
        hingeLine.addLine(to: CGPoint(x: screen.maxX - 2, y: screen.maxY))
        context.stroke(hingeLine, with: .color(ink), style: line)
    }

    static func laptopBezel(in rect: CGRect) -> CGRect {
        let baseH = rect.height * 0.20
        let hinge = rect.height * 0.06
        let screen = CGRect(
            x: rect.minX + rect.width * 0.10,
            y: rect.minY,
            width: rect.width * 0.80,
            height: rect.height - baseH - hinge
        )
        return screen.insetBy(dx: screen.width * 0.07, dy: screen.height * 0.07)
    }
}

/// Live Step 1 window content, scaled to fit the laptop screen.
private struct Step1ScreenMiniature: View {
    var nesting: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("15CE Flasher")
                    .font(.largeTitle.weight(.semibold))
                Text("Native SAM-BA programmer for the post-2015 Voyager series")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Step 1 of \(WizardStep.count)")
                    .font(.headline)
                Text(WizardStep.cable.title)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    CableDiagram(nesting: nesting)
                    Text("Open the calculator's battery door and insert the POGO cable. The connector is keyed; the POGO can only be inserted one way. Make sure the plug snaps securely into place.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Plug the other end of the cable (USB-A or USB-C) into this Mac.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(WizardStep.allCases, id: \.self) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                        Text("\(step.number). \(step.title)")
                            .fontWeight(step == .cable ? .semibold : .regular)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(step == .cable ? Color.primary : Color.secondary)
                    .opacity(step == .cable ? 1 : 0.45)
                }
            }
            .padding(.top, 4)
            HStack {
                Text("Back")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Continue")
                    .fontWeight(.medium)
            }
            Text("\(Bundle.main.miniatureVersionLabel) · Mach II Labs · offline · no telemetry · free forever")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 640, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MiniatureSizeKey: PreferenceKey {
    static var defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
    }
}

/// Uniformly scales content to fit the proposed size without clipping.
private struct FitToSize<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var intrinsic = CGSize(width: 640, height: 900)

    var body: some View {
        GeometryReader { geo in
            let scale = min(
                geo.size.width / max(intrinsic.width, 1),
                geo.size.height / max(intrinsic.height, 1)
            ) * 0.92
            content()
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { inner in
                        Color.clear.preference(key: MiniatureSizeKey.self, value: inner.size)
                    }
                )
                .onPreferenceChange(MiniatureSizeKey.self) { size in
                    if size.width > 0, size.height > 0 { intrinsic = size }
                }
                .scaleEffect(scale, anchor: .top)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}

private extension Bundle {
    var miniatureVersionLabel: String {
        let marketing = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(marketing) (\(build))"
    }
}

/// Closed left-wing outline in 0–1 `PogoPlugDrawing` space.
/// Empty uses the built-in curves. Paste tracer output here; the right wing is mirrored.
enum PogoWingOutline {
    /// Closed left-wing outline in 0–1 drawing space. Right wing is mirrored.
    static let left: [CGPoint] = [
        CGPoint(x: 0.144, y: 0.296),
        CGPoint(x: 0.148, y: 0.387),
        CGPoint(x: 0.168, y: 0.723),
        CGPoint(x: 0.188, y: 0.780),
        CGPoint(x: 0.199, y: 0.817),
        CGPoint(x: 0.166, y: 0.813),
        CGPoint(x: 0.236, y: 0.877),
        CGPoint(x: 0.214, y: 0.745),
        CGPoint(x: 0.210, y: 0.393),
        CGPoint(x: 0.253, y: 0.392),
        CGPoint(x: 0.251, y: 0.294),
    ]
}

/// Side-view silhouette of the USB-C pogo plug, pins down, filled dark grey.
/// The main body is a golden rectangle (height / width = φ); the head is scaled to match.
struct PogoPlugDrawing: View {
    @Environment(\.colorScheme) private var colorScheme

    #if DEBUG
    /// When set (Debug wing editor), replaces `PogoWingOutline.left`.
    var leftWingOverride: [CGPoint]? = nil
    #endif

    private static let phi: CGFloat = (1 + sqrt(5)) / 2
    private static let bodyTop: CGFloat = 0.215
    private static let bodyBottom: CGFloat = 0.80
    private static let bodyH: CGFloat = bodyBottom - bodyTop
    private static let bodyW: CGFloat = 0.50
    private static let widthBoost: CGFloat = 1.10
    private static let bodyLeft: CGFloat = (1 - bodyW) / 2
    private static let bodyRight: CGFloat = 1 - bodyLeft
    static let aspect: CGFloat = {
        let rAspect = bodyH / (bodyW * phi) * widthBoost
        return rAspect * 0.96 / 0.92
    }()

    static func drawingBox(in size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.04, dy: size.height * 0.02)
    }

    static func viewPoint(_ n: CGPoint, in box: CGRect) -> CGPoint {
        CGPoint(x: box.minX + n.x * box.width, y: box.minY + n.y * box.height)
    }

    static func normalizedPoint(_ p: CGPoint, in box: CGRect) -> CGPoint {
        CGPoint(x: (p.x - box.minX) / box.width, y: (p.y - box.minY) / box.height)
    }

    static func sizeMatching(connectorBodyWidth target: CGFloat) -> CGSize {
        let height = target * phi / (bodyH * 0.96 * widthBoost)
        return CGSize(width: height * aspect, height: height)
    }

    /// Outer x of the traced left wing and its mirror, as a fraction of the view width.
    private static var wingXFracOfView: (left: CGFloat, right: CGFloat) {
        let minX = PogoWingOutline.left.map(\.x).min() ?? 0.14
        let left = 0.04 + minX * 0.92
        return (left, 1 - left)
    }

    static func sizeMatching(wingSpan target: CGFloat) -> CGSize {
        let span = wingXFracOfView
        let width = target / (span.right - span.left)
        return CGSize(width: width, height: width / aspect)
    }

    /// Pin tips as a fraction of the view height (from the top).
    static var pinTipYFrac: CGFloat {
        let nose = Step1Layout.pogoNoseBottom
        let tipInBox = nose + (1 - nose) * 0.85
        return 0.02 + tipInBox * 0.96
    }

    static let cableTopYFrac: CGFloat = 0.02

    static func cableNeckWidth(for plugSize: CGSize) -> CGFloat {
        let box = drawingBox(in: plugSize)
        let bodyFrac = (bodyH * box.height / phi) / box.width * widthBoost
        return max(4, bodyFrac * 0.39 * box.width)
    }

    var body: some View {
        Canvas { context, size in
            let fill = colorScheme == .dark ? Color(white: 0.72) : Color(white: 0.28)
            let box = Self.drawingBox(in: size)
            context.fill(housingPath(in: box), with: .color(fill))
            context.fill(leftWingPath(in: box), with: .color(fill))
            context.fill(rightWingPath(in: box), with: .color(fill))
            let pinStroke = StrokeStyle(lineWidth: max(1.0, size.width / 140), lineCap: .round, lineJoin: .round)
            for pin in pinRects(in: box) {
                context.stroke(pinOutline(in: pin), with: .color(fill), style: pinStroke)
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func bodyEdges(in r: CGRect) -> (left: CGFloat, right: CGFloat) {
        let w = (Self.bodyH * r.height / Self.phi) / r.width * Self.widthBoost
        let left = (1 - w) / 2
        return (left, 1 - left)
    }

    private func pt(_ x: CGFloat, _ y: CGFloat, in r: CGRect) -> CGPoint {
        CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
    }

    private func housingPath(in r: CGRect) -> Path {
        let e = bodyEdges(in: r)
        let bodyW = e.right - e.left
        let cableW = bodyW * 0.39
        let noseW = bodyW * Step1Layout.pogoNoseWidthFracOfBody
        let cableL = (1 - cableW) / 2
        let cableR = 1 - cableL
        let noseL = (1 - noseW) / 2
        let noseR = 1 - noseL
        var p = Path()
        p.move(to: pt(cableL, 0.00, in: r))
        p.addLine(to: pt(cableR, 0.00, in: r))
        p.addLine(to: pt(cableR, Self.bodyTop, in: r))
        p.addLine(to: pt(e.right, Self.bodyTop, in: r))
        p.addLine(to: pt(e.right, Self.bodyBottom, in: r))
        p.addLine(to: pt(noseR, Self.bodyBottom, in: r))
        p.addLine(to: pt(noseR, Step1Layout.pogoNoseBottom, in: r))
        p.addLine(to: pt(noseL, Step1Layout.pogoNoseBottom, in: r))
        p.addLine(to: pt(noseL, Self.bodyBottom, in: r))
        p.addLine(to: pt(e.left, Self.bodyBottom, in: r))
        p.addLine(to: pt(e.left, Self.bodyTop, in: r))
        p.addLine(to: pt(cableL, Self.bodyTop, in: r))
        p.closeSubpath()
        return p
    }

    private var leftWingPoints: [CGPoint] {
        #if DEBUG
        leftWingOverride ?? PogoWingOutline.left
        #else
        PogoWingOutline.left
        #endif
    }

    private func polyline(_ points: [CGPoint], in r: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: pt(first.x, first.y, in: r))
        for point in points.dropFirst() {
            p.addLine(to: pt(point.x, point.y, in: r))
        }
        p.closeSubpath()
        return p
    }

    private func leftWingPath(in r: CGRect) -> Path {
        let custom = leftWingPoints
        if custom.count >= 3 {
            return polyline(custom, in: r)
        }
        let L = bodyEdges(in: r).left
        var p = Path()
        p.move(to: pt(L, 0.33, in: r))
        p.addQuadCurve(to: pt(0.04, 0.54, in: r), control: pt(0.02, 0.36, in: r))
        p.addQuadCurve(to: pt(L - 0.08, 0.805, in: r), control: pt(0.03, 0.72, in: r))
        p.addLine(to: pt(L + 0.04, 0.795, in: r))
        p.addLine(to: pt(L - 0.02, 0.77, in: r))
        p.addQuadCurve(to: pt(0.13, 0.54, in: r), control: pt(0.13, 0.70, in: r))
        p.addQuadCurve(to: pt(L, 0.39, in: r), control: pt(0.14, 0.40, in: r))
        p.closeSubpath()
        return p
    }

    private func rightWingPath(in r: CGRect) -> Path {
        let custom = leftWingPoints
        if custom.count >= 3 {
            return polyline(custom.map { CGPoint(x: 1 - $0.x, y: $0.y) }, in: r)
        }
        let R = bodyEdges(in: r).right
        var p = Path()
        p.move(to: pt(R, 0.33, in: r))
        p.addQuadCurve(to: pt(0.96, 0.54, in: r), control: pt(0.98, 0.36, in: r))
        p.addQuadCurve(to: pt(R + 0.08, 0.805, in: r), control: pt(0.97, 0.72, in: r))
        p.addLine(to: pt(R - 0.04, 0.795, in: r))
        p.addLine(to: pt(R + 0.02, 0.77, in: r))
        p.addQuadCurve(to: pt(0.87, 0.54, in: r), control: pt(0.87, 0.70, in: r))
        p.addQuadCurve(to: pt(R, 0.39, in: r), control: pt(0.86, 0.40, in: r))
        p.closeSubpath()
        return p
    }

    private func pinRects(in r: CGRect) -> [CGRect] {
        let bodyW = bodyEdges(in: r).right - bodyEdges(in: r).left
        let y = r.minY + Step1Layout.pogoNoseBottom * r.height
        let h = (1 - Step1Layout.pogoNoseBottom) * r.height * 0.85
        let w = bodyW * Step1Layout.padDiameterFracOfBody * r.width
        let span = bodyW * Step1Layout.padCenterSpacingFracOfBody * r.width
        let start = r.midX - span - w / 2
        return (0..<3).map { i in
            CGRect(x: start + CGFloat(i) * span, y: y, width: w, height: h)
        }
    }

    private func pinOutline(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height / 2)
        let tip = CGPoint(x: rect.midX, y: rect.maxY - radius)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: tip.y))
        path.addArc(
            center: tip,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Line drawing of the 15c CE battery bay, door off, display end at the top.
/// The keyed pogo connector has a narrow slot on the left and a wide slot on the right.
struct BatteryBayDrawing: View {
    var body: some View {
        Canvas { context, size in
            let ink = Color.primary.opacity(0.78)
            let dim = Color.secondary
            let lw = max(1.15, size.width / 300)
            let line = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)

            func stroke(_ path: Path, color: Color = ink, width: CGFloat? = nil) {
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: width ?? lw, lineCap: .round, lineJoin: .round)
                )
            }

            let bay = Step1Layout.bayRect(in: size)
            stroke(Path(roundedRect: bay, cornerRadius: bay.height * 0.07))

            let batteryR = bay.height * 0.32
            let leftC = CGPoint(x: bay.minX + bay.width * 0.26, y: bay.minY + bay.height * 0.36)
            let rightC = CGPoint(x: bay.minX + bay.width * 0.74, y: leftC.y)

            drawBattery(at: leftC, radius: batteryR, in: &context, ink: ink, dim: dim, line: line)
            drawBattery(at: rightC, radius: batteryR, in: &context, ink: ink, dim: dim, line: line)

            let tabW = batteryR * 0.18
            let tabH = batteryR * 0.32
            for center in [leftC, rightC] {
                stroke(Path(roundedRect: CGRect(
                    x: center.x + batteryR - tabW * 0.35,
                    y: center.y - tabH / 2,
                    width: tabW,
                    height: tabH
                ), cornerRadius: 1.5))
            }

            let plusArm = batteryR * 0.20
            let plus = CGPoint(x: bay.midX, y: leftC.y)
            var plusPath = Path()
            plusPath.move(to: CGPoint(x: plus.x - plusArm, y: plus.y))
            plusPath.addLine(to: CGPoint(x: plus.x + plusArm, y: plus.y))
            plusPath.move(to: CGPoint(x: plus.x, y: plus.y - plusArm))
            plusPath.addLine(to: CGPoint(x: plus.x, y: plus.y + plusArm))
            stroke(plusPath, width: lw * 1.7)

            let well = Step1Layout.wellRect(in: size)
            let leftKey = Step1Layout.leftKeyRect(in: size)
            let keys = Step1Layout.rightKeyRects(in: size)
            stroke(keyedWellPath(well: well, leftKey: leftKey, rightKey: keys.outer))
            stroke(rightKeyInnerBorder(well: well, inner: keys.inner))

            let wellW = well.width
            let wellH = well.height
            let padR = min(wellW, wellH) * Step1Layout.padRadiusFrac
            let clusterW = wellW * Step1Layout.padClusterWidthFrac
            let clusterH = wellH * 0.34
            let padArea = CGRect(
                x: well.midX - clusterW / 2,
                y: well.midY - clusterH / 2,
                width: clusterW,
                height: clusterH
            )
            for row in 0..<2 {
                for col in 0..<3 {
                    let x = padArea.minX + padArea.width * CGFloat(col) / 2
                    let y = padArea.minY + padArea.height * CGFloat(row)
                    let rect = CGRect(x: x - padR, y: y - padR, width: padR * 2, height: padR * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.accentColor.opacity(0.9)))
                    stroke(Path(ellipseIn: rect))
                }
            }
        }
    }

    private func drawBattery(
        at center: CGPoint,
        radius: CGFloat,
        in context: inout GraphicsContext,
        ink: Color,
        dim: Color,
        line: StrokeStyle
    ) {
        let outer = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: outer), with: .color(ink), style: line)
        let p = radius * 0.16
        var plus = Path()
        plus.move(to: CGPoint(x: center.x - p, y: center.y))
        plus.addLine(to: CGPoint(x: center.x + p, y: center.y))
        plus.move(to: CGPoint(x: center.x, y: center.y - p))
        plus.addLine(to: CGPoint(x: center.x, y: center.y + p))
        context.stroke(plus, with: .color(dim), style: line)
    }

    /// Inner lip of the wide key: top, right, and bottom only. Size is independent of outer padding.
    private func rightKeyInnerBorder(well: CGRect, inner: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: well.maxX, y: inner.minY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.minY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
        path.addLine(to: CGPoint(x: well.maxX, y: inner.maxY))
        return path
    }

    private func keyedWellPath(well: CGRect, leftKey: CGRect, rightKey: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: well.minX, y: well.minY))
        path.addLine(to: CGPoint(x: well.maxX, y: well.minY))
        path.addLine(to: CGPoint(x: well.maxX, y: rightKey.minY))
        path.addLine(to: CGPoint(x: rightKey.maxX, y: rightKey.minY))
        path.addLine(to: CGPoint(x: rightKey.maxX, y: rightKey.maxY))
        path.addLine(to: CGPoint(x: well.maxX, y: rightKey.maxY))
        path.addLine(to: CGPoint(x: well.maxX, y: well.maxY))
        path.addLine(to: CGPoint(x: well.minX, y: well.maxY))
        path.addLine(to: CGPoint(x: well.minX, y: leftKey.maxY))
        path.addLine(to: CGPoint(x: leftKey.minX, y: leftKey.maxY))
        path.addLine(to: CGPoint(x: leftKey.minX, y: leftKey.minY))
        path.addLine(to: CGPoint(x: well.minX, y: leftKey.minY))
        path.closeSubpath()
        return path
    }
}

struct ProgrammingModeDiagram: View {
    var body: some View {
        HStack(spacing: 20) {
            callout("1. Hold ERASE", fill: .black, motion: .hold)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            callout("2. Press RESET", fill: Color(white: 0.92), motion: .tap)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            callout("3. Release ERASE", fill: .black, motion: .release)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel("On the cable's switch box, hold ERASE, press RESET, then release ERASE")
    }

    private enum Motion {
        case hold, tap, release
    }

    private func callout(_ title: String, fill: Color, motion: Motion) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 5) {
                motionArrows(motion)
                Circle()
                    .fill(fill)
                    .overlay {
                        Circle().stroke(Color.secondary, lineWidth: 1.25)
                    }
                    .frame(width: 22, height: 22)
            }
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .frame(width: 90)
        }
    }

    @ViewBuilder
    private func motionArrows(_ motion: Motion) -> some View {
        switch motion {
        case .hold:
            Image(systemName: "arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        case .tap:
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                Image(systemName: "arrow.up")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        case .release:
            Image(systemName: "arrow.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct FinishDiagram: View {
    var body: some View {
        HStack(spacing: 28) {
            VStack(spacing: 6) {
                VStack(spacing: 5) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                        Image(systemName: "arrow.up")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Circle()
                        .fill(Color(white: 0.92))
                        .overlay {
                            Circle().stroke(Color.secondary, lineWidth: 1.25)
                        }
                        .frame(width: 22, height: 22)
                }
                Text("Press RESET")
                    .font(.caption)
            }
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            CalculatorOnKey()
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            CalculatorDisplay("Pr Error")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel("Press RESET on the cable switch-box, then turn the calculator ON. Pr Error in the display is expected")
    }
}

struct ChecksumDiagram: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 4) {
                iconColumn {
                    VStack(spacing: 5) {
                        KeystrokeArrows(motion: .press)
                        CalculatorOnKey()
                    }
                }
                connector
                iconColumn {
                    VStack(spacing: 5) {
                        KeystrokeArrows(motion: .hold)
                        VoyagerGPlusEnter()
                    }
                }
                connector
                iconColumn {
                    VStack(spacing: 5) {
                        KeystrokeArrows(motion: .press)
                        CalculatorOnKey()
                    }
                }
                connector
                iconColumn {
                    VStack(spacing: 5) {
                        KeystrokeArrows(motion: .release)
                        VoyagerGPlusEnter()
                    }
                }
                connector
                iconColumn {
                    CalculatorDisplay("1.L 2.C 3.H")
                }
                connector
                iconColumn {
                    VStack(spacing: 5) {
                        KeystrokeArrows(motion: .press)
                        VoyagerTwoKey()
                    }
                }
            }
            HStack(alignment: .top, spacing: 4) {
                caption("1. Turn OFF")
                connectorSlot
                caption("2. Hold g + ENTER")
                connectorSlot
                caption("3. Press ON")
                connectorSlot
                caption("4. Release g + ENTER")
                connectorSlot
                caption("5. Test menu")
                connectorSlot
                caption("6. Press 2")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel("Turn the calculator off with ON, hold g and ENTER, press ON, release g and ENTER. The display shows the test menu 1.L 2.C 3.H. Press 2 for the checksum")
    }

    private enum Layout {
        static let arrow: CGFloat = 12
    }

    private func iconColumn<Icon: View>(@ViewBuilder icon: () -> Icon) -> some View {
        icon()
            .frame(maxWidth: .infinity)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    private var connector: some View {
        Image(systemName: "arrow.right")
            .foregroundStyle(.secondary)
            .frame(width: Layout.arrow)
    }

    private var connectorSlot: some View {
        Color.clear.frame(width: Layout.arrow, height: 1)
    }
}

private enum KeystrokeMotion {
    case hold, press, release
}

private struct KeystrokeArrows: View {
    var motion: KeystrokeMotion

    var body: some View {
        Group {
            switch motion {
            case .hold:
                Image(systemName: "arrow.down")
            case .press:
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                    Image(systemName: "arrow.up")
                }
            case .release:
                Image(systemName: "arrow.up")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private enum VoyagerKeyMetrics {
    static let gSize = CGSize(width: 28, height: 28)
    static let enterSize = CGSize(width: gSize.width, height: gSize.height * 3)
    static let enterInkHeight: CGFloat = 8
    static let enterLetterTop: CGFloat = 6
    static let enterLetterGap: CGFloat = 2
}

private enum EnterLetterMetrics {
    static var font: NSFont {
        let probe = roundedRegular(100)
        return roundedRegular(VoyagerKeyMetrics.enterInkHeight * 100 / probe.capHeight)
    }

    static func roundedRegular(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .regular)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func size(of letter: String) -> CGSize {
        let size = NSAttributedString(string: letter, attributes: [.font: font]).size()
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}

private struct VoyagerGPlusEnter: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            VoyagerGKey()
            Text("+")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(height: VoyagerKeyMetrics.gSize.height)
            VoyagerEnterKey()
        }
        .fixedSize()
    }
}

/// Digit key: dark faces, ivory numeral on the top, blue g-shifted legend on the bevel.
private struct VoyagerTwoKey: View {
    private let light = Color(white: 0.30)
    private let dark = Color(white: 0.16)
    private let ivory = Color(red: 0.93, green: 0.89, blue: 0.72)
    private let legend = Color(red: 0.42, green: 0.72, blue: 0.92)
    private let size = VoyagerKeyMetrics.gSize
    private let darkFraction: CGFloat = 0.32

    var body: some View {
        let lightH = voyagerLightFaceHeight(total: size.height, darkFraction: darkFraction)
        let darkH = size.height - lightH
        ZStack {
            voyagerKeyBody(size: size, light: light, dark: dark, darkFraction: darkFraction, corner: 5)
            VStack(spacing: 0) {
                Text("2")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(ivory)
                    .frame(width: size.width, height: lightH, alignment: .center)
                HStack(spacing: 1) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 6, weight: .bold))
                    Text("H")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(legend)
                .frame(width: size.width, height: darkH)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// Gold/brown f-key silhouette, but blue: lighter top face, darker front bevel.
private struct VoyagerGKey: View {
    private let light = Color(red: 0.36, green: 0.56, blue: 0.78)
    private let dark = Color(red: 0.20, green: 0.36, blue: 0.54)
    private let size = VoyagerKeyMetrics.gSize
    private let darkFraction: CGFloat = 0.35

    var body: some View {
        let lightH = voyagerLightFaceHeight(total: size.height, darkFraction: darkFraction)
        let darkH = size.height - lightH
        ZStack {
            voyagerKeyBody(size: size, light: light, dark: dark, darkFraction: darkFraction, corner: 5)
            VStack(spacing: 0) {
                Text("g")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: size.width, height: lightH, alignment: .center)
                Color.clear.frame(height: darkH)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// Tall ENTER: dark grey faces, blue LST *x* on the front bevel. ENTER letters are separate overlays.
private struct VoyagerEnterKey: View {
    private let light = Color(white: 0.30)
    private let dark = Color(white: 0.16)
    private let size = VoyagerKeyMetrics.enterSize
    private let darkFraction: CGFloat = 0.20
    private let legend = Color(red: 0.42, green: 0.72, blue: 0.92)

    var body: some View {
        let lightH = voyagerLightFaceHeight(total: size.height, darkFraction: darkFraction)
        let darkH = size.height - lightH
        ZStack(alignment: .topLeading) {
            voyagerKeyBody(size: size, light: light, dark: dark, darkFraction: darkFraction, corner: 4)
            VStack(spacing: 0) {
                Color.clear.frame(width: size.width, height: lightH)
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("LST")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                    Text("\u{1D465}")
                        .font(.system(size: 12))
                }
                .foregroundStyle(legend)
                .frame(width: size.width, height: darkH)
            }
            ForEach(Array("ENTER".enumerated()), id: \.offset) { index, character in
                let letter = String(character)
                let letterSize = EnterLetterMetrics.size(of: letter)
                Text(letter)
                    .font(Font(EnterLetterMetrics.font))
                    .foregroundStyle(Color(white: 0.95))
                    .fixedSize()
                    .offset(
                        x: (size.width - letterSize.width) / 2,
                        y: VoyagerKeyMetrics.enterLetterTop
                            + CGFloat(index) * (VoyagerKeyMetrics.enterInkHeight + VoyagerKeyMetrics.enterLetterGap)
                    )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct CalculatorOnKey: View {
    var body: some View {
        Text("ON")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(white: 0.92))
            .frame(width: 32, height: 22)
            .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 2.5, style: .continuous))
    }
}

private func voyagerLightFaceHeight(total: CGFloat, darkFraction: CGFloat, blend: CGFloat = 0.03) -> CGFloat {
    total * (1 - darkFraction - blend)
}

private func voyagerKeyBody(
    size: CGSize,
    light: Color,
    dark: Color,
    darkFraction: CGFloat,
    corner: CGFloat
) -> some View {
    let blend: CGFloat = 0.03
    return RoundedRectangle(cornerRadius: corner, style: .continuous)
        .fill(
            LinearGradient(
                stops: [
                    .init(color: light, location: 0),
                    .init(color: light, location: max(0, 1 - darkFraction - blend)),
                    .init(color: dark, location: min(1, 1 - darkFraction + blend)),
                    .init(color: dark, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.black.opacity(0.45), lineWidth: 0.8)
        }
        .frame(width: size.width, height: size.height)
}
