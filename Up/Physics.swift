import Foundation

// MARK: - Vec2

struct Vec2: Equatable {
    var x: Double
    var y: Double

    static let zero = Vec2(x: 0, y: 0)

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(x: a.x - b.x, y: a.y - b.y) }
    static func * (s: Double, v: Vec2) -> Vec2 { Vec2(x: s * v.x, y: s * v.y) }
    static func * (v: Vec2, s: Double) -> Vec2 { Vec2(x: s * v.x, y: s * v.y) }
    static func / (v: Vec2, s: Double) -> Vec2 { Vec2(x: v.x / s, y: v.y / s) }
    static prefix func - (v: Vec2) -> Vec2 { Vec2(x: -v.x, y: -v.y) }
    static func += (a: inout Vec2, b: Vec2) { a = a + b }
    static func -= (a: inout Vec2, b: Vec2) { a = a - b }

    func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }
    func cross(_ other: Vec2) -> Double { x * other.y - y * other.x }
    var lengthSquared: Double { x * x + y * y }
    var length: Double { sqrt(lengthSquared) }
    func normalized() -> Vec2 {
        let l = length
        return l > 1e-9 ? Vec2(x: x / l, y: y / l) : .zero
    }
    /// 90° counterclockwise.
    func perp() -> Vec2 { Vec2(x: -y, y: x) }
    func rotated(by angle: Double) -> Vec2 {
        let c = cos(angle), s = sin(angle)
        return Vec2(x: c * x - s * y, y: s * x + c * y)
    }
}

// MARK: - AABB

struct AABB {
    var min: Vec2
    var max: Vec2

    func intersects(_ other: AABB) -> Bool {
        !(max.x < other.min.x || other.max.x < min.x ||
          max.y < other.min.y || other.max.y < min.y)
    }
}

// MARK: - Shape

enum PhysicsShape {
    case circle(radius: Double)
    /// Vertices in local coordinates, ordered counterclockwise around the centroid (origin).
    case polygon(localVertices: [Vec2])
}

// MARK: - Body

final class PhysicsBody {
    var position: Vec2
    var velocity: Vec2 = .zero
    var angle: Double
    var angularVelocity: Double = 0

    /// 0 means infinite mass (static or kinematic).
    var inverseMass: Double
    var inverseInertia: Double

    var restitution: Double
    var friction: Double

    private(set) var shape: PhysicsShape
    /// Polygon vertices transformed into world space; empty for circles.
    private(set) var worldVertices: [Vec2] = []
    private(set) var aabb = AABB(min: .zero, max: .zero)

    /// Static / kinematic bodies do not respond to forces but can still produce contacts.
    var isStatic: Bool

    /// Sleep state: a settled body that's skipped by the simulator until disturbed.
    var isSleeping: Bool = false
    /// Seconds the body has been below the sleep velocity threshold; once it exceeds
    /// the world's sleepTime it transitions to isSleeping = true.
    var sleepTimer: Double = 0

    func wake() {
        isSleeping = false
        sleepTimer = 0
    }

    init(shape: PhysicsShape,
         position: Vec2,
         angle: Double = 0,
         density: Double,
         restitution: Double,
         friction: Double,
         isStatic: Bool = false)
    {
        self.shape = shape
        self.position = position
        self.angle = angle
        self.restitution = restitution
        self.friction = friction
        self.isStatic = isStatic

        if isStatic {
            inverseMass = 0
            inverseInertia = 0
        } else {
            let mass: Double
            let inertia: Double
            switch shape {
            case .circle(let r):
                mass = density * .pi * r * r
                inertia = 0.5 * mass * r * r
            case .polygon(let verts):
                let (area, i) = Self.polygonAreaAndInertia(verts, density: density)
                mass = density * area
                inertia = i
            }
            inverseMass = mass > 0 ? 1 / mass : 0
            inverseInertia = inertia > 0 ? 1 / inertia : 0
        }
        updateTransform()
    }

    func setShape(_ newShape: PhysicsShape, density: Double) {
        shape = newShape
        let mass: Double
        let inertia: Double
        switch newShape {
        case .circle(let r):
            mass = density * .pi * r * r
            inertia = 0.5 * mass * r * r
        case .polygon(let verts):
            let (area, i) = Self.polygonAreaAndInertia(verts, density: density)
            mass = density * area
            inertia = i
        }
        inverseMass = mass > 0 ? 1 / mass : 0
        inverseInertia = inertia > 0 ? 1 / inertia : 0
        updateTransform()
    }

    /// Inverse mass to use in physics resolution. Static or sleeping bodies act as
    /// infinite mass (returns 0) regardless of the stored `inverseMass`.
    var effectiveInverseMass: Double { (isStatic || isSleeping) ? 0 : inverseMass }
    var effectiveInverseInertia: Double { (isStatic || isSleeping) ? 0 : inverseInertia }

    func updateTransform() {
        switch shape {
        case .circle(let r):
            worldVertices = []
            aabb = AABB(min: Vec2(x: position.x - r, y: position.y - r),
                        max: Vec2(x: position.x + r, y: position.y + r))
        case .polygon(let local):
            let cosA = cos(angle), sinA = sin(angle)
            var minP = Vec2(x: .infinity, y: .infinity)
            var maxP = Vec2(x: -.infinity, y: -.infinity)
            worldVertices = local.map { v in
                let rotated = Vec2(x: cosA * v.x - sinA * v.y, y: sinA * v.x + cosA * v.y)
                let world = Vec2(x: rotated.x + position.x, y: rotated.y + position.y)
                if world.x < minP.x { minP.x = world.x }
                if world.y < minP.y { minP.y = world.y }
                if world.x > maxP.x { maxP.x = world.x }
                if world.y > maxP.y { maxP.y = world.y }
                return world
            }
            aabb = AABB(min: minP, max: maxP)
        }
    }

    /// Apply impulse at a world-space point.
    func applyImpulse(_ impulse: Vec2, at point: Vec2) {
        guard !isStatic, !isSleeping, inverseMass > 0 else { return }
        velocity += inverseMass * impulse
        let r = point - position
        angularVelocity += inverseInertia * r.cross(impulse)
    }

    /// Linear velocity of a world-space point on this body, including rotation.
    func pointVelocity(at point: Vec2) -> Vec2 {
        let r = point - position
        return velocity + angularVelocity * r.perp()
    }

    /// Returns (area, moment of inertia about centroid). Assumes vertices already centered.
    private static func polygonAreaAndInertia(_ verts: [Vec2], density: Double) -> (area: Double, inertia: Double) {
        // Shoelace + standard polygon moment of inertia formula.
        var area: Double = 0
        var inertia: Double = 0
        let n = verts.count
        for i in 0..<n {
            let v1 = verts[i]
            let v2 = verts[(i + 1) % n]
            let cross = v1.cross(v2)
            area += cross
            inertia += cross * (v1.dot(v1) + v1.dot(v2) + v2.dot(v2))
        }
        area = abs(area) * 0.5
        inertia = density * abs(inertia) / 12
        return (area, inertia)
    }
}

// MARK: - Contact

struct Contact {
    let bodyA: PhysicsBody
    let bodyB: PhysicsBody
    /// Unit normal pointing from A to B.
    let normal: Vec2
    let penetration: Double
    /// Contact point in world space.
    let point: Vec2
}

// MARK: - Collision detection

func detectContact(_ a: PhysicsBody, _ b: PhysicsBody) -> Contact? {
    guard a.aabb.intersects(b.aabb) else { return nil }
    switch (a.shape, b.shape) {
    case (.circle(let ra), .circle(let rb)):
        return circleCircle(a, ra, b, rb)
    case (.circle(let r), .polygon):
        return circlePolygon(circle: a, radius: r, polygon: b, swap: false)
    case (.polygon, .circle(let r)):
        return circlePolygon(circle: b, radius: r, polygon: a, swap: true)
    case (.polygon, .polygon):
        return polygonPolygon(a, b)
    }
}

private func circleCircle(_ a: PhysicsBody, _ ra: Double, _ b: PhysicsBody, _ rb: Double) -> Contact? {
    let delta = b.position - a.position
    let distSq = delta.lengthSquared
    let sumR = ra + rb
    guard distSq < sumR * sumR else { return nil }
    let dist = sqrt(distSq)
    let normal = dist > 1e-9 ? delta / dist : Vec2(x: 1, y: 0)
    let penetration = sumR - dist
    let point = a.position + ra * normal
    return Contact(bodyA: a, bodyB: b, normal: normal, penetration: penetration, point: point)
}

private func projectPolygon(_ verts: [Vec2], onto axis: Vec2) -> (minVal: Double, maxVal: Double) {
    var minVal = verts[0].dot(axis)
    var maxVal = minVal
    for i in 1..<verts.count {
        let d = verts[i].dot(axis)
        if d < minVal { minVal = d }
        if d > maxVal { maxVal = d }
    }
    return (minVal, maxVal)
}

private func polygonPolygon(_ a: PhysicsBody, _ b: PhysicsBody) -> Contact? {
    var minOverlap = Double.infinity
    var bestAxis = Vec2(x: 1, y: 0)

    func testAxes(_ verts: [Vec2]) -> Bool {
        let n = verts.count
        for i in 0..<n {
            let v1 = verts[i]
            let v2 = verts[(i + 1) % n]
            let edge = v2 - v1
            let axis = edge.perp().normalized()
            if axis == .zero { continue }
            let (minA, maxA) = projectPolygon(a.worldVertices, onto: axis)
            let (minB, maxB) = projectPolygon(b.worldVertices, onto: axis)
            if maxA < minB || maxB < minA { return false }
            let overlap = Swift.min(maxA, maxB) - Swift.max(minA, minB)
            if overlap < minOverlap {
                minOverlap = overlap
                bestAxis = axis
            }
        }
        return true
    }

    guard testAxes(a.worldVertices), testAxes(b.worldVertices) else { return nil }

    // Make normal point from A to B.
    let delta = b.position - a.position
    if bestAxis.dot(delta) < 0 { bestAxis = -bestAxis }

    // Contact point: deepest vertex of B in -normal direction (i.e. into A).
    var deepest = b.worldVertices[0]
    var maxDot = deepest.dot(-bestAxis)
    for v in b.worldVertices.dropFirst() {
        let d = v.dot(-bestAxis)
        if d > maxDot { maxDot = d; deepest = v }
    }

    return Contact(bodyA: a, bodyB: b, normal: bestAxis, penetration: minOverlap, point: deepest)
}

private func circlePolygon(circle: PhysicsBody, radius: Double, polygon: PhysicsBody, swap: Bool) -> Contact? {
    let center = circle.position
    var minDistSq = Double.infinity
    var closestPoint = polygon.worldVertices[0]
    let n = polygon.worldVertices.count
    for i in 0..<n {
        let v1 = polygon.worldVertices[i]
        let v2 = polygon.worldVertices[(i + 1) % n]
        let edge = v2 - v1
        let toCenter = center - v1
        let t = max(0.0, min(1.0, toCenter.dot(edge) / edge.lengthSquared))
        let p = v1 + t * edge
        let distSq = (p - center).lengthSquared
        if distSq < minDistSq {
            minDistSq = distSq
            closestPoint = p
        }
    }

    let isInside = pointInPolygon(center, polygon.worldVertices)
    let dist = sqrt(minDistSq)

    guard isInside || dist < radius else { return nil }

    let outwardNormal: Vec2
    let penetration: Double
    if isInside {
        // Center inside polygon — push outward through closest edge point.
        let dir = center - closestPoint
        outwardNormal = dir.length > 1e-9 ? dir.normalized() : Vec2(x: 1, y: 0)
        penetration = radius + dist
    } else {
        let dir = closestPoint - center
        outwardNormal = dir.length > 1e-9 ? dir.normalized() : Vec2(x: 1, y: 0)
        penetration = radius - dist
    }

    // outwardNormal points from circle center outward (toward polygon).
    // We want the contact normal to point from A to B.
    if swap {
        // A is polygon, B is circle. Normal from polygon to circle = -outwardNormal.
        return Contact(bodyA: polygon, bodyB: circle,
                       normal: -outwardNormal, penetration: penetration, point: closestPoint)
    } else {
        // A is circle, B is polygon. Normal from circle to polygon = outwardNormal.
        return Contact(bodyA: circle, bodyB: polygon,
                       normal: outwardNormal, penetration: penetration, point: closestPoint)
    }
}

private func pointInPolygon(_ p: Vec2, _ verts: [Vec2]) -> Bool {
    var inside = false
    let n = verts.count
    var j = n - 1
    for i in 0..<n {
        let vi = verts[i]
        let vj = verts[j]
        if (vi.y > p.y) != (vj.y > p.y) {
            let denom = vj.y - vi.y
            if abs(denom) > 1e-12 {
                let intersectX = vi.x + (p.y - vi.y) * (vj.x - vi.x) / denom
                if p.x < intersectX {
                    inside.toggle()
                }
            }
        }
        j = i
    }
    return inside
}

// MARK: - Contact resolution

private func resolveContact(_ c: Contact) {
    let a = c.bodyA, b = c.bodyB
    let n = c.normal

    let ra = c.point - a.position
    let rb = c.point - b.position

    let vAtA = a.pointVelocity(at: c.point)
    let vAtB = b.pointVelocity(at: c.point)
    let relVel = vAtB - vAtA
    let velAlongNormal = relVel.dot(n)
    if velAlongNormal > 0 { return }

    let e = Swift.min(a.restitution, b.restitution)
    let raCrossN = ra.cross(n)
    let rbCrossN = rb.cross(n)
    let invMassA = a.effectiveInverseMass
    let invMassB = b.effectiveInverseMass
    let invInertiaA = a.effectiveInverseInertia
    let invInertiaB = b.effectiveInverseInertia
    let denomNormal = invMassA + invMassB
        + raCrossN * raCrossN * invInertiaA
        + rbCrossN * rbCrossN * invInertiaB
    guard denomNormal > 0 else { return }

    let j = -(1 + e) * velAlongNormal / denomNormal
    let impulse = j * n
    a.applyImpulse(-impulse, at: c.point)
    b.applyImpulse(impulse, at: c.point)

    // Friction (Coulomb)
    let vAtA2 = a.pointVelocity(at: c.point)
    let vAtB2 = b.pointVelocity(at: c.point)
    let relVel2 = vAtB2 - vAtA2
    var tangent = relVel2 - relVel2.dot(n) * n
    let tangentLen = tangent.length
    if tangentLen > 1e-6 {
        tangent = tangent / tangentLen
        let raCrossT = ra.cross(tangent)
        let rbCrossT = rb.cross(tangent)
        let denomTangent = invMassA + invMassB
            + raCrossT * raCrossT * invInertiaA
            + rbCrossT * rbCrossT * invInertiaB
        guard denomTangent > 0 else { return }
        let jt = -relVel2.dot(tangent) / denomTangent
        let muKinetic = sqrt(a.friction * b.friction)
        let muStatic = muKinetic * 1.5  // matches demo's frictionStatic = 1.5
        let frictionImpulse: Vec2
        if abs(jt) <= j * muStatic {
            // Within static friction cone — no slipping.
            frictionImpulse = jt * tangent
        } else {
            // Slipping — apply kinetic friction.
            frictionImpulse = -j * muKinetic * tangent
        }
        a.applyImpulse(-frictionImpulse, at: c.point)
        b.applyImpulse(frictionImpulse, at: c.point)
    }
}

private func correctPosition(_ c: Contact) {
    let percent = 0.2  // less aggressive — high values amplify solver noise in dense stacks
    let slop = 0.05    // larger tolerance — tiny overlaps don't trigger corrections
    let invMassA = c.bodyA.effectiveInverseMass
    let invMassB = c.bodyB.effectiveInverseMass
    let invMassSum = invMassA + invMassB
    guard invMassSum > 0 else { return }
    let mag = Swift.max(c.penetration - slop, 0) / invMassSum * percent
    let correction = mag * c.normal
    c.bodyA.position -= invMassA * correction
    c.bodyB.position += invMassB * correction
}

// MARK: - World

final class PhysicsWorld {
    private(set) var bodies: [PhysicsBody] = []
    var gravity = Vec2(x: 0, y: -980)
    var velocityIterations = 8   // matches demo (Matter.js engine.velocityIterations)
    var positionIterations = 10  // matches demo (Matter.js engine.positionIterations)

    func add(_ body: PhysicsBody) {
        bodies.append(body)
    }

    func remove(_ body: PhysicsBody) {
        bodies.removeAll { $0 === body }
    }

    // Matter.js applies frictionAir each tick: velocity *= 1 - frictionAir (default 0.01).
    // We mirror that here for both linear and angular components.
    var linearDamping: Double = 0.01
    var angularDamping: Double = 0.01

    /// Sleep thresholds. A body whose velocity stays below these for `sleepTime`
    /// seconds is put to sleep — it skips integration and contact resolution.
    var sleepLinearThreshold: Double = 8.0
    var sleepAngularThreshold: Double = 0.25
    var sleepTime: Double = 0.5

    func step(dt: Double) {
        // Apply damping then gravity, then integrate awake dynamic bodies.
        let linDecay = max(0, 1 - linearDamping * dt * 60)
        let angDecay = max(0, 1 - angularDamping * dt * 60)
        for body in bodies where body.inverseMass > 0 && !body.isStatic && !body.isSleeping {
            body.velocity = linDecay * body.velocity
            body.angularVelocity *= angDecay
            body.velocity += dt * gravity
            body.position += dt * body.velocity
            body.angle += dt * body.angularVelocity
            body.updateTransform()
        }
        // Refresh transforms for kinematic / sleeping bodies (their positions may
        // have been adjusted externally, e.g. during the grow phase).
        for body in bodies where body.isStatic || body.isSleeping {
            body.updateTransform()
        }

        // Detect contacts once per step.
        var contacts: [Contact] = []
        let n = bodies.count
        for i in 0..<n {
            for j in (i + 1)..<n {
                if let c = detectContact(bodies[i], bodies[j]) {
                    contacts.append(c)
                    // Wake either body if the other is moving — keeps stacks
                    // responsive when something new lands on top.
                    let a = bodies[i], b = bodies[j]
                    if a.isSleeping && !b.isStatic && !b.isSleeping { a.wake() }
                    if b.isSleeping && !a.isStatic && !a.isSleeping { b.wake() }
                }
            }
        }

        // Velocity (impulse) iterations. Sleeping bodies act as immovable (their
        // effectiveInverseMass already returns 0 indirectly via isStatic-like
        // treatment? No — we still apply impulses to them. To make sleep truly
        // skip them in resolution, treat sleeping as static for resolution.)
        for _ in 0..<velocityIterations {
            for c in contacts {
                resolveContact(c)
            }
        }

        // Position correction iterations.
        for _ in 0..<positionIterations {
            for c in contacts {
                correctPosition(c)
            }
            for body in bodies where !body.isStatic && body.inverseMass > 0 && !body.isSleeping {
                body.updateTransform()
            }
        }

        // Update sleep state. A body whose velocity has been small enough for
        // sleepTime seconds transitions to sleeping.
        for body in bodies where !body.isStatic && body.inverseMass > 0 && !body.isSleeping {
            let vMag = body.velocity.length
            let wMag = abs(body.angularVelocity)
            if vMag < sleepLinearThreshold && wMag < sleepAngularThreshold {
                body.sleepTimer += dt
                if body.sleepTimer >= sleepTime {
                    body.isSleeping = true
                    body.velocity = .zero
                    body.angularVelocity = 0
                }
            } else {
                body.sleepTimer = 0
            }
        }
    }
}
