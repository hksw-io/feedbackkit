#if os(iOS) || os(macOS)
import SwiftUI

/// A feedback form for a sheet on iOS, or a sheet or window on macOS.
///
/// The form owns its draft, the email check, the send and its failure alert, and Discard Changes. It calls
/// `onDismiss` when the person closes an empty form, confirms Discard Changes, or when the thank-you screen
/// after a successful send ends, which it does after 5 seconds or when the person taps it.
public struct FeedbackView: View {
    let icon: Image
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

    /// Creates a form that sends to the HK Softworks feedback service.
    ///
    /// - Parameters:
    ///   - serviceURL: The service's base URL, production or sandbox.
    ///   - appID: The bundle ID the service knows the app by. Defaults to the main bundle's.
    ///   - icon: The app icon, shown on the thank-you screen.
    ///   - strings: The app's text for every ``FeedbackString``.
    ///   - title: `.feedbackTitle` or `.problemTitle`.
    ///   - prompt: `.feedbackPrompt`, `.problemPrompt` or `.contentPrompt`.
    ///   - context: Lines sent with the message, such as what failed. Up to 10 lines of 500 characters.
    ///   - hapticsEnabled: The app's haptics preference.
    ///   - onDismiss: Closes the form.
    public init(
        serviceURL: URL,
        appID: String = Bundle.main.bundleIdentifier ?? "",
        icon: Image,
        strings: @escaping (FeedbackString) -> String,
        title: FeedbackString = .feedbackTitle,
        prompt: FeedbackString = .feedbackPrompt,
        context: [String] = [],
        hapticsEnabled: Bool = true,
        onDismiss: @escaping () -> Void)
    {
        self.init(
            sender: FeedbackClient(serviceURL: serviceURL, appID: appID),
            icon: icon,
            strings: strings,
            title: title,
            prompt: prompt,
            context: context,
            hapticsEnabled: hapticsEnabled,
            onDismiss: onDismiss)
    }

    /// Creates a form that sends through `sender`: your own backend, or a fake for previews and UI tests.
    public init(
        sender: some FeedbackSender,
        icon: Image,
        strings: @escaping (FeedbackString) -> String,
        title: FeedbackString = .feedbackTitle,
        prompt: FeedbackString = .feedbackPrompt,
        context: [String] = [],
        hapticsEnabled: Bool = true,
        onDismiss: @escaping () -> Void)
    {
        self._model = State(initialValue: FeedbackModel(sender: sender, context: context))
        self.icon = icon
        self.strings = strings
        self.title = title
        self.prompt = prompt
        self.hapticsEnabled = hapticsEnabled
        self.onDismiss = onDismiss
    }

    public var body: some View {
        self.form
            .accessibilityHidden(self.model.isThanking)
            .overlay { self.thanksOverlay }
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
                    self.focusedField = nil
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

    private var thanksOverlay: some View {
        ZStack {
            if self.model.isThanking {
                FeedbackThanksView(
                    icon: self.icon,
                    title: self.strings(.thanks),
                    detail: self.strings(self.model.thanksDetail))
                    .onTapGesture { self.model.cancelTapped() }
                    .transition(.opacity)
            }
        }
        .animation(self.reduceMotion ? nil : Tokens.Animations.thanksFade, value: self.model.isThanking)
    }

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
            #if os(iOS)
                // no .autocorrectionDisabled: it costs the keyboard's suggestion bar, and with it AutoFill's address.
                // The email keyboard doesn't autocorrect on its own.
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .submitLabel(.send)
                .onSubmit(self.send)
            #else
                .autocorrectionDisabled(true)
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
