#if os(iOS) || os(macOS)
import SwiftUI

enum Tokens {
    enum Animations {
        static let quickFade: Animation = .easeInOut(duration: 0.2)
        static let successPop: Animation = .spring(duration: 0.32, bounce: 0.28)
        static let saveMorph: Animation = .smooth(duration: 0.24)
        static let controlMorph: Animation = .smooth(duration: 0.22)
        static let felt: Animation = .spring(duration: 0.32, bounce: 0.16)
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
    let completeLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Phase
    @State private var latestPhase: Phase
    @State private var labelFadeDone = false

    init(phase: Phase, title: String, image: Image?, completeLabel: String) {
        self.phase = phase
        self.title = title
        self.image = image
        self.completeLabel = completeLabel
        self._displayed = State(initialValue: phase)
        self._latestPhase = State(initialValue: phase)
    }

    var body: some View {
        ZStack {
            Group {
                if let image = self.image {
                    image.accessibilityLabel(self.title)
                } else {
                    Text(self.title)
                }
            }
            .opacity(self.displayed == .idle ? 1 : 0)
            .accessibilityHidden(self.displayed != .idle)

            ProgressView()
                .controlSize(.small)
                .opacity(self.displayed == .working ? 1 : 0)
                .accessibilityHidden(self.displayed != .working)

            Image(systemName: "checkmark")
                .symbolEffect(.drawOn, isActive: !self.reduceMotion && self.displayed != .success)
                .opacity(self.displayed == .success ? 1 : 0)
                .accessibilityLabel(self.completeLabel)
                .accessibilityHidden(self.displayed != .success)
        }
        .onChange(of: self.phase) { _, newPhase in
            self.latestPhase = newPhase
            self.advance(to: newPhase)
        }
    }

    private func advance(to newPhase: Phase) {
        if self.reduceMotion {
            self.labelFadeDone = newPhase != .idle
            self.displayed = newPhase
            return
        }

        switch (self.displayed, newPhase) {
        case (.idle, .working), (.idle, .success):
            withAnimation(Tokens.Animations.quickFade, completionCriteria: .removed) {
                self.displayed = .working
            } completion: {
                self.labelFadeDone = true
                guard self.latestPhase == .success, self.displayed == .working else { return }
                withAnimation(Tokens.Animations.successPop) {
                    self.displayed = .success
                }
            }

        case (.working, .success):
            guard self.labelFadeDone else { return }
            withAnimation(Tokens.Animations.successPop) {
                self.displayed = .success
            }

        case (_, .idle):
            self.labelFadeDone = false
            withAnimation(Tokens.Animations.saveMorph) {
                self.displayed = .idle
            }

        default:
            withAnimation(Tokens.Animations.saveMorph) {
                self.displayed = newPhase
            }
        }
    }
}
#endif
