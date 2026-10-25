#if os(iOS) || os(macOS)
import SwiftUI

public struct FeedbackView: View {
    let strings: (FeedbackString) -> String
    let title: FeedbackString
    let prompt: FeedbackString
    let hapticsEnabled: Bool
    let onDismiss: () -> Void

    @State private var model: FeedbackModel
    @FocusState private var focusedField: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field {
        case message
        case email
    }

    public init(
        serviceURL: URL,
        appID: String = Bundle.main.bundleIdentifier ?? "",
        strings: @escaping (FeedbackString) -> String,
        title: FeedbackString = .feedbackTitle,
        prompt: FeedbackString = .feedbackPrompt,
        context: [String] = [],
        hapticsEnabled: Bool = true,
        onDismiss: @escaping () -> Void)
    {
        self.init(
            sender: FeedbackClient(serviceURL: serviceURL, appID: appID),
            strings: strings,
            title: title,
            prompt: prompt,
            context: context,
            hapticsEnabled: hapticsEnabled,
            onDismiss: onDismiss)
    }

    public init(
        sender: some FeedbackSender,
        strings: @escaping (FeedbackString) -> String,
        title: FeedbackString = .feedbackTitle,
        prompt: FeedbackString = .feedbackPrompt,
        context: [String] = [],
        hapticsEnabled: Bool = true,
        onDismiss: @escaping () -> Void)
    {
        self._model = State(initialValue: FeedbackModel(sender: sender, context: context))
        self.strings = strings
        self.title = title
        self.prompt = prompt
        self.hapticsEnabled = hapticsEnabled
        self.onDismiss = onDismiss
    }

    public var body: some View {
        self.form
            .accessibilityIdentifier("feedback.form")
            .alert(
                self.strings(.failedTitle),
                isPresented: Binding(
                    get: { self.model.alert != nil },
                    set: { isPresented in
                        if !isPresented {
                            self.model.alert = nil
                        }
                    }),
                presenting: self.model.alert)
            { error in
                if error == .unsupported {
                    Button(self.strings(.ok)) {}
                } else {
                    Button(self.strings(.tryAgain)) {
                        Task { await self.model.tryAgain() }
                    }
                    Button(self.strings(.cancel), role: .cancel) {}
                }
            } message: { error in
                Text(self.strings(FeedbackModel.message(for: error)))
            }
            .sensoryFeedback(.error, trigger: self.model.emailErrorCount) { _, _ in
                self.hapticsEnabled
            }
            .sensoryFeedback(.success, trigger: self.model.didSucceed) { _, didSucceed in
                self.hapticsEnabled && didSucceed
            }
            .onChange(of: self.model.emailErrorCount) {
                AccessibilityNotification.Announcement(self.strings(.emailInvalid)).post()
            }
            .onChange(of: self.model.didSucceed) { _, didSucceed in
                if didSucceed {
                    AccessibilityNotification.Announcement(self.strings(.thanks)).post()
                }
            }
            .onChange(of: self.focusedField) { oldField, _ in
                if oldField == .email {
                    self.model.emailEditingEnded()
                }
            }
            .onChange(of: self.model.shouldDismiss) { _, shouldDismiss in
                if shouldDismiss {
                    self.onDismiss()
                }
            }
            .onAppear { self.focusedField = .message }
    }

    #if os(iOS)
        private var form: some View {
            NavigationStack {
                Form {
                    self.messageSection
                    self.emailSection
                }
                .navigationTitle(self.strings(self.title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(self.strings(.cancel), systemImage: "xmark") {
                            self.model.cancelTapped()
                        }
                        .labelStyle(.iconOnly)
                        .keyboardShortcut(.cancelAction)
                        .discardConfirmation(model: self.model, strings: self.strings)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: self.send) {
                            SendButtonMorph(
                                phase: self.sendPhase,
                                title: self.strings(.send),
                                image: Image(systemName: "arrow.up"),
                                completeLabel: self.strings(.complete))
                        }
                        .accessibilityLabel(self.strings(.send))
                        .buttonStyle(.glassProminent)
                        .disabled(!self.model.canSend)
                    }
                }
            }
            .interactiveDismissDisabled(self.model.preventsInteractiveDismissal)
            .background(SheetDismissalGuard(
                isDisabled: self.model.preventsInteractiveDismissal,
                onAttempt: { self.model.cancelTapped() }))
        }
    #else
        private var form: some View {
            VStack(spacing: 0) {
                Form {
                    self.messageSection
                    self.emailSection
                }
                .formStyle(.grouped)

                HStack {
                    Spacer()
                    Button(self.strings(.cancel), role: .cancel) {
                        self.model.cancelTapped()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(action: self.send) {
                        SendButtonMorph(
                            phase: self.sendPhase,
                            title: self.strings(.send),
                            image: nil,
                            completeLabel: self.strings(.complete))
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!self.model.canSend)
                }
                .padding([.horizontal, .bottom], 20)
            }
            .frame(width: 480)
            .navigationTitle(self.strings(self.title))
            .discardConfirmation(model: self.model, strings: self.strings)
        }
    #endif

    private var messageSection: some View {
        Section {
            TextField(
                self.strings(.messageLabel),
                text: Binding(get: { self.model.message }, set: { self.model.messageChanged($0) }),
                prompt: Text(self.strings(self.prompt)),
                axis: .vertical)
                .labelsHidden()
            #if os(iOS)
                .lineLimit(6 ... 14)
                .textInputAutocapitalization(.sentences)
            #else
                .lineLimit(8 ... 16)
            #endif
                .focused(self.$focusedField, equals: .message)
        } footer: {
            Text(self.strings(self.model.messageFooter))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(
                    self.reduceMotion ? nil : Tokens.Animations.controlMorph,
                    value: self.model.messageFooter)
        }
    }

    private var emailSection: some View {
        Section {
            TextField(
                self.strings(.emailLabel),
                text: Binding(get: { self.model.email }, set: { self.model.emailChanged($0) }),
                prompt: Text(self.strings(.emailPlaceholder)))
                .labelsHidden()
                .textContentType(.emailAddress)
                .autocorrectionDisabled(true)
            #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .submitLabel(.send)
                .onSubmit(self.send)
            #endif
                .focused(self.$focusedField, equals: .email)
        } footer: {
            Text(self.strings(self.model.emailFooter))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(
                    self.reduceMotion ? nil : Tokens.Animations.felt,
                    value: self.model.isEmailErrorVisible)
        }
    }

    private var sendPhase: SendButtonMorph.Phase {
        if self.model.didSucceed {
            .success
        } else if self.model.isSending {
            .working
        } else {
            .idle
        }
    }

    private func send() {
        Task { await self.model.sendTapped() }
    }
}

extension View {
    fileprivate func discardConfirmation(
        model: FeedbackModel,
        strings: @escaping (FeedbackString) -> String) -> some View
    {
        self.confirmationDialog(
            strings(.discardTitle),
            isPresented: Binding(
                get: { model.isDiscardConfirmationPresented },
                set: { model.isDiscardConfirmationPresented = $0 }),
            titleVisibility: .visible)
        {
            Button(strings(.discard), role: .destructive) {
                model.discard()
            }
            Button(strings(.keepEditing), role: .cancel) {}
        } message: {
            Text(strings(.discardMessage))
        }
    }
}
#endif
