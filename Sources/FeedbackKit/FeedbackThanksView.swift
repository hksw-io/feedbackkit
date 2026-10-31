#if os(iOS) || os(macOS)
import SwiftUI

/// What the form gives way to after a send, over everything including its toolbar: the app icon on a drifting
/// backdrop, then the thanks, in the manner of PaywallKit's thank-you screen.
struct FeedbackThanksView: View {
    let icon: Image
    let title: String
    let detail: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pop: CGFloat = 1
    @State private var float: CGFloat = 0
    @State private var pulse: CGFloat = 1
    @State private var titleShown = false
    @State private var detailShown = false
    @State private var sheenPhase: CGFloat = 0

    private static let iconSize: CGFloat = 88

    private var titleFont: Font {
        .title.weight(.bold)
    }

    var body: some View {
        VStack(spacing: 24) {
            self.hero

            VStack(spacing: 8) {
                Text(self.title)
                    .font(self.titleFont)
                    .foregroundStyle(LinearGradient(
                        colors: [.primary, Color.primary.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing))
                    .overlay { self.titleSheen }
                    .opacity(self.titleShown ? 1 : 0)

                Text(self.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .opacity(self.detailShown ? 1 : 0)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .background {
            ZStack {
                Rectangle().fill(Tokens.Colors.background)
                DriftingBackdrop()
            }
            .padding(-200)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(.keyboard)
        .task {
            await self.reveal()
        }
    }

    private var hero: some View {
        self.icon
            .resizable()
            .scaledToFit()
            .frame(width: Self.iconSize, height: Self.iconSize)
            .clipShape(.rect(cornerRadius: Self.iconSize * 0.23, style: .continuous))
            .shadow(
                color: .black.opacity(0.15),
                radius: Self.iconSize * 0.14,
                x: 0,
                y: Self.iconSize * 0.06)
            .scaleEffect(self.pulse)
            .scaleEffect(self.pop)
            .offset(y: self.float)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var titleSheen: some View {
        if !self.reduceMotion {
            GeometryReader { geometry in
                let width = geometry.size.width
                LinearGradient(
                    colors: [.clear, Color.accentColor.opacity(0.55), .clear],
                    startPoint: .leading,
                    endPoint: .trailing)
                    .frame(width: width * 0.45)
                    .offset(x: -width * 0.45 + self.sheenPhase * width * 1.45)
            }
            .mask(Text(self.title).font(self.titleFont))
            .allowsHitTesting(false)
        }
    }

    private func reveal() async {
        var announcement = AttributedString("\(self.title) \(self.detail)")
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()

        guard !self.reduceMotion else {
            self.titleShown = true
            self.detailShown = true
            return
        }

        withAnimation(Tokens.Animations.successPop) {
            self.pop = 1.05
        }
        withAnimation(Tokens.Animations.thanksTitleLand) {
            self.titleShown = true
        }
        withAnimation(Tokens.Animations.thanksDetailLand) {
            self.detailShown = true
        }

        try? await Task.sleep(for: .seconds(0.33))
        withAnimation(Tokens.Animations.thanksIconSettle) {
            self.pop = 1
        }
        withAnimation(Tokens.Animations.thanksBreath.repeatForever(autoreverses: true)) {
            self.float = -4
            self.pulse = 1.015
        }

        try? await Task.sleep(for: .seconds(1.2))
        withAnimation(Tokens.Animations.thanksSheen) {
            self.sheenPhase = 1
        }
    }
}

/// Soft colour moving slowly behind the thanks.
private struct DriftingBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size: CGSize = .zero

    var body: some View {
        ZStack {
            if self.size != .zero {
                let (width, height) = (self.size.width, self.size.height)
                let unit = max(width, height)
                DriftingBlob(
                    color: Color.accentColor.opacity(0.16), diameter: unit * 0.95,
                    home: CGPoint(x: width * 0.22, y: height * 0.26),
                    drift: CGSize(width: unit * 0.10, height: unit * 0.09),
                    speed: 0.9, isStill: self.reduceMotion)
                DriftingBlob(
                    color: Color.blue.opacity(0.16), diameter: unit * 0.9,
                    home: CGPoint(x: width * 0.82, y: height * 0.30),
                    drift: CGSize(width: -unit * 0.09, height: unit * 0.11),
                    speed: 1.18, isStill: self.reduceMotion)
                DriftingBlob(
                    color: Color.accentColor.opacity(0.15), diameter: unit,
                    home: CGPoint(x: width * 0.34, y: height * 0.8),
                    drift: CGSize(width: unit * 0.12, height: -unit * 0.09),
                    speed: 0.78, isStill: self.reduceMotion)
                DriftingBlob(
                    color: Color.blue.opacity(0.14), diameter: unit * 0.85,
                    home: CGPoint(x: width * 0.78, y: height * 0.82),
                    drift: CGSize(width: -unit * 0.11, height: -unit * 0.08),
                    speed: 1.05, isStill: self.reduceMotion)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .blur(radius: 50)
        .clipped()
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            self.size = newSize
        }
    }
}

private struct DriftingBlob: View {
    let color: Color
    let diameter: CGFloat
    let home: CGPoint
    let drift: CGSize
    let speed: Double
    let isStill: Bool

    @State private var isDrifting = false

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: [self.color, self.color.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: self.diameter / 2))
            .frame(width: self.diameter, height: self.diameter)
            .scaleEffect(self.isDrifting ? 1.1 : 0.9)
            .position(
                x: self.home.x + (self.isDrifting ? self.drift.width : -self.drift.width),
                y: self.home.y + (self.isDrifting ? self.drift.height : -self.drift.height))
            .onAppear {
                guard !self.isStill else { return }
                withAnimation(Tokens.Animations.thanksDrift.speed(self.speed).repeatForever(autoreverses: true)) {
                    self.isDrifting = true
                }
            }
    }
}
#endif
