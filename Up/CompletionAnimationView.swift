import SwiftUI
import SpriteKit

struct CompletionAnimationView: View {
    @StateObject private var holder = SceneHolder()

    var body: some View {
        SpriteView(scene: holder.scene,
                   options: [.allowsTransparency])
            .frame(width: StackingScene.boxWidth, height: holder.boxHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: holder.boxHeight)
    }
}

@MainActor
private final class SceneHolder: ObservableObject {
    let scene: StackingScene
    @Published var boxHeight: CGFloat = StackingScene.minBoxHeight

    init() {
        let scene = StackingScene()
        self.scene = scene
        scene.onHeightChange = { [weak self] height in
            self?.boxHeight = height
        }
    }
}
