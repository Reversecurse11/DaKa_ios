import SwiftUI

/// Email-only security projection. The retired phone/SMS and local-success
/// flows are intentionally not exposed.
struct ContactManagementView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var verifiedEmail: String?

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                        SectionTitle(eyebrow: "ACCOUNT", title: "登录与安全")
                        Text("学生登录仅支持学校邮箱；这里展示服务器返回的验证状态。")
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)

                        ContactStatusPanel(verifiedEmail: verifiedEmail)

                        Text("已验证邮箱变更需要当前邮箱和新邮箱双验证码；完整流程接入前，本地不会显示或保存假成功。")
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
