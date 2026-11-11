import SwiftUI
import UIKit

/// Original Horizon control editor. No Amethyst/Pojav implementation is used.
/// IDs/order are the version-one ABI in touch.rs and horizon-ios-launcher.
enum TouchButton: Int, CaseIterable, Codable, Identifiable {
    case forward, back, left, right, sneak, jump, perspective, chat, pause, inventory, attack, use, offhand
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .forward: return "Forward"
        case .back: return "Back"
        case .left: return "Left"
        case .right: return "Right"
        case .sneak: return "Sneak"
        case .jump: return "Jump"
        case .perspective: return "View"
        case .chat: return "Chat"
        case .pause: return "Pause"
        case .inventory: return "Inventory"
        case .attack: return "Hit / Break"
        case .use: return "Use / Place"
        case .offhand: return "Offhand"
        }
    }
    var symbol: String {
        switch self {
        case .forward: return "arrow.up"
        case .back: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .sneak: return "figure.walk"
        case .jump: return "arrow.up.to.line"
        case .perspective: return "camera.rotate"
        case .chat: return "text.bubble"
        case .pause: return "pause"
        case .inventory: return "ellipsis"
        case .attack: return "hammer"
        case .use: return "cube"
        case .offhand: return "arrow.left.arrow.right"
        }
    }
    // GUI pixels, matching touch::default_layout. Hotbar is the game's HUD,
    // not an independently movable touch button.
    func rect(in size: CGSize) -> CGRect {
        let w = size.width, h = size.height
        let s = min(48, max(26, h * 0.14)), small = (s * 0.65).rounded()
        let cx = 14 + s, cy = h - 14 - 2 * s - 8
        switch self {
        case .forward: return CGRect(x: cx, y: cy - s, width: s, height: s)
        case .back: return CGRect(x: cx, y: cy + s, width: s, height: s)
        case .left: return CGRect(x: cx - s, y: cy, width: s, height: s)
        case .right: return CGRect(x: cx + s, y: cy, width: s, height: s)
        case .sneak: return CGRect(x: cx, y: cy, width: s, height: s)
        case .jump: return CGRect(x: w - 14 - s, y: cy, width: s, height: s)
        case .inventory: return CGRect(x: floor(w / 2 - 91) + 184, y: h - 30, width: 30, height: 30)
        case .attack:
            let x: CGFloat = w - 14 - s
            let y: CGFloat = cy - s - 4
            return CGRect(x: x, y: y, width: s, height: s)
        case .use:
            let x: CGFloat = w - 14 - 2 * s - 4
            let y: CGFloat = cy - s - 4
            return CGRect(x: x, y: y, width: s, height: s)
        case .offhand:
            let x: CGFloat = floor(w / 2 - 91) - 32
            let y: CGFloat = h - 30
            return CGRect(x: x, y: y, width: 30, height: 30)
        default:
            let i = rawValue - TouchButton.perspective.rawValue
            return CGRect(x: (w - 3 * small - 8) / 2 + CGFloat(i) * (small + 4), y: 2, width: small, height: small)
        }
    }
}

struct TouchCentre: Codable, Equatable {
    var x: Double
    var y: Double
    var valid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

struct TouchConfiguration: Codable, Equatable {
    /// The size multipliers the editor offers; mirrored by MIN_SCALE/MAX_SCALE in touch.rs.
    static let minScale = 0.5
    static let maxScale = 2.0

    var centres: [String: TouchCentre] = [:]
    /// Size multipliers by button; a missing entry is the built-in size.
    var sizes: [String: Double] = [:]
    var showControls = true

    init() {}
    private enum CodingKeys: String, CodingKey { case centres, sizes, showControls }
    /// Layouts saved before sizes existed have no `sizes` key and must keep their positions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        centres = try c.decodeIfPresent([String: TouchCentre].self, forKey: .centres) ?? [:]
        sizes = try c.decodeIfPresent([String: Double].self, forKey: .sizes) ?? [:]
        showControls = try c.decodeIfPresent(Bool.self, forKey: .showControls) ?? true
    }

    func scale(_ button: TouchButton) -> CGFloat {
        guard let v = sizes[String(button.rawValue)], v.isFinite, v > 0 else { return 1 }
        return CGFloat(min(Self.maxScale, max(Self.minScale, v)))
    }
    mutating func setScale(_ button: TouchButton, _ value: Double) {
        let v = min(Self.maxScale, max(Self.minScale, value))
        if abs(v - 1) < 0.005 { sizes[String(button.rawValue)] = nil } else { sizes[String(button.rawValue)] = v }
    }
    /// The built-in rectangle grown or shrunk around its own centre, as touch.rs does before placing it.
    private func sized(_ button: TouchButton, in size: CGSize) -> CGRect {
        var r = button.rect(in: size)
        let k = scale(button)
        guard k != 1 else { return r }
        let centre = CGPoint(x: r.midX, y: r.midY)
        r.size = CGSize(width: r.width * k, height: r.height * k)
        r.origin = CGPoint(x: centre.x - r.width / 2, y: centre.y - r.height / 2)
        r.origin.x = max(0, min(size.width - r.width, r.origin.x))
        r.origin.y = max(0, min(size.height - r.height, r.origin.y))
        return r
    }

    func rect(_ button: TouchButton, in size: CGSize) -> CGRect {
        var r = sized(button, in: size)
        if let c = centres[String(button.rawValue)], c.valid {
            r.origin.x = max(0, min(size.width - r.width, c.x * size.width - r.width / 2))
            r.origin.y = max(0, min(size.height - r.height, c.y * size.height - r.height / 2))
        }
        return r
    }
    mutating func move(_ button: TouchButton, to point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let r = sized(button, in: size)
        let x = max(r.width / 2, min(size.width - r.width / 2, point.x))
        let y = max(r.height / 2, min(size.height - r.height / 2, point.y))
        centres[String(button.rawValue)] = TouchCentre(x: x / size.width, y: y / size.height)
    }
    func snapshot() -> ([Float], UInt32) {
        let points = TouchButton.allCases.flatMap { b -> [Float] in
            guard let c = centres[String(b.rawValue)], c.valid else { return [.nan, .nan] }
            return [Float(c.x), Float(c.y)]
        }
        return (points, showControls ? 0 : 1)
    }
    /// One multiplier per button in `TouchButton` order; NaN is the built-in size.
    func sizeSnapshot() -> [Float] {
        var out: [Float] = []
        for button in TouchButton.allCases {
            let key = String(button.rawValue)
            if let v = sizes[key], v.isFinite, v > 0 {
                let clamped: Double = min(Self.maxScale, max(Self.minScale, v))
                out.append(Float(clamped))
            } else {
                out.append(Float.nan)
            }
        }
        return out
    }
    /// ABI v2: the centres (26), then the sizes (13).
    func snapshotV2() -> ([Float], UInt32) {
        let (points, flags) = snapshot()
        return (points + sizeSnapshot(), flags)
    }
}

/// The synchronous C reader may be called from a different thread. Only plain
/// values are read under this lock; there are no UIKit calls in the render loop.
final class TouchPreferences: ObservableObject {
    static let shared = TouchPreferences()
    static let key = "touchControls.v1"
    @Published private(set) var configuration: TouchConfiguration
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var cached: TouchConfiguration

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let config = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(TouchConfiguration.self, from: $0) } ?? TouchConfiguration()
        configuration = config; cached = config
    }
    func save(_ value: TouchConfiguration) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
        lock.lock(); cached = value; lock.unlock()
        configuration = value
    }
    func snapshot() -> ([Float], UInt32) {
        lock.lock(); defer { lock.unlock() }
        return cached.snapshot()
    }
    func snapshotV2() -> ([Float], UInt32) {
        lock.lock(); defer { lock.unlock() }
        return cached.snapshotV2()
    }
}

@_cdecl("horizon_touch_preferences_v1")
public func horizonTouchPreferences(_ buffer: UnsafeMutablePointer<Float>?, _ capacity: UInt32) -> UInt32 {
    guard let buffer, capacity >= 20 else { return 0 }
    let (values, flags) = TouchPreferences.shared.snapshot()
    for i in 0..<20 { buffer[i] = values[i] }
    return flags
}

/// ABI v2: 26 centres then 13 sizes, 39 floats, NaN for the built-in placement or size.
@_cdecl("horizon_touch_preferences_v2")
public func horizonTouchPreferencesV2(_ buffer: UnsafeMutablePointer<Float>?, _ capacity: UInt32) -> UInt32 {
    guard let buffer, capacity >= 39 else { return 0 }
    let (values, flags) = TouchPreferences.shared.snapshotV2()
    for i in 0..<39 { buffer[i] = values[i] }
    return flags
}

struct TouchControlsSettings: View {
    @ObservedObject private var preferences = TouchPreferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Touch controls")
            SecondaryButton(title: "Edit button layout", icon: "hand.draw") { presentTouchEditor() }
                .accessibilityIdentifier("touch-edit-layout")
            Toggle("Show touch controls", isOn: Binding(get: { preferences.configuration.showControls }, set: { value in
                var c = preferences.configuration; c.showControls = value; preferences.save(c)
            })).accessibilityIdentifier("touch-show-controls")
            Text("Controls remain visible during screen recording. For a clean system screenshot, turn off Show touch controls first; the touch areas remain active.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

@MainActor
func presentTouchEditor() {
    guard let presenter = gameViewController() else { return }
    let host = TouchEditorController(rootView: AnyView(EmptyView()))
    host.modalPresentationStyle = .fullScreen
    let previous = presenter.view.window?.windowScene?.interfaceOrientation ?? .portrait
    let restore: UIInterfaceOrientationMask
    switch previous {
    case .landscapeLeft: restore = .landscapeLeft
    case .landscapeRight: restore = .landscapeRight
    case .portraitUpsideDown: restore = .portraitUpsideDown
    default: restore = .portrait
    }
    host.rootView = AnyView(TouchLayoutEditor(initial: TouchPreferences.shared.configuration) { [weak host] saved in
        guard let host else { return }
        if let saved { TouchPreferences.shared.save(saved) }
        let scene = host.view.window?.windowScene
        host.dismiss(animated: true) {
            turn(scene, to: UIDevice.current.userInterfaceIdiom == .pad ? restore : .portrait)
        }
    })
    presenter.present(host, animated: true)
}

private final class TouchEditorController: UIHostingController<AnyView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersStatusBarHidden: Bool { true }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        turn(view.window?.windowScene, to: .landscape)
    }
}

private struct TouchLayoutEditor: View {
    /// A button's size being changed in the mini panel, and the size to go back to on Cancel.
    private struct SizeEdit {
        let button: TouchButton
        let original: Double?
    }

    @State private var draft: TouchConfiguration
    @State private var dragStart: CGPoint?
    @State private var selected: TouchButton?
    @State private var sizing: SizeEdit?
    @State private var confirmReset = false
    @State private var toolbarCentre: CGPoint?
    @State private var toolbarStart: CGPoint?
    @State private var guiLimit = TouchEditorGeometry.savedScale()
    let finish: (TouchConfiguration?) -> Void

    init(initial: TouchConfiguration, finish: @escaping (TouchConfiguration?) -> Void) {
        _draft = State(initialValue: initial)
        self.finish = finish
    }

    var body: some View {
        GeometryReader { geometry in
            editorCanvas(in: geometry.size)
        }
        .ignoresSafeArea()
        .background(Color.black)
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .confirmationDialog("Reset all button positions and sizes?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Layout", role: .destructive) { resetLayout() }
        } message: {
            Text("Save to keep the default layout, or Cancel to keep your current layout.")
        }
    }

    // MARK: Canvas

    private func editorCanvas(in size: CGSize) -> some View {
        let metrics = TouchEditorGeometry(size: size, displayScale: UIScreen.main.scale, limit: guiLimit)
        return ZStack(alignment: .topLeading) {
            Color.black
                .contentShape(Rectangle())
                .onTapGesture { deselect() }
            hotbarOutline(metrics)
            ForEach(TouchButton.allCases) { button in
                buttonView(button, metrics: metrics)
            }
            editorToolbar(in: size)
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: size) { _ in
            toolbarCentre = nil
            toolbarStart = nil
        }
    }

    private func hotbarOutline(_ metrics: TouchEditorGeometry) -> some View {
        let scale: CGFloat = metrics.pointsPerUnit
        let centreX: CGFloat = (metrics.gui.width / 2) * scale
        let centreY: CGFloat = (metrics.gui.height - 11) * scale
        return Rectangle()
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
            .frame(width: 182 * scale, height: 22 * scale)
            .position(x: centreX, y: centreY)
            .allowsHitTesting(false)
    }

    private func buttonView(_ button: TouchButton, metrics: TouchEditorGeometry) -> some View {
        let scale: CGFloat = metrics.pointsPerUnit
        let rect: CGRect = draft.rect(button, in: metrics.gui)
        let isSelected: Bool = (selected == button)
        let fontSize: CGFloat = max(12, rect.height * scale * 0.34)
        let width: CGFloat = rect.width * scale
        let height: CGFloat = rect.height * scale
        let centreX: CGFloat = rect.midX * scale
        let centreY: CGFloat = rect.midY * scale
        let fill: Color = isSelected ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.18)
        let outline: Color = isSelected ? Color.yellow : Color.white.opacity(0.6)
        let outlineWidth: CGFloat = isSelected ? 2 : 1
        let layer: Double = isSelected ? 1 : 0
        let identifier: String = "touch-layout-\(button.rawValue)"
        return Image(systemName: button.symbol)
            .font(.system(size: fontSize, weight: .semibold))
            .frame(width: width, height: height)
            .background(fill)
            .overlay(Rectangle().stroke(outline, lineWidth: outlineWidth))
            .clipShape(Rectangle())
            .contentShape(Rectangle())
            .position(x: centreX, y: centreY)
            .zIndex(layer)
            .accessibilityLabel(button.title)
            .accessibilityIdentifier(identifier)
            .allowsHitTesting(sizing == nil)
            .gesture(dragGesture(button, rect: rect, metrics: metrics))
    }

    private func dragGesture(_ button: TouchButton, rect: CGRect, metrics: TouchEditorGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragChanged(button, rect: rect, translation: value.translation, metrics: metrics)
            }
            .onEnded { _ in
                dragStart = nil
            }
    }

    private func dragChanged(_ button: TouchButton, rect: CGRect, translation: CGSize, metrics: TouchEditorGeometry) {
        let alreadyDragging: Bool = (selected == button) && (dragStart != nil)
        if !alreadyDragging {
            selected = button
            dragStart = CGPoint(x: rect.midX, y: rect.midY)
        }
        guard let start = dragStart else { return }
        let scale: CGFloat = metrics.pointsPerUnit
        let targetX: CGFloat = start.x + translation.width / scale
        let targetY: CGFloat = start.y + translation.height / scale
        draft.move(button, to: CGPoint(x: targetX, y: targetY), in: metrics.gui)
    }

    // MARK: Toolbar

    private func editorToolbar(in size: CGSize) -> some View {
        let toolbarWidth: CGFloat = min(500, max(280, size.width - 32))
        let position: CGPoint = toolbarCentre ?? CGPoint(x: size.width / 2, y: size.height / 2)
        return VStack(spacing: 0) {
            toolbarHandle(in: size, toolbarWidth: toolbarWidth)
            mainRow
            detailRow
        }
        .frame(width: toolbarWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .position(position)
        .zIndex(2)
    }

    private func toolbarHandle(in size: CGSize, toolbarWidth: CGFloat) -> some View {
        Image(systemName: "line.3.horizontal")
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel("Move editing toolbar")
            .accessibilityIdentifier("touch-toolbar-handle")
            .gesture(
                DragGesture()
                    .onChanged { value in
                        moveToolbar(by: value.translation, in: size, toolbarWidth: toolbarWidth)
                    }
                    .onEnded { _ in
                        toolbarStart = nil
                    }
            )
    }

    private func moveToolbar(by translation: CGSize, in size: CGSize, toolbarWidth: CGFloat) {
        let fallback = CGPoint(x: size.width / 2, y: size.height / 2)
        let origin: CGPoint = toolbarStart ?? toolbarCentre ?? fallback
        toolbarStart = origin
        let minX: CGFloat = toolbarWidth / 2
        let maxX: CGFloat = size.width - toolbarWidth / 2
        let x: CGFloat = min(maxX, max(minX, origin.x + translation.width))
        let y: CGFloat = min(size.height - 70, max(70, origin.y + translation.height))
        toolbarCentre = CGPoint(x: x, y: y)
    }

    /// Cancel, the button picker, Reset and Save. Locked while a size is being changed.
    private var mainRow: some View {
        HStack(spacing: 20) {
            Button { finish(nil) } label: { Text("Cancel").frame(minWidth: 50, minHeight: 44) }
                .accessibilityIdentifier("touch-editor-cancel")
            Spacer(minLength: 4)
            selectMenu
            Spacer(minLength: 4)
            Button { confirmReset = true } label: { Text("Reset").frame(minWidth: 50, minHeight: 44) }
                .accessibilityIdentifier("touch-editor-reset")
            Button { finish(draft) } label: { Text("Save").fontWeight(.semibold).frame(minWidth: 50, minHeight: 44) }
                .accessibilityIdentifier("touch-editor-save")
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .disabled(sizing != nil)
    }

    private var selectMenu: some View {
        Menu {
            ForEach(TouchButton.allCases) { button in
                Button(button.title) { select(button) }
            }
        } label: {
            Label(selected?.title ?? "Touch Layout", systemImage: "hand.draw")
        }
        .accessibilityIdentifier("touch-editor-select")
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
    }

    /// Under the main row: the Size button for the selected button, or the mini size panel.
    @ViewBuilder private var detailRow: some View {
        if let edit = sizing {
            sizePanel(edit)
        } else if let button = selected {
            sizeButtonRow(button)
        }
    }

    private func sizeButtonRow(_ button: TouchButton) -> some View {
        VStack(spacing: 0) {
            separator
            HStack {
                Text(button.title).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button { beginSizing(button) } label: { Text("Size").fontWeight(.semibold).frame(minWidth: 60, minHeight: 44) }
                    .accessibilityIdentifier("touch-editor-size")
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
        }
    }

    /// The mini panel: drag the slider left or right, then Done keeps the size and Cancel puts back the one
    /// the button had.
    private func sizePanel(_ edit: SizeEdit) -> some View {
        let percent: Int = Int((draft.scale(edit.button) * 100).rounded())
        let range: ClosedRange<Double> = TouchConfiguration.minScale...TouchConfiguration.maxScale
        return VStack(spacing: 0) {
            separator
            HStack(spacing: 12) {
                Button { cancelSize(edit) } label: { Text("Cancel").frame(minWidth: 50, minHeight: 44) }
                    .accessibilityIdentifier("touch-size-cancel")
                Slider(value: sizeBinding(edit.button), in: range)
                    .accessibilityIdentifier("touch-size-slider")
                Text("\(percent)%")
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
                Button { sizing = nil } label: { Text("Done").fontWeight(.semibold).frame(minWidth: 50, minHeight: 44) }
                    .accessibilityIdentifier("touch-size-done")
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
        }
    }

    // MARK: Actions

    private func select(_ button: TouchButton) {
        selected = button
        dragStart = nil
    }

    private func deselect() {
        if sizing == nil { selected = nil }
    }

    private func beginSizing(_ button: TouchButton) {
        sizing = SizeEdit(button: button, original: draft.sizes[String(button.rawValue)])
    }

    private func sizeBinding(_ button: TouchButton) -> Binding<Double> {
        Binding<Double>(
            get: { Double(draft.scale(button)) },
            set: { newValue in draft.setScale(button, newValue) }
        )
    }

    private func cancelSize(_ edit: SizeEdit) {
        draft.sizes[String(edit.button.rawValue)] = edit.original
        sizing = nil
    }

    private func resetLayout() {
        draft.centres = [:]
        draft.sizes = [:]
        selected = nil
        dragStart = nil
    }
}

/// Same integer scale selection and ceil-to-GUI dimensions as HudBatch::new.
struct TouchEditorGeometry {
    let gui: CGSize
    let pointsPerUnit: CGFloat
    init(size: CGSize, displayScale: CGFloat, limit: Int) {
        let density = max(1, displayScale)
        let pixels = (Int((size.width * density).rounded()), Int((size.height * density).rounded()))
        var scale = 1
        while (limit == 0 || scale < limit) && pixels.0 / (scale + 1) >= 320 && pixels.1 / (scale + 1) >= 240 {
            scale += 1
        }
        gui = CGSize(width: ceil(Double(pixels.0) / Double(scale)), height: ceil(Double(pixels.1) / Double(scale)))
        pointsPerUnit = CGFloat(scale) / density
    }
    static func savedScale() -> Int {
        let url = GameFolder.documents.appendingPathComponent("options.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let value = text.split(separator: "\n").last(where: { $0.hasPrefix("guiScale:") })
        return max(0, value.flatMap { Int($0.dropFirst("guiScale:".count).trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0)
    }
}
