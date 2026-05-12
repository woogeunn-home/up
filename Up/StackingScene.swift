import AppKit
import SpriteKit

/// Scene that renders the stacking animation. Physics is driven by Matter.js
/// running inside a JSContext (`MatterJSWorld`). SKShapeNodes are pure visuals
/// that we drive each frame from the JS-side body states.
@MainActor
final class StackingScene: SKScene {
    static let boxWidth: CGFloat = 280  // matches popover content width — animation spans full width
    static let minBoxHeight: CGFloat = 80
    static let topPadding: CGFloat = 16
    static let maxShapes = 50
    static let spawnInterval: TimeInterval = 1.6

    var onHeightChange: ((CGFloat) -> Void)?

    private let world = MatterJSWorld()
    /// Visual nodes keyed by their JS-side body id.
    private var visuals: [Int: SKShapeNode] = [:]
    private var lastUpdateTime: TimeInterval = 0
    private var nextSpawnTime: TimeInterval = 0

    override init() {
        super.init(size: CGSize(width: Self.boxWidth, height: Self.minBoxHeight))
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = CGPoint(x: 0, y: 0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        lastUpdateTime = 0
        nextSpawnTime = 0
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        isPaused = true
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        guard let skView = self.view else { return }
        let windowPoint = event.locationInWindow
        let viewPoint = skView.convert(windowPoint, from: nil)
        let scenePoint = convertPoint(fromView: viewPoint)

        // Walk up each hit node's parent chain to find the shape node that
        // carries our bodyId tag.
        for hit in nodes(at: scenePoint) {
            var candidate: SKNode? = hit
            while let n = candidate {
                if let id = n.userData?["bodyId"] as? Int {
                    pop(id: id, node: n)
                    return
                }
                candidate = n.parent
            }
        }
    }

    private func pop(id: Int, node: SKNode) {
        // Remove from the physics simulation immediately so it stops interacting
        // and the next spawn cycle can refill the slot. The visual stays a
        // little longer to play the pop animation.
        world.remove(id: id)
        visuals.removeValue(forKey: id)

        let scaleDown = SKAction.scale(to: 0.0, duration: 0.18)
        scaleDown.timingMode = .easeIn
        let fadeOut = SKAction.fadeOut(withDuration: 0.18)
        let pop = SKAction.group([scaleDown, fadeOut])
        node.run(.sequence([pop, .removeFromParent()]))

        NSSound(named: "Pop")?.play()
    }

    // MARK: - Spawning

    private func spawnIfDue(currentTime: TimeInterval) {
        guard currentTime >= nextSpawnTime else { return }
        nextSpawnTime = currentTime + Self.spawnInterval

        // The JS side refuses spawns when its on-screen count already equals
        // maxShapes, so we just call and let it decide. A pop creates a slot
        // that the next tick automatically refills.
        let id = world.spawn()
        guard id > 0 else { return }
        NSSound(named: "Tink")?.play()
        // The visual node is created lazily on the first snapshot that includes
        // this id — we don't know its kind/palette without that info.
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            nextSpawnTime = currentTime  // spawn immediately on first frame
        }
        let rawDt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        let dt = min(rawDt, 1.0 / 30.0)

        spawnIfDue(currentTime: currentTime)
        world.step(dt: dt)

        // Sync visuals from JS snapshot.
        let states = world.snapshot()
        var seenIds = Set<Int>()
        for state in states {
            seenIds.insert(state.id)
            let node = visuals[state.id] ?? makeNode(for: state)
            visuals[state.id] = node
            node.setScale(CGFloat(state.scale))
            node.position = CGPoint(x: state.x, y: state.y)
            node.zRotation = CGFloat(state.angle)
            if node.parent == nil { addChild(node) }
        }
        // Remove visuals for bodies that disappeared (shouldn't happen in this
        // scene, but guards against leaks).
        for (id, node) in visuals where !seenIds.contains(id) {
            node.removeFromParent()
            visuals.removeValue(forKey: id)
        }

        let newHeight = CGFloat(world.updateBoxHeight())
        onHeightChange?(newHeight)
    }

    // MARK: - Visual node construction

    private func makeNode(for state: MatterJSWorld.BodyState) -> SKShapeNode {
        let definition = shapeDefinition(for: state.kind)
        let color = ShapePalette.colors[state.palette % ShapePalette.colors.count]
        let node = makeShapeNode(definition: definition, color: color)
        node.userData = NSMutableDictionary()
        node.userData?["bodyId"] = state.id
        return node
    }

    private func shapeDefinition(for kind: String) -> ShapeDefinition {
        // Map JS-side kind strings to our ShapeDefinition for rendering.
        // Sizes mirror the JS SHAPE_TYPES exactly so visuals match physics bodies.
        switch kind {
        case "circle":
            return ShapeDefinition(kind: .circle(radius: 30), originalHeight: 60, visualWidth: 60)
        case "rect":
            return ShapeDefinition(kind: .rect(side: 54), originalHeight: 54, visualWidth: 54)
        case "rounded":
            return ShapeDefinition(kind: .rounded(side: 54, cornerRadius: 12), originalHeight: 54, visualWidth: 54)
        case "triangle":
            return ShapeDefinition(kind: .polygon(sides: 3, circumradius: 39), originalHeight: 78, visualWidth: 78)
        case "pentagon":
            return ShapeDefinition(kind: .polygon(sides: 5, circumradius: 33), originalHeight: 66, visualWidth: 66)
        case "hexagon":
            return ShapeDefinition(kind: .polygon(sides: 6, circumradius: 33), originalHeight: 66, visualWidth: 66)
        default:
            return ShapeDefinition(kind: .circle(radius: 30), originalHeight: 60, visualWidth: 60)
        }
    }

    private func makeShapeNode(definition: ShapeDefinition, color: ShapeColor) -> SKShapeNode {
        let shapeNode: SKShapeNode
        switch definition.kind {
        case .circle(let radius):
            shapeNode = SKShapeNode(circleOfRadius: radius)
        case .rect(let side):
            shapeNode = SKShapeNode(rectOf: CGSize(width: side, height: side))
        case .rounded(let side, let cornerRadius):
            shapeNode = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: cornerRadius)
        case .polygon(let sides, let circumradius):
            shapeNode = SKShapeNode(path: Self.polygonPath(sides: sides, radius: circumradius))
        }
        shapeNode.fillColor = color.fill
        shapeNode.strokeColor = .clear
        shapeNode.lineWidth = 0
        shapeNode.addChild(makeIconNode(definition: definition, iconColor: color.icon))
        return shapeNode
    }

    private func makeIconNode(definition: ShapeDefinition, iconColor: NSColor) -> SKNode {
        let container = SKNode()
        // Fixed icon size across all shapes so the arrow looks visually uniform
        // regardless of which shape it sits inside.
        let iconHeight: CGFloat = 22
        let iconScale = iconHeight / UpArrowPath.viewBoxHeight
        var transform = CGAffineTransform(scaleX: iconScale, y: iconScale)
            .concatenating(CGAffineTransform(translationX: -UpArrowPath.viewBoxWidth * iconScale / 2,
                                             y: -UpArrowPath.viewBoxHeight * iconScale / 2))
        for subpath in [UpArrowPath.chevronPath, UpArrowPath.stemPath] {
            guard let scaled = subpath.copy(using: &transform) else { continue }
            let node = SKShapeNode(path: scaled)
            node.fillColor = iconColor
            node.strokeColor = .clear
            node.lineWidth = 0
            container.addChild(node)
        }
        return container
    }

    private static func polygonPath(sides: Int, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<sides {
            let angle = CGFloat(i) / CGFloat(sides) * 2 * .pi - .pi / 2
            let point = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
