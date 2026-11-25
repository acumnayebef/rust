import QuartzCore
import SwiftUI
import UIKit

struct GameViewportView: View {
    @EnvironmentObject private var viewModel: LauncherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showMiniConsole = true

    var body: some View {
        ZStack {
            MetalSurfaceView(
                onLayerReady: { layer in
                    viewModel.startEngine(metalLayer: layer)
                },
                onResize: { width, height, scale in
                    viewModel.resizeViewport(width: width, height: height, scale: scale)
                },
                onTouch: { action, x, y, dx, dy in
                    viewModel.sendTouchInput(action: action, x: x, y: y, dx: dx, dy: dy)
                }
            )
            .ignoresSafeArea()

            VStack {
                topHUDBar
                if showMiniConsole {
                    miniConsoleOverlay
                }
                Spacer()
                bottomTouchControls
            }
            .padding()
        }
        .statusBarHidden(true)
    }

    private var topHUDBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.engineState == .running ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.activeInstance?.name ?? "Rust Client")
                    .font(.caption.bold())
                Text("• \(viewModel.engineState.displayTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button {
                withAnimation {
                    showMiniConsole.toggle()
                }
            } label: {
                Image(systemName: "terminal")
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Button {
                viewModel.stopEngine()
                dismiss()
            } label: {
                Label("Выход", systemImage: "xmark.circle.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }

    private var miniConsoleOverlay: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(viewModel.logs.suffix(25)) { entry in
                    Text("[\(entry.level.label)] \(entry.message)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(entry.level == .error ? .red : .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 170)
        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
    }

    private var bottomTouchControls: some View {
        let scale = CGFloat(viewModel.graphicsSettings.touchHUDScale)

        return HStack(alignment: .bottom) {
            VStack(spacing: 6) {
                hudButton(systemImage: "arrow.up", actionCode: 3, x: 0, y: 1)
                HStack(spacing: 6) {
                    hudButton(systemImage: "arrow.left", actionCode: 3, x: -1, y: 0)
                    hudButton(systemImage: "arrow.down", actionCode: 3, x: 0, y: -1)
                    hudButton(systemImage: "arrow.right", actionCode: 3, x: 1, y: 0)
                }
            }
            .scaleEffect(scale, anchor: .bottomLeading)

            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    actionPill("Атака", code: 1, x: 0.8, y: 0.2)
                    actionPill("Использ.", code: 1, x: 0.9, y: 0.2)
                }
                HStack(spacing: 10) {
                    actionPill("Присед", code: 1, x: 0.8, y: 0.8)
                    actionPill("Прыжок", code: 1, x: 0.9, y: 0.8)
                }
            }
            .scaleEffect(scale, anchor: .bottomTrailing)
        }
    }

    private func hudButton(systemImage: String, actionCode: Int32, x: Float, y: Float) -> some View {
        Button {
            viewModel.sendTouchInput(action: actionCode, x: x, y: y)
        } label: {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(.white)
    }

    private func actionPill(_ title: String, code: Int32, x: Float, y: Float) -> some View {
        Button {
            viewModel.sendTouchInput(action: code, x: x, y: y)
        } label: {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.white)
    }
}

struct MetalSurfaceView: UIViewRepresentable {
    let onLayerReady: (CAMetalLayer) -> Void
    let onResize: (UInt32, UInt32, Float) -> Void
    let onTouch: (Int32, Float, Float, Float, Float) -> Void

    func makeUIView(context: Context) -> MetalLayerHostView {
        let view = MetalLayerHostView()
        view.onLayerReady = onLayerReady
        view.onResize = onResize
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ uiView: MetalLayerHostView, context: Context) {
        uiView.onLayerReady = onLayerReady
        uiView.onResize = onResize
        uiView.onTouch = onTouch
    }
}

final class MetalLayerHostView: UIView {
    override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    var onLayerReady: ((CAMetalLayer) -> Void)?
    var onResize: ((UInt32, UInt32, Float) -> Void)?
    var onTouch: ((Int32, Float, Float, Float, Float) -> Void)?

    private var didNotifyReady = false
    private var lastDrawableSize: CGSize = .zero
    private var lastTouchPoint: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.11, alpha: 1.0)
        isMultipleTouchEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureAndNotifyLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        configureAndNotifyLayer()
    }

    private func configureAndNotifyLayer() {
        guard window != nil, bounds.width > 0, bounds.height > 0 else { return }

        let scale = window?.windowScene?.screen.scale ?? max(traitCollection.displayScale, 1.0)
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = scale

        let drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        metalLayer.drawableSize = drawableSize

        if !didNotifyReady {
            didNotifyReady = true
            onLayerReady?(metalLayer)
        }

        if drawableSize != lastDrawableSize {
            lastDrawableSize = drawableSize
            onResize?(UInt32(drawableSize.width), UInt32(drawableSize.height), Float(scale))
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let pt = touch.location(in: self)
        lastTouchPoint = pt
        let norm = normalized(pt)
        onTouch?(1, norm.x, norm.y, 0, 0)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let pt = touch.location(in: self)
        let prev = lastTouchPoint ?? pt
        lastTouchPoint = pt
        let norm = normalized(pt)
        let dx = Float(pt.x - prev.x)
        let dy = Float(pt.y - prev.y)
        onTouch?(0, norm.x, norm.y, dx, dy)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let pt = touch.location(in: self)
        lastTouchPoint = nil
        let norm = normalized(pt)
        onTouch?(2, norm.x, norm.y, 0, 0)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouchPoint = nil
        onTouch?(2, 0, 0, 0, 0)
    }

    private func normalized(_ point: CGPoint) -> (x: Float, y: Float) {
        let w = max(bounds.width, 1)
        let h = max(bounds.height, 1)
        return (Float(point.x / w), Float(point.y / h))
    }
}
