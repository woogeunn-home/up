import AppKit
import SpriteKit

final class StackingScene: SKScene {
    static let boxWidth: CGFloat = 248
    static let minBoxHeight: CGFloat = 80
    static let topPadding: CGFloat = 16
    static let maxShapes = 50
    static let spawnInterval: TimeInterval = 1.6
    static let growDuration: TimeInterval = 0.5
    private static let wallHeight: CGFloat = 2000
    private static let spawnActionKey = "spawn"

    var onHeightChange: ((CGFloat) -> Void)?

    private var shapeCount = 0
    private var dynamicShapes: [SKShapeNode] = []
    private var currentBoxHeight: CGFloat = StackingScene.minBoxHeight

    override init() {
        super.init(size: CGSize(width: Self.boxWidth, height: Self.minBoxHeight))
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = CGPoint(x: 0, y: 0)
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        setupWalls()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: - Walls

    private func setupWalls() {
        addWall(from: CGPoint(x: 0, y: 0), to: CGPoint(x: Self.boxWidth, y: 0))                    // floor
        addWall(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: Self.wallHeight))                  // left
        addWall(from: CGPoint(x: Self.boxWidth, y: 0), to: CGPoint(x: Self.boxWidth, y: Self.wallHeight)) // right
    }

    private func addWall(from p1: CGPoint, to p2: CGPoint) {
        let node = SKNode()
        let body = SKPhysicsBody(edgeFrom: p1, to: p2)
        body.friction = 0.9
        node.physicsBody = body
        addChild(node)
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        spawnShape()
        let wait = SKAction.wait(forDuration: Self.spawnInterval)
        let spawn = SKAction.run { [weak self] in self?.spawnShape() }
        run(.repeatForever(.sequence([wait, spawn])), withKey: Self.spawnActionKey)
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        removeAction(forKey: Self.spawnActionKey)
        isPaused = true
    }

    // MARK: - Spawning

    private func spawnShape() {
        guard shapeCount < Self.maxShapes else {
            removeAction(forKey: Self.spawnActionKey)
            return
        }

        guard let definition = ShapePalette.shapeDefinitions.randomElement(),
              let color = ShapePalette.colors.randomElement() else { return }

        let margin = definition.visualWidth / 2 + 12
        let maxJitter = max(0, Self.boxWidth / 2 - margin)
        let jitter = maxJitter > 0 ? CGFloat.random(in: -maxJitter...maxJitter) : 0
        let x = Self.boxWidth / 2 + jitter

        let node = makeShapeNode(definition: definition, color: color)
        let initialScale: CGFloat = 0.05
        node.setScale(initialScale)
        node.position = CGPoint(x: x, y: definition.originalHeight * initialScale / 2)
        node.zRotation = CGFloat.random(in: -0.15...0.15)

        let body = makePhysicsBody(definition: definition)
        body.restitution = 0.05
        body.friction = 0.9
        body.density = 0.002
        body.isDynamic = false
        node.physicsBody = body

        addChild(node)
        dynamicShapes.append(node)
        shapeCount += 1

        let grow = SKAction.scale(to: 1.0, duration: Self.growDuration)
        grow.timingFunction = { t in 1 - powf(1 - t, 2.5) }
        let activate = SKAction.run { node.physicsBody?.isDynamic = true }
        node.run(.sequence([grow, activate]))

        NSSound(named: "Tink")?.play()
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

    private func makeIconNode(definition: ShapeDefinition, iconColor: NSColor) -> SKShapeNode {
        let iconHeight = definition.originalHeight * 0.45
        let iconScale = iconHeight / UpArrowPath.viewBoxHeight
        var transform = CGAffineTransform(scaleX: iconScale, y: iconScale)
            .concatenating(CGAffineTransform(translationX: -UpArrowPath.viewBoxWidth * iconScale / 2,
                                             y: -UpArrowPath.viewBoxHeight * iconScale / 2))
        guard let scaledPath = UpArrowPath.path.copy(using: &transform) else {
            return SKShapeNode()
        }
        let iconNode = SKShapeNode(path: scaledPath)
        iconNode.fillColor = iconColor
        iconNode.strokeColor = .clear
        iconNode.lineWidth = 0
        return iconNode
    }

    private func makePhysicsBody(definition: ShapeDefinition) -> SKPhysicsBody {
        switch definition.kind {
        case .circle(let radius):
            return SKPhysicsBody(circleOfRadius: radius)
        case .rect(let side):
            return SKPhysicsBody(rectangleOf: CGSize(width: side, height: side))
        case .rounded(let side, _):
            return SKPhysicsBody(rectangleOf: CGSize(width: side, height: side))
        case .polygon(let sides, let circumradius):
            return SKPhysicsBody(polygonFrom: Self.polygonPath(sides: sides, radius: circumradius))
        }
    }

    private static func polygonPath(sides: Int, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<sides {
            let angle = CGFloat(i) / CGFloat(sides) * 2 * .pi - .pi / 2
            let point = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Box height

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)

        let towerTopY = dynamicShapes
            .map { $0.calculateAccumulatedFrame().maxY }
            .max() ?? 0

        let target = max(Self.minBoxHeight, towerTopY + Self.topPadding)
        currentBoxHeight += (target - currentBoxHeight) * 0.15
        size = CGSize(width: Self.boxWidth, height: currentBoxHeight)
        onHeightChange?(currentBoxHeight)
    }
}
