#if os(iOS) || os(macOS)
import SwiftUI

enum Tokens {
    enum Animations {
        static let quickFade: Animation = .easeInOut(duration: 0.2)
        static let successPop: Animation = .spring(duration: 0.32, bounce: 0.28)
        static let saveMorph: Animation = .smooth(duration: 0.24)
        static let controlMorph: Animation = .smooth(duration: 0.22)
        static let felt: Animation = .spring(duration: 0.32, bounce: 0.16)
        static let thanksFade: Animation = .smooth(duration: 0.55)
        static let thanksIconSettle: Animation = .smooth(duration: 0.68)
        static let thanksTitleLand: Animation = .smooth(duration: 0.8).delay(0.35)
        static let thanksDetailLand: Animation = .smooth(duration: 0.8).delay(0.5)
        static let thanksSheen: Animation = .easeInOut(duration: 0.8)
        static let thanksBreath: Animation = .easeInOut(duration: 3.5)
        static let thanksDrift: Animation = .easeInOut(duration: 8)
    }

    enum Colors {
        #if os(iOS)
            static let background = Color(.systemBackground)
        #else
            static let background = Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

struct SendButtonMorph: View {
    enum Phase: Equatable {
        case idle
        case working
        case success
    }

    let phase: Phase
    let title: String
    let image: Image?
    let workingLabel: String
    let completeLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                if let image = self.image {
                    image.accessibilityLabel(self.title)
                } else {
                    Text(self.title)
                }
            }
            .opacity(self.phase == .idle ? 1 : 0)
            .accessibilityHidden(self.phase != .idle)

            // a spinner inside a button has no label of its own
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(self.workingLabel)
                .opacity(self.phase == .working ? 1 : 0)
                .accessibilityHidden(self.phase != .working)

            Image(systemName: "checkmark")
                .symbolEffect(.drawOn, isActive: !self.reduceMotion && self.phase != .success)
                .opacity(self.phase == .success ? 1 : 0)
                .accessibilityLabel(self.completeLabel)
                .accessibilityHidden(self.phase != .success)
        }
        .animation(self.reduceMotion ? nil : self.animation, value: self.phase)
    }

    /// How the button arrives at `phase`.
    private var animation: Animation {
        switch self.phase {
        case .idle: Tokens.Animations.saveMorph
        case .working: Tokens.Animations.quickFade
        case .success: Tokens.Animations.successPop
        }
    }
}
#endif
