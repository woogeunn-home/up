import AppKit
import SwiftUI

/// SwiftUI-rendered stacking animation. Physics still runs inside `MatterJSWorld`
/// (Matter.js via JSContext); this view simply draws each tick's snapshot as
/// SwiftUI shape views so we can apply Liquid Glass material to them.
struct CompletionAnimationView: View {
    /// Called when the user taps the empty floor — lets the host shake the
    /// popover window in sync with the slosh.
    var onShake: (() -> Void)?

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
        .onAppear { holder.onShake = onShake }
    }

    private var contentZStack: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(holder.shapes, id: \.id) { state in
                circleBody(for: state)
                    .scaleEffect(holder.popScale(for: state.id))
                    .position(
                        x: CGFloat(state.x),
                        y: holder.boxHeight - CGFloat(state.y)
                    )
            }
        }
        // Tapping the empty floor of the container (anywhere not on a shape)
        // jostles the whole stack so it sloshes and resettles.
        .contentShape(Rectangle())
        .onTapGesture {
            holder.shake()
        }
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
                    .frame(width: diameter * 0.275, height: diameter * 0.275)
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

    /// Host-supplied hook to shake the popover window in sync with the slosh.
    var onShake: (() -> Void)?

    /// Bodies that have been popped: their last-known state (frozen position)
    /// and the moment the pop started. The visual lingers for `popDuration`
    /// and shrinks in place via `popScale(for:)`.
    private var poppingStates: [Int: (state: MatterJSWorld.BodyState, startTime: TimeInterval)] = [:]

    private var timer: Timer?
    private var lastTime: TimeInterval = 0
    private var nextSpawnTime: TimeInterval = 0
    private var lastAutoPopTime: TimeInterval = 0
    private var heightFrozen = false
    /// Easter egg: set once the giant shape has dropped, after which the normal
    /// spawn/auto-pop loop halts and the popover grows to reveal it.
    private var giantDropped = false

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

        // ── 채우기 단계: 50개가 될 때까지 1.6초마다 작은 도형 보충 ──
        // (거대 도형이 떠 있으면 count >= 50이라 spawn은 자연히 멈춤)
        if now >= nextSpawnTime {
            nextSpawnTime = now + 1.6
            let id = world.spawn(boxHeight: world.currentBoxHeight)
            if id > 0 {
                NSSound(named: "Tink")?.play()
                shake()
            }
        }

        if !heightFrozen {
            // 50개 도달 → 높이 고정, 1초 후부터 auto-pop 시작
            if world.shapeCount >= 50 {
                heightFrozen = true
                lastAutoPopTime = now
            }
        } else {
            // ── 완성 단계 ──
            if world.onlySmallRemain {
                // 이스터에그: 큰 도형이 전부 빠지고 최소 크기 도형만 남으면
                // (= 완료 팝오버를 오래 열어두면) 거대 도형을 투하한다. 거대
                // 도형이 랜덤/탭으로 제거돼 다시 작은 도형만 남으면 재투하된다.
                if world.spawnGiant(boxHeight: world.currentBoxHeight) > 0 {
                    giantDropped = true
                    NSSound(named: "Submarine")?.play()
                    shake()
                }
            } else if world.shapeCount >= 50, now - lastAutoPopTime >= 1.0,
                      let target = world.snapshot().randomElement() {
                // 1초마다 pop 1개 — 거대 도형도 제거 풀에 포함된다.
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
        // Height grows during the fill phase, and again after the giant drops
        // so the popover expands to reveal it.
        if !heightFrozen || giantDropped {
            boxHeight = CGFloat(world.updateBoxHeight())
        }
    }

    /// The "slosh package": jostle the whole stack upward and shake the popover
    /// window in sync.
    func shake() {
        world.shake()
        onShake?()
    }

    func pop(id: Int) {
        if let state = shapes.first(where: { $0.id == id }) {
            poppingStates[id] = (state, CACurrentMediaTime())
        }
        world.remove(id: id)
        NSSound(named: "Pop")?.play()
        // Every disappearance triggers the slosh package.
        shake()
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
