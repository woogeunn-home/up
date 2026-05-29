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
    /// `boxHeight` is the current popover visible height in pixels — shapes
    /// spawn just above that, outside the visible area, and fall in.
    @discardableResult
    func spawn(boxHeight: Double) -> Int {
        let result = context.evaluateScript("UpScene.spawn(\(boxHeight))")
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
                  let angle = dict["angle"] as? Double else { return nil }
            return BodyState(id: id, kind: kind, palette: palette, size: size,
                             x: x, y: y, angle: angle)
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
            ground.isGround = true;
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
            // Distance above the popover's visible top edge at which new shapes
            // appear. They drop into view under gravity.
            const SPAWN_OFFSET_ABOVE_TOP = 40;
            // Initial downward speed given to a newly spawned shape (Matter.js
            // velocity units = pixels per ~16.67ms step). Gives the fall some
            // weight from the first frame instead of starting from rest.
            const SPAWN_INITIAL_VELOCITY_Y = 6;

            let dynamicBodies = [];
            let shapeCount = 0;
            let nextId = 1;
            // Per-body bookkeeping (kind, palette index, size).
            const data = new Map();
            // Body ids that have touched the ground or another landed body.
            // Falling shapes (still in flight from above the popover) are
            // excluded from tower-height calculations until they land — that
            // way the popover only grows to fit the actually-settled stack.
            const landed = new Set();

            M.Events.on(engine, 'collisionActive', function(event) {
                for (const pair of event.pairs) {
                    const a = pair.bodyA;
                    const b = pair.bodyB;
                    if (!a.isStatic && a.upId !== undefined) {
                        if (b.isGround || (b.upId !== undefined && landed.has(b.upId))) {
                            landed.add(a.upId);
                        }
                    }
                    if (!b.isStatic && b.upId !== undefined) {
                        if (a.isGround || (a.upId !== undefined && landed.has(a.upId))) {
                            landed.add(b.upId);
                        }
                    }
                }
            });

            function spawn(boxHeight) {
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

                // Spawn position is just above the popover's visible top edge so
                // the shape originates outside the popover and falls in.
                // Visible top in Matter coords = floorY - boxHeight.
                const spawnY = floorY - boxHeight - radius - SPAWN_OFFSET_ABOVE_TOP;

                const base = {
                    restitution: 0.05,
                    friction: 0.9,
                    frictionStatic: 1.5,
                    density: 0.002,
                    isStatic: false
                };
                const body = M.Bodies.circle(x, spawnY, radius, base);
                M.Body.setAngle(body, (Math.random() - 0.5) * 0.3);
                M.Body.setVelocity(body, { x: 0, y: SPAWN_INITIAL_VELOCITY_Y });

                const id = nextId++;
                body.upId = id;
                M.Composite.add(engine.world, body);
                dynamicBodies.push(body);
                shapeCount++;

                data.set(id, {
                    kind: 'circle',
                    palette: paletteIdx,
                    size: radius
                });
                return id;
            }

            // Matter.js engine ticks at fixed delta (16.667ms by default for setInterval-driven
            // pages); we feed it our actual frame delta so motion is correct.
            function tick(dtMs) {
                M.Engine.update(engine, dtMs);
            }

            // Tower top is the topmost (smallest y in Matter coords) bound.min.y
            // among bodies that have landed. Shapes still falling from above the
            // popover are excluded so they don't inflate the popover height
            // before they actually settle.
            function towerTop() {
                let minY = floorY;
                for (const b of dynamicBodies) {
                    if (!landed.has(b.upId)) continue;
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
                        angle: -b.angle                           // Y flip → flip rotation sign
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
                landed.delete(id);
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

