import CoreGraphics
import Foundation
import SwiftUI

enum EternalPalette {
    static let bgTop = Color(red: 0.09, green: 0.04, blue: 0.07)
    static let bgMid = Color(red: 0.16, green: 0.07, blue: 0.11)
    static let bgBottom = Color(red: 0.11, green: 0.05, blue: 0.08)

    static let panelFill = Color(red: 0.14, green: 0.08, blue: 0.11).opacity(0.84)
    static let panelSolid = Color(red: 0.13, green: 0.07, blue: 0.10)
    static let cardFill = Color(red: 0.17, green: 0.09, blue: 0.13).opacity(0.78)
    static let cardStroke = Color.white.opacity(0.09)

    static let rose = Color(red: 0.87, green: 0.56, blue: 0.62)
    static let roseSoft = Color(red: 0.87, green: 0.56, blue: 0.62).opacity(0.18)
    static let roseInk = Color(red: 0.16, green: 0.06, blue: 0.09)
    static let gold = Color(red: 0.96, green: 0.71, blue: 0.24)
    static let textPrimary = Color(red: 0.96, green: 0.93, blue: 0.94)
    static let textSecondary = Color(red: 0.72, green: 0.63, blue: 0.67)
    static let textMuted = Color(red: 0.54, green: 0.45, blue: 0.49)
}

struct EternalWindowBackground: View {
    var body: some View {
        LinearGradient(
            colors: [EternalPalette.bgMid, EternalPalette.bgTop, EternalPalette.bgBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct StarryHorizonBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.05, blue: 0.10),
                        Color(red: 0.16, green: 0.10, blue: 0.18),
                        Color(red: 0.34, green: 0.17, blue: 0.25),
                        Color(red: 0.12, green: 0.06, blue: 0.09)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Pixel stars
                Canvas { context, size in
                    let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
                        (0.08, 0.12, 2, 0.8), (0.15, 0.22, 3, 0.55), (0.23, 0.09, 2, 0.7),
                        (0.31, 0.18, 2, 0.45), (0.39, 0.07, 3, 0.85), (0.46, 0.24, 2, 0.5),
                        (0.55, 0.11, 2, 0.75), (0.62, 0.19, 3, 0.6), (0.76, 0.08, 2, 0.7),
                        (0.84, 0.16, 2, 0.65), (0.91, 0.25, 3, 0.55), (0.12, 0.34, 2, 0.45),
                        (0.28, 0.31, 2, 0.5), (0.64, 0.30, 2, 0.65), (0.87, 0.38, 2, 0.4)
                    ]
                    for (nx, ny, sz, alpha) in stars {
                        let rect = CGRect(x: size.width * nx, y: size.height * ny, width: sz, height: sz)
                        context.fill(Path(rect), with: .color(.white.opacity(alpha)))
                    }
                }

                // Pixel moon
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.94, blue: 0.76).opacity(0.18))
                        .frame(width: 78, height: 78)
                        .blur(radius: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 1.0, green: 0.95, blue: 0.80))
                        .frame(width: 28, height: 28)
                }
                .position(x: w * 0.69, y: h * 0.21)

                // Stepped voxel hills silhouette
                Canvas { context, size in
                    let step = max(12.0, size.width / 46.0)
                    let cols = Int(Foundation.ceil(Double(size.width / step))) + 1

                    func drawLayer(baseY: CGFloat, amp: CGFloat, freq: CGFloat, phase: CGFloat, color: Color) {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height))
                        for i in 0..<cols {
                            let x = CGFloat(i) * step
                            let angle = Double(CGFloat(i) * freq + phase)
                            let rawY = baseY + CGFloat(Foundation.sin(angle)) * amp
                            let snappedY = (rawY / step).rounded() * step
                            path.addLine(to: CGPoint(x: x, y: snappedY))
                            path.addLine(to: CGPoint(x: x + step, y: snappedY))
                        }
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.closeSubpath()
                        context.fill(path, with: .color(color))
                    }

                    drawLayer(
                        baseY: size.height * 0.62,
                        amp: 26,
                        freq: 0.24,
                        phase: 0.5,
                        color: Color(red: 0.36, green: 0.20, blue: 0.28).opacity(0.65)
                    )
                    drawLayer(
                        baseY: size.height * 0.69,
                        amp: 20,
                        freq: 0.32,
                        phase: 2.1,
                        color: Color(red: 0.22, green: 0.11, blue: 0.16).opacity(0.85)
                    )
                }

                // Floor stage gradient
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(red: 0.08, green: 0.04, blue: 0.06).opacity(0.88),
                            Color(red: 0.06, green: 0.03, blue: 0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: h * 0.34)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct PixelHeadView: View {
    let skin: SkinPreset
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Rectangle()
                .fill(skin.skinTone)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(skin.hairColor)
                    .frame(height: size * 0.28)
                Spacer()
            }
            HStack(spacing: size * 0.24) {
                HStack(spacing: 0) {
                    Color.white.frame(width: size * 0.12, height: size * 0.12)
                    skin.eyeColor.frame(width: size * 0.12, height: size * 0.12)
                }
                HStack(spacing: 0) {
                    skin.eyeColor.frame(width: size * 0.12, height: size * 0.12)
                    Color.white.frame(width: size * 0.12, height: size * 0.12)
                }
            }
            .offset(y: size * 0.05)

            Rectangle()
                .fill(skin.hairColor.opacity(0.75))
                .frame(width: size * 0.26, height: size * 0.10)
                .offset(y: size * 0.26)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(3, size * 0.14)))
    }
}

struct PixelCharacterView: View {
    let skin: SkinPreset
    let particle: ParticleOption
    var scale: CGFloat = 1.0

    @State private var floatPhase = false

    var body: some View {
        let armWidth: CGFloat = skin.modelKind == .slim ? 20 : 25

        ZStack {
            // Pedestal shadow
            Ellipse()
                .fill(Color.black.opacity(0.65))
                .frame(width: 120 * scale, height: 22 * scale)
                .offset(y: 126 * scale)
                .blur(radius: 4)

            VStack(spacing: 2 * scale) {
                // Head
                PixelHeadView(skin: skin, size: 54 * scale)

                // Torso + Arms
                HStack(alignment: .top, spacing: 2 * scale) {
                    // Left Arm
                    VStack(spacing: 0) {
                        skin.shirtColor.frame(height: 28 * scale)
                        skin.skinTone.frame(height: 52 * scale)
                    }
                    .frame(width: armWidth * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                    // Torso
                    ZStack(alignment: .top) {
                        skin.shirtColor
                        Rectangle()
                            .fill(skin.accentColor)
                            .frame(width: 18 * scale, height: 14 * scale)
                            .offset(y: 4 * scale)
                    }
                    .frame(width: 54 * scale, height: 80 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                    // Right Arm
                    VStack(spacing: 0) {
                        skin.shirtColor.frame(height: 28 * scale)
                        skin.skinTone.frame(height: 52 * scale)
                    }
                    .frame(width: armWidth * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }

                // Legs
                HStack(spacing: 2 * scale) {
                    ZStack(alignment: .bottom) {
                        skin.pantsColor
                        Color.black.opacity(0.28).frame(height: 12 * scale)
                    }
                    .frame(width: 26 * scale, height: 78 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                    ZStack(alignment: .bottom) {
                        skin.pantsColor
                        Color.black.opacity(0.28).frame(height: 12 * scale)
                    }
                    .frame(width: 26 * scale, height: 78 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            .offset(y: floatPhase ? -2 : 2)

            if particle == .hearts {
                ZStack {
                    pixelHeart(size: 16 * scale)
                        .offset(x: -44 * scale, y: (floatPhase ? -24 : -14) * scale)
                    pixelHeart(size: 14 * scale)
                        .offset(x: 22 * scale, y: (floatPhase ? -32 : -22) * scale)
                    pixelHeart(size: 18 * scale)
                        .offset(x: 42 * scale, y: (floatPhase ? 52 : 62) * scale)
                    pixelHeart(size: 13 * scale)
                        .offset(x: -10 * scale, y: (floatPhase ? -12 : -4) * scale)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                floatPhase.toggle()
            }
        }
    }

    private func pixelHeart(size: CGFloat) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.45, blue: 0.65), Color(red: 0.88, green: 0.22, blue: 0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: Color.pink.opacity(0.6), radius: 4)
    }
}

struct EternalGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 14
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(EternalPalette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isSelected ? EternalPalette.rose : EternalPalette.cardStroke,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
    }
}

extension View {
    func eternalCard(cornerRadius: CGFloat = 14, isSelected: Bool = false) -> some View {
        modifier(EternalGlassCardModifier(cornerRadius: cornerRadius, isSelected: isSelected))
    }
}
