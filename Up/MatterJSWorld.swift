import Foundation
import JavaScriptCore

/// Thin wrapper that runs the Matter.js physics engine inside a JSContext.
/// All bookkeeping (engine, bodies, grow timers, spawn logic) lives on the JS
/// side; Swift only drives stepping and pulls render-state out each frame.
@MainActor
final class MatterJSWorld {
    struct BodyState {
        let id: Int
        let size: Double          // radius
        let x: Double
        let y: Double
        let angle: Double
    }

    let boxWidth: Double
    let minBoxHeight: Double
    let topPadding: Double
    private(set) var currentBoxHeight: Double

    private let context: JSContext
    // Cached UpScene functions — evaluateScript re-parses the source string on
    // every call, so we resolve JSValues once and invoke them via call().
    private let fnTick: JSValue
    private let fnSpawn: JSValue
    private let fnSpawnGiant: JSValue
    private let fnSnapshot: JSValue
    private let fnTowerTop: JSValue
    private let fnShake: JSValue
    private let fnRemoveBody: JSValue
    private let fnShapeCount: JSValue
    private let fnOnlySmallRemain: JSValue

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

        ctx.evaluateScript(Self.bootstrapScript(boxWidth: boxWidth))

        guard let upScene = ctx.objectForKeyedSubscript("UpScene") else {
            fatalError("UpScene not defined after bootstrap")
        }
        self.fnTick = upScene.objectForKeyedSubscript("tick")
        self.fnSpawn = upScene.objectForKeyedSubscript("spawn")
        self.fnSpawnGiant = upScene.objectForKeyedSubscript("spawnGiant")
        self.fnSnapshot = upScene.objectForKeyedSubscript("snapshot")
        self.fnTowerTop = upScene.objectForKeyedSubscript("towerTop")
        self.fnShake = upScene.objectForKeyedSubscript("shake")
        self.fnRemoveBody = upScene.objectForKeyedSubscript("removeBody")
        self.fnShapeCount = upScene.objectForKeyedSubscript("shapeCount")
        self.fnOnlySmallRemain = upScene.objectForKeyedSubscript("onlySmallRemain")
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
        fnTick.call(withArguments: [dtMs])
    }

    /// Spawn a new shape. Returns the JS-side body id (unique per shape).
    /// `boxHeight` is the current popover visible height in pixels — shapes
    /// spawn just above that, outside the visible area, and fall in.
    @discardableResult
    func spawn(boxHeight: Double) -> Int {
        let result = fnSpawn.call(withArguments: [boxHeight])
        return Int(result?.toInt32() ?? -1)
    }

    var shapeCount: Int {
        Int(fnShapeCount.call(withArguments: [])?.toInt32() ?? 0)
    }

    /// Give every body an upward impulse so the stack sloshes and resettles,
    /// like jostling a cup. `strength` is in Matter velocity units (px/step).
    func shake(strength: Double = 4.7) {
        fnShake.call(withArguments: [strength])
    }

    /// True once only the smallest shapes remain (the big early shapes have all
    /// been popped away). Used to time the easter-egg giant drop.
    var onlySmallRemain: Bool {
        fnOnlySmallRemain.call(withArguments: [])?.toBool() ?? false
    }

    /// Easter egg: drop one giant shape (4× the max normal size).
    @discardableResult
    func spawnGiant(boxHeight: Double) -> Int {
        let result = fnSpawnGiant.call(withArguments: [boxHeight])
        return Int(result?.toInt32() ?? -1)
    }

    /// Remove a body from the simulation. Subsequent snapshots will not include it.
    @discardableResult
    func remove(id: Int) -> Bool {
        let result = fnRemoveBody.call(withArguments: [id])
        return result?.toBool() ?? false
    }

    /// Snapshot every dynamic body's render-relevant state.
    func snapshot() -> [BodyState] {
        guard let value = fnSnapshot.call(withArguments: []),
              let array = value.toArray() as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let id   = dict["id"]    as? Int,
                  let size = dict["size"]  as? Double,
                  let x    = dict["x"]     as? Double,
                  let y    = dict["y"]     as? Double,
                  let angle = dict["angle"] as? Double else { return nil }
            return BodyState(id: id, size: size, x: x, y: y, angle: angle)
        }
    }

    /// Recompute the popover box height each frame.
    /// Monotonic: it grows toward the target but never shrinks, which keeps the
    /// popover from quivering when shapes micro-settle.
    func updateBoxHeight() -> Double {
        let towerTop = fnTowerTop.call(withArguments: [])?.toDouble() ?? 0
        let target = Swift.max(minBoxHeight, towerTop + topPadding)
        if target > currentBoxHeight {
            currentBoxHeight += (target - currentBoxHeight) * 0.15
        }
        return currentBoxHeight
    }

    // MARK: - Bootstrap JS

    private static func bootstrapScript(boxWidth: Double) -> String {
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
            const CIRCLE_MIN_RADIUS = 5;
            const CIRCLE_MAX_RADIUS = 40;
            // Easter egg: a single giant shape, diameter 240 — fills most of the
            // popover width while leaving a ~20px margin on each side.
            const GIANT_RADIUS = (containerWidth - 40) / 2;
            // A shape counts as "small" (one of the last to spawn) below this.
            const SMALL_RADIUS_THRESHOLD = CIRCLE_MIN_RADIUS * 2;
            let giantSpawned = false;

            const MAX_COUNT = 50;
            // Distance above the popover's visible top edge at which new shapes
            // appear. They drop into view under gravity.
            const SPAWN_OFFSET_ABOVE_TOP = 40;
            // Initial downward speed given to a newly spawned shape (Matter.js
            // velocity units = pixels per ~16.67ms step). Gives the fall some
            // weight from the first frame instead of starting from rest.
            const SPAWN_INITIAL_VELOCITY_Y = 6;

            let dynamicBodies = [];
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
                if (dynamicBodies.length >= MAX_COUNT) return -1;

                // Radius grows linearly with fill progress so early shapes are
                // small and later shapes are large.
                const progress = dynamicBodies.length / MAX_COUNT;
                const radius = CIRCLE_MAX_RADIUS
                    - progress * (CIRCLE_MAX_RADIUS - CIRCLE_MIN_RADIUS);

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
                data.set(id, { size: radius });
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
                        size: info.size,
                        x: b.position.x,
                        y: floorY - b.position.y + FLOOR_OFFSET,
                        angle: -b.angle
                    });
                }
                return out;
            }

            // Easter egg helpers ----------------------------------------------

            // True once every remaining body is "small" — i.e. all the larger
            // early shapes have been popped away, which only happens after the
            // completion popover has been left open a long while.
            function onlySmallRemain() {
                if (dynamicBodies.length === 0) return false;
                for (const b of dynamicBodies) {
                    const info = data.get(b.upId);
                    if (info && info.size > SMALL_RADIUS_THRESHOLD) return false;
                }
                return true;
            }

            // Drop a single huge shape from above the popover's top edge.
            function spawnGiant(boxHeight) {
                if (giantSpawned) return -1;
                giantSpawned = true;

                const radius = GIANT_RADIUS;
                const spawnY = floorY - boxHeight - radius - SPAWN_OFFSET_ABOVE_TOP;
                const body = M.Bodies.circle(cx, spawnY, radius, {
                    restitution: 0,
                    friction: 1,
                    frictionStatic: 2,
                    density: 0.004,
                    isStatic: false
                });
                M.Body.setVelocity(body, { x: 0, y: SPAWN_INITIAL_VELOCITY_Y });

                const id = nextId++;
                body.upId = id;
                body.isGiant = true;
                M.Composite.add(engine.world, body);
                dynamicBodies.push(body);
                data.set(id, { size: radius });
                return id;
            }

            // Kick every body upward (with a little lateral jitter) so the
            // settled stack briefly sloshes and falls back into place.
            function shake(strength) {
                for (const b of dynamicBodies) {
                    M.Body.setVelocity(b, {
                        x: b.velocity.x + (Math.random() - 0.5) * strength,
                        y: b.velocity.y - strength
                    });
                }
            }

            function removeBody(id) {
                const body = dynamicBodies.find(b => b.upId === id);
                if (!body) return false;
                // If the giant is removed, re-arm it so it can drop again once
                // only small shapes remain.
                if (body.isGiant) giantSpawned = false;
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
                shake,
                onlySmallRemain,
                spawnGiant,
                removeBody,
                shapeCount: () => dynamicBodies.length
            };
        })();
        """
    }
}

