import Foundation
import JavaScriptCore

/// Thin wrapper that runs the Matter.js physics engine inside a JSContext.
/// All bookkeeping (engine, bodies, grow timers, spawn logic) lives on the JS
/// side; Swift only drives stepping and pulls render-state out each frame.
@MainActor
final class MatterJSWorld {
    struct BodyState {
        let id: Int
        let kind: String          // circle (others removed)
        let palette: Int          // index into ShapePalette.colors
        let size: Double          // shape-specific dimension (radius for circle)
        let x: Double
        let y: Double
        let angle: Double
        let scale: Double
    }

    let boxWidth: Double
    let minBoxHeight: Double
    let topPadding: Double
    private(set) var currentBoxHeight: Double

    private let context: JSContext
    private var lastTime: TimeInterval = 0

    init(boxWidth: Double = 280, minBoxHeight: Double = 80, topPadding: Double = 16) {
        self.boxWidth = boxWidth
        self.minBoxHeight = minBoxHeight
        self.topPadding = topPadding
        self.currentBoxHeight = minBoxHeight

        guard let ctx = JSContext() else {
            fatalError("Failed to create JSContext")
        }
        self.context = ctx

        ctx.exceptionHandler = { _, exception in
            if let exception {
                print("[MatterJS] JS exception: \(exception)")
            }
        }

        // JSContext lacks `performance.now()` and `setTimeout`/`setInterval`.
        // Matter.js references the former for its internal timing fallback; our
        // grow logic uses it explicitly. Install a minimal shim BEFORE matter.js
        // loads.
        Self.installPerformanceShim(into: ctx)

        guard let url = Bundle.main.url(forResource: "matter.min", withExtension: "js"),
              let source = try? String(contentsOf: url) else {
            fatalError("matter.min.js not found in bundle")
        }
        ctx.evaluateScript(source)

        ctx.evaluateScript(Self.bootstrapScript(boxWidth: boxWidth, minBoxHeight: minBoxHeight))
    }

    private static func installPerformanceShim(into ctx: JSContext) {
        let start = Date()
        let now: @convention(block) () -> Double = {
            -start.timeIntervalSinceNow * 1000.0
        }
        let perf = JSValue(newObjectIn: ctx)
        perf?.setObject(now, forKeyedSubscript: "now" as NSString)
        ctx.setObject(perf, forKeyedSubscript: "performance" as NSString)
    }

    /// Advance the simulation by the given time delta.
    func step(dt: TimeInterval) {
        // Matter.js Engine.update takes milliseconds.
        let dtMs = min(dt * 1000.0, 33.0)  // clamp so a hiccup doesn't blow up physics
        _ = context.evaluateScript("UpScene.tick(\(dtMs))")
    }

    /// Spawn a new shape. Returns the JS-side body id (unique per shape).
    @discardableResult
    func spawn() -> Int {
        let result = context.evaluateScript("UpScene.spawn()")
        return Int(result?.toInt32() ?? -1)
    }

    var shapeCount: Int {
        Int(context.evaluateScript("UpScene.shapeCount()")?.toInt32() ?? 0)
    }

    /// Remove a body from the simulation. Subsequent snapshots will not include it.
    @discardableResult
    func remove(id: Int) -> Bool {
        let result = context.evaluateScript("UpScene.removeBody(\(id))")
        return result?.toBool() ?? false
    }

    /// Snapshot every dynamic body's render-relevant state.
    func snapshot() -> [BodyState] {
        guard let value = context.evaluateScript("UpScene.snapshot()"),
              let array = value.toArray() as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let id = dict["id"] as? Int,
                  let kind = dict["kind"] as? String,
                  let palette = dict["palette"] as? Int,
                  let size = dict["size"] as? Double,
                  let x = dict["x"] as? Double,
                  let y = dict["y"] as? Double,
                  let angle = dict["angle"] as? Double,
                  let scale = dict["scale"] as? Double else { return nil }
            return BodyState(id: id, kind: kind, palette: palette, size: size,
                             x: x, y: y, angle: angle, scale: scale)
        }
    }

    /// Recompute the popover box height each frame.
    /// Monotonic: it grows toward the target but never shrinks, which keeps the
    /// popover from quivering when shapes micro-settle.
    func updateBoxHeight() -> Double {
        let towerTop = context.evaluateScript("UpScene.towerTop()")?.toDouble() ?? 0
        let target = Swift.max(minBoxHeight, towerTop + topPadding)
        if target > currentBoxHeight {
            currentBoxHeight += (target - currentBoxHeight) * 0.15
        }
        return currentBoxHeight
    }

    // MARK: - Bootstrap JS

    private static func bootstrapScript(boxWidth: Double, minBoxHeight: Double) -> String {
        // The JS side mirrors the demo exactly: same gravity/iterations, walls,
        // shape sizes scaled to our box width, grow-from-floor mechanic, etc.
        // We do NOT do any rendering in JS — Swift renders via SKShapeNodes.
        return """
        (function(){
            const M = Matter;
            const engine = M.Engine.create();
            engine.gravity.y = 1;
            engine.positionIterations = 10;
            engine.velocityIterations = 8;

            const containerWidth = \(boxWidth);
            const wallThickness = 80;
            const cx = containerWidth / 2;
            // We use Matter.js's screen-style coords internally: Y grows downward
            // and the floor lives at floorY. Swift converts to Y-up for SpriteKit.
            const floorY = 2000;  // arbitrary positive number; Swift maps positions back to Y-up

            const ground = M.Bodies.rectangle(cx, floorY + wallThickness / 2,
                                              containerWidth, wallThickness, { isStatic: true });
            const leftWall = M.Bodies.rectangle(-wallThickness / 2, floorY / 2,
                                                wallThickness, floorY * 4, { isStatic: true });
            const rightWall = M.Bodies.rectangle(containerWidth + wallThickness / 2, floorY / 2,
                                                 wallThickness, floorY * 4, { isStatic: true });
            M.Composite.add(engine.world, [ground, leftWall, rightWall]);

            // Circle radius range — diameter 40..80, so radius 20..40.
            const CIRCLE_MIN_RADIUS = 20;
            const CIRCLE_MAX_RADIUS = 40;

            const PALETTE_COUNT = 2;
            // Sequential palette index — alternates 0, 1, 0, 1, ...
            let nextPaletteIdx = 0;
            const MAX_COUNT = 50;
            const GROW_DURATION_MS = 200;
            // Shapes spawn directly at their resting position so the appearance
            // reads as a pure pop-in rather than a fall. Set to a small positive
            // value if you want a subtle drop.
            const SPAWN_DROP_HEIGHT = 0;

            let dynamicBodies = [];
            let shapeCount = 0;
            let nextId = 1;
            // Active grow animations keyed by body id.
            const grows = new Map();
            // Per-body bookkeeping (kind, palette index, currentScale, targetHeight).
            const data = new Map();

            function spawn() {
                // Spawn until the on-screen count reaches MAX_COUNT. When a shape
                // is popped (removeBody), the next timed tick refills the slot.
                if (dynamicBodies.length >= MAX_COUNT) return -1;
                const paletteIdx = nextPaletteIdx;
                nextPaletteIdx = (nextPaletteIdx + 1) % PALETTE_COUNT;

                // Random circle radius within configured range.
                const radius = CIRCLE_MIN_RADIUS
                    + Math.random() * (CIRCLE_MAX_RADIUS - CIRCLE_MIN_RADIUS);

                const visualW = radius * 2;
                const margin = visualW / 2 + 12;
                const maxJitter = Math.max(0, containerWidth / 2 - margin);
                const jitter = (Math.random() - 0.5) * 2 * maxJitter;
                const x = cx + jitter;

                // Resting base: the top of whichever existing shape overlaps the
                // new body's x range (smaller y in Matter coords = visually higher).
                // Falls back to the floor when the column is empty, so shapes only
                // start stacking from the tower once the ground is occupied.
                const newMinX = x - radius;
                const newMaxX = x + radius;
                let baseFloor = floorY;
                for (const b of dynamicBodies) {
                    if (b.bounds.max.x > newMinX && b.bounds.min.x < newMaxX) {
                        if (b.bounds.min.y < baseFloor) baseFloor = b.bounds.min.y;
                    }
                }

                const base = {
                    restitution: 0.05,
                    friction: 0.9,
                    frictionStatic: 1.5,
                    density: 0.002,
                    isStatic: false
                };
                const body = M.Bodies.circle(x, baseFloor, radius, base);
                const originalHeight = radius * 2;
                M.Body.setAngle(body, (Math.random() - 0.5) * 0.3);

                // Body is dynamic from the moment it spawns and keeps its full
                // physical size — only the *visual* scale animates. Scaling the
                // physics body during the spring overshoot caused the post-peak
                // shrink to detach the body from the floor and drop it again,
                // which read as a late "fall at the end of the animation".
                const initialScale = 0.05;
                const restingCenterY = baseFloor - originalHeight / 2;
                const spawnCenterY = restingCenterY - SPAWN_DROP_HEIGHT;
                M.Body.setPosition(body, { x: x, y: spawnCenterY });

                const id = nextId++;
                body.upId = id;
                M.Composite.add(engine.world, body);
                dynamicBodies.push(body);
                shapeCount++;

                data.set(id, {
                    kind: 'circle',
                    palette: paletteIdx,
                    currentScale: initialScale,
                    originalHeight: originalHeight,
                    size: radius,
                    spawnX: x,
                    baseFloor: baseFloor
                });
                grows.set(id, { startTime: performance.now(), targetScale: 1.0 });
                return id;
            }

            function advanceGrows(now) {
                // Ease-out-back tuned for ~5% overshoot — soft pop. Visual-only:
                // physical size is left untouched so post-peak settle doesn't
                // shift the body downward.
                // Peak overshoot = 4·c1³ / (27·(c1+1)²). c1 ≈ 1.165 → ~5%.
                const BACK_C1 = 1.165;
                const BACK_C3 = BACK_C1 + 1;
                for (const [id, g] of grows.entries()) {
                    const t = Math.min((now - g.startTime) / GROW_DURATION_MS, 1);
                    const eased = 1 + BACK_C3 * Math.pow(t - 1, 3) + BACK_C1 * Math.pow(t - 1, 2);
                    const newScale = 0.05 + (g.targetScale - 0.05) * eased;
                    const info = data.get(id);
                    if (!info) { grows.delete(id); continue; }
                    info.currentScale = newScale;
                    if (t >= 1) {
                        grows.delete(id);
                    }
                }
            }

            // Engine step: advance grow animations, then engine.update.
            // Matter.js engine ticks at fixed delta (16.667ms by default for setInterval-driven
            // pages); we feed it our actual frame delta so motion is correct.
            function tick(dtMs) {
                advanceGrows(performance.now());
                M.Engine.update(engine, dtMs);
            }

            // Tower top is the topmost (smallest y in Matter coords) bound.min.y of any body.
            function towerTop() {
                let minY = floorY;
                for (const b of dynamicBodies) {
                    if (b.bounds.min.y < minY) minY = b.bounds.min.y;
                }
                // Match the visual FLOOR_OFFSET applied in snapshot().
                return Math.max(0, floorY - minY) + FLOOR_OFFSET;
            }

            // Shapes sit directly on the 확인 button (which visually serves as the
            // ground), so no extra offset is needed — scene y=0 aligns with the
            // button's top edge.
            const FLOOR_OFFSET = 0;

            // Render snapshot: positions in our scene's Y-up space (floor at y=0).
            function snapshot() {
                const out = [];
                for (const b of dynamicBodies) {
                    const info = data.get(b.upId);
                    if (!info) continue;
                    out.push({
                        id: b.upId,
                        kind: info.kind,
                        palette: info.palette,
                        size: info.size,
                        x: b.position.x,
                        y: floorY - b.position.y + FLOOR_OFFSET,  // Y-down → Y-up, lifted
                        angle: -b.angle,                          // Y flip → flip rotation sign
                        scale: info.currentScale
                    });
                }
                return out;
            }

            function removeBody(id) {
                const body = dynamicBodies.find(b => b.upId === id);
                if (!body) return false;
                M.Composite.remove(engine.world, body);
                dynamicBodies = dynamicBodies.filter(b => b.upId !== id);
                data.delete(id);
                grows.delete(id);
                return true;
            }

            globalThis.UpScene = {
                spawn,
                tick,
                snapshot,
                towerTop,
                removeBody,
                shapeCount: () => dynamicBodies.length
            };
        })();
        """
    }
}

