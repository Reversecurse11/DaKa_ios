import SwiftUI

private enum LoginFormField: Hashable {
    case account
    case password
}

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedField: LoginFormField?
    @State private var account = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var showPrivacyPolicy = false

    var body: some View {
        ZStack {
            GridBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    universityBrandLockup
                    headerBlock
                    loginPanel

                    Text("第一阶段仅包含学生端体育打卡与成绩透明化；老师端和管理端由 Web 承担。")
                        .font(.footnote.weight(.regular))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .accessibilityIdentifier("screen.login")
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showPrivacyPolicy = false }
                        }
                    }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                    dismissBNBUKeyboard()
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }

    private var universityBrandLockup: some View {
        HStack(spacing: 12) {
            BrandMark(compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("北师香港浸会大学")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(BNBUTheme.onSurface)
                Text("BNBU · STUDENT SPORTS")
                    .font(.caption2.weight(.medium))
                    .tracking(0.6)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BNBU")
                .font(.system(size: 57, weight: .regular))
                .foregroundStyle(BNBUTheme.onSurface)
            Text("体育打卡与成绩进度")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(BNBUTheme.onSurface)
            Text("课程相关 10 小时 + 其他运动 10 小时，进度、缺口与打卡记录一次看清。")
                .font(.body.weight(.regular))
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .lineSpacing(4)
        }
    }

    private var loginPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "SIGN IN", title: "学生登录")

                if let errorMessage = appState.errorMessage {
                    BNBUErrorPanel(message: errorMessage)
                }

                loginField(title: "学号 / 邮箱") {
                    TextField("请输入学号或校园邮箱", text: $account)
                        .accessibilityLabel("学号或邮箱")
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .account)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .accessibilityIdentifier("login.email.field")
                }

                loginField(title: "密码") {
                    HStack(spacing: 8) {
                        Group {
                            if passwordVisible {
                                TextField("请输入密码", text: $password)
                            } else {
                                SecureField("请输入密码", text: $password)
                            }
                        }
                        .textContentType(.password)
                        .accessibilityLabel("密码")
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .onSubmit { submitLogin() }
                        .accessibilityIdentifier("login.password.field")

                        Button {
                            passwordVisible.toggle()
                        } label: {
                            Image(systemName: passwordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(passwordVisible ? "隐藏密码" : "显示密码")
                    }
                }

                PrimaryActionButton(
                    title: appState.isLoading ? "登录中…" : "进入学生端",
                    systemImage: "arrow.right",
                    accessibilityIdentifier: "login.submit.button"
                ) {
                    submitLogin()
                }
                .disabled(!canLogin)
                .opacity(canLogin ? 1 : 0.55)

                Button("登录前请阅读《隐私政策》") {
                    showPrivacyPolicy = true
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BNBUTheme.primary)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
        }
    }

    private func loginField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            content()
                .bnbuInputText()
                .padding(12)
                .background(BNBUTheme.surface)
                .bnbuOutlinedSurface(lineWidth: 1)
        }
    }

    private var canLogin: Bool {
        !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.isEmpty &&
            !appState.isLoading
    }

    private func submitLogin() {
        guard canLogin else { return }
        focusedField = nil
        dismissBNBUKeyboard()
        Task {
            await appState.login(
                account: account.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ZStack {
            BNBUPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(eyebrow: "PRIVACY", title: "隐私政策")
                    privacySection("一、信息收集", paragraphs: [
                        "本应用仅收集校园体育服务所需的账户、课程、学时、成绩和申请信息。",
                        "提交打卡或免测申请时，只有经您主动选择或拍摄的图片、视频及说明会被上传。"
                    ])
                    privacySection("二、信息使用", paragraphs: [
                        "相关信息仅用于体育学时计算、成绩展示、打卡记录、免测申请和校园通知，不用于商业广告。"
                    ])
                    privacySection("三、本地存储与安全", paragraphs: [
                        "密码仅用于登录请求，不写入本地持久化状态。短期登录令牌保存在本机 Keychain；工作台缓存和未提交草稿使用完整文件保护并排除云备份。退出登录会清理当前账号凭据、缓存和草稿。",
                        "从相册选择凭证使用系统照片选择器，App 只接收您明确选中的项目；直接拍摄仅在您操作时申请摄像头及录音权限。",
                        "正式环境应使用受信任的 HTTPS 服务；调试环境的 HTTP 地址仅用于联调，不应承载真实敏感数据。"
                    ])
                    privacySection("四、用户权利", paragraphs: [
                        "您可以查看自己的学时、成绩和打卡记录；如需更正或删除服务器数据，请联系体育老师或系统管理员。"
                    ])
                    privacySection("五、政策更新", paragraphs: [
                        "重大变更将通过 App 内通知或学校公告告知。最新修订日期：2026 年 7 月 15 日。"
                    ])
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacySection(_ title: String, paragraphs: [String]) -> some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline.weight(.medium))
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .lineSpacing(3)
                }
            }
        }
    }
}
