import SwiftUI
import UIKit

struct PINSheet: View {
    enum Mode { case set, unlock }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    var onSuccess: () -> Void = {}

    @State private var current = ""
    @State private var first = ""
    @State private var second = ""
    @State private var error: String?
    @FocusState private var focused: Field?

    private enum Field { case current, first, second }

    var body: some View {
        NavigationStack {
            Form {
                switch mode {
                case .unlock:
                    Section {
                        SecureField("PIN", text: $current)
                            .focused($focused, equals: .current)
                    } footer: {
                        errorText
                    }
                case .set:
                    if model.state.hasPin {
                        Section {
                            SecureField("Current PIN", text: $current)
                                .focused($focused, equals: .current)
                        }
                    }
                    Section {
                        SecureField("New PIN (4–8 digits)", text: $first)
                            .focused($focused, equals: .first)
                        SecureField("Repeat new PIN", text: $second)
                            .focused($focused, equals: .second)
                    } footer: {
                        if error == nil {
                            Text("Used to unlock Strict Mode when the unlock method is PIN code. It's stored only as a salted hash on this iPhone.")
                        } else {
                            errorText
                        }
                    }
                }
            }
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .unlock ? "Unlock" : "Save", action: submit)
                        .fontWeight(.semibold)
                        .disabled(mode == .unlock ? current.isEmpty : first.isEmpty || second.isEmpty)
                }
            }
            .task {
                // Focus set while the sheet is still animating in is ignored.
                try? await Task.sleep(nanoseconds: 400_000_000)
                focused = mode == .set && !model.state.hasPin ? .first : .current
            }
        }
        .presentationDetents([.medium])
    }

    private var title: String {
        switch mode {
        case .unlock: return "Unlock Strict Mode"
        case .set: return model.state.hasPin ? "Change PIN" : "Set a PIN"
        }
    }

    @ViewBuilder
    private var errorText: some View {
        if let error {
            Text(error).foregroundStyle(.red)
        }
    }

    private func submit() {
        switch mode {
        case .unlock:
            if model.unlockWithPIN(current) {
                dismiss()
            } else {
                error = "Wrong PIN"
                current = ""
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        case .set:
            if let message = model.setPIN(current: current, new: first, repeated: second) {
                error = message
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                onSuccess()
                dismiss()
            }
        }
    }
}
