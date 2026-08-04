import SwiftUI

/// Settings → 绑定或更换邮箱、手机号. Mirrors the Android `ContactBindingScreen`
/// in its `ManageContacts` mode: each contact is verified on its own and saved
/// as soon as it passes, so there is no submit button.
struct ContactManagementView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var phone = ""
    @State private var email = ""
    @State private var verifiedPhone: String?
    @State private var verifiedEmail: String?

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                        SectionTitle(eyebrow: "ACCOUNT", title: "登录与安全")
                        Text("添加或更换邮箱、手机号，保持登录方式随时可用。")
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)

                        ContactStatusPanel(
                            verifiedPhone: verifiedPhone,
                            verifiedEmail: verifiedEmail
                        )

                        ContactChannelPanel(
                            channel: .phone,
                            value: $phone,
                            verifiedValue: $verifiedPhone,
                            allowsReplacement: true
                        )
                        ContactChannelPanel(
                            channel: .email,
                            value: $email,
                            verifiedValue: $verifiedEmail,
                            allowsReplacement: true
                        )

                        Text("验证任一联系方式后会自动保存。")
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
        if ContactBindingRule.isValid(boundEmail, for: .email) {
            verifiedEmail = boundEmail
        }
        if let boundPhone = appState.courseJoinRequest?.phone,
           ContactBindingRule.isValid(boundPhone, for: .phone) {
            verifiedPhone = boundPhone
        }
    }
}

/// The "登录方式" summary Android shows above the forms, so a student can see
/// at a glance which contacts can already receive a code.
private struct ContactStatusPanel: View {
    let verifiedPhone: String?
    let verifiedEmail: String?

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                BNBUGroupLabel("登录方式")
                statusRow(channel: .email, value: verifiedEmail)
                Divider().overlay(BNBUTheme.outlineVariant.opacity(0.45))
                statusRow(channel: .phone, value: verifiedPhone)
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
