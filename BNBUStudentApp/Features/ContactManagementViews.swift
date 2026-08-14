import SwiftUI

/// Settings → bind or replace the single email authentication channel.
struct ContactManagementView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var verifiedEmail: String?

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                        SectionTitle(eyebrow: "ACCOUNT", title: "登录与安全")
                        Text("绑定或更换邮箱，保持验证码登录方式可用。")
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)

                        ContactStatusPanel(
                            verifiedEmail: verifiedEmail
                        )

                        ContactChannelPanel(
                            channel: .email,
                            value: $email,
                            verifiedValue: $verifiedEmail,
                            allowsReplacement: true
                        )

                        Text("邮箱验证成功后会自动保存。")
                            .font(BNBUFont.bodySmall)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    }
                    .padding(BNBUSpacing.screen)
                }
            }
            .navigationTitle(Text("登录与安全"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("contactBinding.back")
                }
            }
        }
        .onAppear(perform: seedFromProfile)
        .accessibilityIdentifier("screen.contactManagement")
    }

    /// The server only ever returns contacts masked, so an already-bound
    /// address is shown as verified rather than pre-filled for editing.
    private func seedFromProfile() {
        guard verifiedEmail == nil else { return }
        let boundEmail = appState.workspace.student.email
        if appState.isEmailVerified, !boundEmail.isEmpty {
            verifiedEmail = boundEmail
        }
    }
}

/// The "登录方式" summary Android shows above the forms, so a student can see
/// at a glance which contacts can already receive a code.
private struct ContactStatusPanel: View {
    let verifiedEmail: String?

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                BNBUGroupLabel("登录方式")
                statusRow(channel: .email, value: verifiedEmail)
            }
        }
    }

    private func statusRow(channel: ContactChannel, value: String?) -> some View {
        HStack(spacing: BNBUSpacing.space12) {
            Image(systemName: channel.systemImage)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            Text(LocalizedStringKey(channel.title))
                .font(BNBUFont.titleSmall)
                .foregroundStyle(BNBUTheme.onSurface)
            Spacer(minLength: 0)
            if let value {
                Text(verbatim: ContactBindingRule.masked(value, for: channel))
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
            StatusBadge(text: value == nil ? "待验证" : "已验证", filled: value != nil)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("contactBinding.status.\(channel.rawValue)")
    }
}
