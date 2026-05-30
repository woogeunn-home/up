import AppKit
import SwiftUI

/// SwiftUI-rendered stacking animation. Physics still runs inside `MatterJSWorld`
/// (Matter.js via JSContext); this view simply draws each tick's snapshot as
/// SwiftUI shape views so we can apply Liquid Glass material to them.
struct CompletionAnimationView: View {
    @StateObject private var holder = AnimationHolder()
    @EnvironmentObject private var monitor: ActivityMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer {
                    contentZStack
                }
            } else {
                contentZStack
            }
        }
        .frame(width: AnimationHolder.boxWidth, height: holder.boxHeight)
        .clipped()
    }

    private var contentZStack: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(holder.shapes, id: \.id) { state in
                bodyView(for: state)
                    .scaleEffect(holder.popScale(for: state.id))
                    .position(
                        x: CGFloat(state.x),
                        // Convert Y-up scene coord → SwiftUI top-down coord.
                        y: holder.boxHeight - CGFloat(state.y)
                    )
            }
        }
    }

    @ViewBuilder
    private func bodyView(for state: MatterJSWorld.BodyState) -> some View {
        circleBody(for: state)
    }

    @ViewBuilder
    private func circleBody(for state: MatterJSWorld.BodyState) -> some View {
        let diameter = CGFloat(state.size) * 2  // size is radius for circles

        ZStack {
            if let custom = monitor.customShapeImage {
                Image(nsImage: custom)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            } else {
                let fill: Color = colorScheme == .dark ? .black : .white
                let icon: Color = colorScheme == .dark ? .white : .black
                Circle()
                    .fill(fill)
                    .frame(width: diameter, height: diameter)
                UpArrowGlyph()
                    .fill(icon)
                    .frame(width: 22, height: 22)
            }
        }
        .rotationEffect(.radians(state.angle))
        .onTapGesture {
            holder.pop(id: state.id)
        }
    }

}

// MARK: - Up arrow glyph

private struct UpArrowGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let viewBoxW: CGFloat = UpArrowPath.viewBoxWidth
        let viewBoxH: CGFloat = UpArrowPath.viewBoxHeight
        let scale = Swift.min(rect.width / viewBoxW, rect.height / viewBoxH)
        let dx = (rect.width - viewBoxW * scale) / 2
        let dy = (rect.height - viewBoxH * scale) / 2
        var t = CGAffineTransform(translationX: dx, y: dy + viewBoxH * scale)
            .scaledBy(x: scale, y: -scale)
        var combined = Path()
        if let chevron = UpArrowPath.chevronPath.copy(using: &t) { combined.addPath(Path(chevron)) }
        if let stem   = UpArrowPath.stemPath.copy(using: &t)    { combined.addPath(Path(stem)) }
        return combined
    }
}

// MARK: - Animation holder

/// Drives the Matter.js simulation via a periodic timer and publishes state to
/// SwiftUI. Replaces the old `SceneHolder` / `SpriteView` driver.
@MainActor
final class AnimationHolder: ObservableObject {
    static let boxWidth: CGFloat = 280
    static let minBoxHeight: CGFloat = 80
    /// Duration of the in-place pop scale-out animation.
    static let popDuration: TimeInterval = 0.09

    private let world = MatterJSWorld()
    @Published var shapes: [MatterJSWorld.BodyState] = []
    @Published var boxHeight: CGFloat = AnimationHolder.minBoxHeight

    /// Bodies that have been popped: their last-known state (frozen position)
    /// and the moment the pop started. The visual lingers for `popDuration`
    /// and shrinks in place via `popScale(for:)`.
    private var poppingStates: [Int: (state: MatterJSWorld.BodyState, startTime: TimeInterval)] = [:]

    private var timer: Timer?
    private var lastTime: TimeInterval = 0
    private var nextSpawnTime: TimeInterval = 0
    private var lastAutoPopTime: TimeInterval = 0
    private var heightFrozen = false

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if lastTime == 0 {
            lastTime = now
            nextSpawnTime = now
        }
        let dt = Swift.min(now - lastTime, 1.0 / 30.0)
        lastTime = now

        // 높이 프리즈 체크: pop 전에 먼저 확인해야 50→49 감소 이후에도 유지됨
        if !heightFrozen && world.shapeCount >= 50 {
            heightFrozen = true
        }

        if now >= nextSpawnTime {
            nextSpawnTime = now + 1.6
            let id = world.spawn(boxHeight: world.currentBoxHeight)
            if id > 0 {
                NSSound(named: "Tink")?.play()
            }
        }

        // 50개 도달 이후 1초마다 랜덤 도형 자동 팝
        if heightFrozen, now - lastAutoPopTime >= 1.0 {
            if let target = world.snapshot().randomElement() {
                lastAutoPopTime = now
                pop(id: target.id)
            }
        }

        world.step(dt: dt)

        let snapshot = world.snapshot()
        let snapshotIds = Set(snapshot.map { $0.id })

        // Drop popping entries whose animation window has elapsed.
        poppingStates = poppingStates.filter { _, value in
            now - value.startTime < Self.popDuration
        }

        // Render-list = live snapshot ∪ frozen popping shapes that aren't
        // already in the snapshot.
        var combined = snapshot
        for (id, popping) in poppingStates where !snapshotIds.contains(id) {
            combined.append(popping.state)
        }

        shapes = combined
        if !heightFrozen {
            boxHeight = CGFloat(world.updateBoxHeight())
        }
    }

    func pop(id: Int) {
        if let state = shapes.first(where: { $0.id == id }) {
            poppingStates[id] = (state, CACurrentMediaTime())
        }
        world.remove(id: id)
        NSSound(named: "Pop")?.play()
    }

    /// Scale factor for a body during its pop animation. 1.0 for normal bodies;
    /// 1.0 → 0.0 over `popDuration` for popping ones.
    func popScale(for id: Int) -> CGFloat {
        guard let popping = poppingStates[id] else { return 1.0 }
        let elapsed = CACurrentMediaTime() - popping.startTime
        let t = Swift.min(elapsed / Self.popDuration, 1.0)
        return CGFloat(1.0 - t)
    }
}
