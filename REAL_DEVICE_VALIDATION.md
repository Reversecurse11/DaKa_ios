# BNBU Student iOS 真机验证记录

更新时间：2026-07-02

## 当前预检结论

- 项目：`ios-app/BNBUStudent.xcodeproj`
- Scheme：`BNBUStudent`
- Bundle ID：`edu.bnbu.student.mvp`
- 后端 API：`http://123.207.5.70:96/api`
- 权限声明已配置：
  - `NSPhotoLibraryUsageDescription`
  - `NSCameraUsageDescription`
  - `NSMicrophoneUsageDescription`
  - `NSLocalNetworkUsageDescription`
  - `123.207.5.70` HTTP ATS 例外
- CLI 预检结果：
  - `xcodebuild -showdestinations` 已识别真实 iPhone：`LABYR1NTH的iPhone`
  - 已选择 Team：`29T9XQFV8P`
  - 已生成 `Apple Development` 签名证书和 `iOS Team Provisioning Profile`
  - `iphoneos` 真机架构编译已通过：`CODE_SIGNING_ALLOWED=NO build`
  - 真机 Debug build 已通过：`BUILD SUCCEEDED`
  - 真机安装与启动已完成，App 已进入登录页 / 首页
- 结论：iOS 真机 MVP 验证完成，可进入本周第一版交付收口。

## 真机准备

1. 使用支持数据传输的数据线连接 iPhone 和 Mac。
2. iPhone 弹窗选择“信任此电脑”，并输入锁屏密码。
3. 打开 Xcode，进入 `Xcode > Settings > Accounts`，登录 Apple ID。
4. 打开项目 `ios-app/BNBUStudent.xcodeproj`。
5. 选择 Target `BNBUStudent`，进入 `Signing & Capabilities`：
   - 勾选 `Automatically manage signing`
   - Team 选择自己的 Apple ID Team
   - 如 Bundle ID 冲突，可临时改成个人唯一 ID，例如 `edu.bnbu.student.mvp.<你的缩写>`
6. 顶部运行设备选择自己的 iPhone。
7. 点击 Run。首次安装后如提示不受信任开发者，在 iPhone：
   - `设置 > 通用 > VPN 与设备管理`
   - 信任对应 Apple Developer 证书

## 终端确认命令

```bash
cd /Users/labyr1nth/Desktop/DaKa

xcodebuild -showdestinations \
  -project ios-app/BNBUStudent.xcodeproj \
  -scheme BNBUStudent

security find-identity -p codesigning -v
```

真机被识别后，`showdestinations` 中应出现类似：

```text
{ platform:iOS, id:..., name:你的 iPhone }
```

## 真机 Smoke Case

| 编号 | 场景 | 操作 | 预期结果 | 状态 |
| --- | --- | --- | --- | --- |
| 1 | 启动 | 真机打开 App | 启动无闪退，显示登录页 | 通过 |
| 2 | 真实登录 | 使用密码管理器提供的专用 QA 账号登录 | 进入首页，显示当前 QA 学生和学时进度 | 通过 |
| 3 | 首页刷新 | 下拉/重新进入首页 | 进度、风险、通知正常显示 | 通过 |
| 4 | 课程 | 进入“我的课程” | 展示课程代码与 Section | 通过 |
| 5 | 打卡任务 | 进入打卡任务列表 | 课程相关/其他运动任务正常分组 | 通过 |
| 6 | 相册完整访问 | 提交打卡时从相册选图 | 弹出权限，请求后可选择图片 | 通过 |
| 7 | 相册限制访问 | iOS 权限选择限制访问 | App 不闪退，可继续选择授权内图片或提示去设置 | 通过 |
| 8 | 相册拒绝访问 | 拒绝相册权限 | App 显示可恢复路径，不闪退 | 通过 |
| 9 | 摄像头拍照 | 添加凭证选择拍照 | 弹出摄像头权限，可拍照回填 | 通过 |
| 10 | 视频凭证 | 添加 1 个视频 | 视频数量限制生效，超过 1 个有提示 | 通过 |
| 11 | 大图限制 | 选择超过 8MB 图片 | 阻止提交并显示大小限制 | 代码校验通过，极限素材待补测 |
| 12 | 大视频限制 | 选择超过 100MB 视频 | 阻止提交并显示大小限制 | 代码校验通过，极限素材待补测 |
| 13 | 打卡提交 | 选任务、填时长、上传凭证提交 | 后端返回待审核记录，记录页可读回 | 通过 |
| 14 | 免测提交 | 成绩页提交 `800m/1000m` 免测 | 后端返回待审核记录，免测列表可读回 | 通过 |
| 15 | 通知 | 标记通知已读 | UI 状态更新，无闪退 | 待测 |
| 16 | 退出登录 | 设置页退出登录 | 回到登录页，本地状态清理 | 通过 |

## 真机 MVP 验证结论

- 状态：完成。
- 通过范围：
  - 真机安装、启动、登录、首页、课程、打卡任务、相册权限、摄像头权限、打卡提交、免测提交、退出登录。
  - 输入文字可读性、全局浅色主题、键盘收起路径均已复测通过。
- 非阻塞补测：
  - 超过 8MB 的大图片真实素材。
  - 超过 100MB 的大视频真实素材。
  - 通知已读状态可在后续通知数据稳定后补测。
- 交付判断：满足本周 iOS 学生端 MVP 真机演示和第一版产品交付要求。

## 已知注意事项

- 真机验证会向真实服务器写入测试记录，提交备注请包含“iOS真机测试”，方便后端清理。
- iOS 端不保存 COS SecretId / SecretKey，文件上传只走后端 `/api/upload/proof`。
- 免测申请后端当前不支持补材料；被驳回后前端引导重新提交新申请。

## 2026-07-02 真机反馈修复

- 已修复：深色系统外观下，登录页、提交打卡、免测申请输入文字颜色过淡。
  - 处理方式：统一输入控件使用 BNBU 高对比黑色文字、蓝色光标，并固定浅色输入环境。
  - 复测范围：登录账号/密码、打卡补充说明、免测申请原因、免测情况说明。
- 已修复：相册入口直接打开系统选择器，没有覆盖“完整访问 / 限制访问 / 拒绝访问”授权弹窗。
  - 处理方式：点击“从相册选择”时先调用 `PHPhotoLibrary.requestAuthorization(for: .readWrite)`，再打开照片选择器。
  - 复测范围：首次授权弹窗、完整访问、限制访问、拒绝访问、拒绝后跳设置路径。
- 已验证：
  - `BNBUStudentTests` 全部通过
  - `iphoneos` 真机架构编译通过
  - 真机签名 Debug build 通过

## 2026-07-02 全局可读性修复

- 已修复：深色系统外观下，各页面可能出现默认文字变白，叠在 BNBU 浅色背景 / 白色面板上导致“字体消失”。
  - 根因：App 视觉规范是固定蓝白黑浅色体系，但部分 SwiftUI `Text` / 系统控件仍跟随系统 `Dark Mode` 默认前景色。
  - 处理方式：在 App 根节点统一设置 BNBU 浅色外观：`.preferredColorScheme(.light)` 与 `.environment(\.colorScheme, .light)`。
  - 复测范围：登录、首页、课程、打卡、成绩、免测表单、设置页、弹窗 / sheet。
- 已验证：
  - `BNBUStudentTests` 全部通过
  - `iphoneos` 真机架构编译通过
  - 真机签名 Debug build 通过

## 2026-07-02 键盘收起修复

- 已修复：登录、提交打卡、免测申请等输入文字后，键盘缺少稳定的收起路径。
  - 根因：多行 `TextEditor` 默认回车是换行，不会关闭键盘；部分输入页没有统一键盘工具栏。
  - 处理方式：新增通用 `bnbuKeyboardDismissToolbar()`，键盘上方提供“完成”；登录和打卡页支持滚动交互式收起；提交按钮触发前主动收起键盘。
  - 复测范围：登录账号 / 密码、打卡补充说明、免测申请原因、免测情况说明。
- 已验证：
  - `BNBUStudentTests` 全部通过
  - `iphoneos` 真机架构编译通过
  - 真机签名 Debug build 通过

## 2026-07-02 键盘收起二次加固

- 已修复：打卡页 `TextEditor` 仍可能无法稳定收起键盘。
  - 根因：通用 `UIApplication.resignFirstResponder` 在 SwiftUI `TextEditor` 上不够稳定，打卡页没有绑定具体 `FocusState`。
  - 处理方式：
    - 登录、打卡、免测全部输入点显式绑定 `@FocusState`
    - 键盘“完成”按钮同时清 `FocusState` 和调用全局收键盘
    - 打卡“补充说明”标题右侧增加收起键盘图标按钮
    - 滚动收起策略改为 `.scrollDismissesKeyboard(.immediately)`
    - 切换打卡分段、提交、关闭表单时主动清焦点
  - 覆盖输入点：
    - 登录账号
    - 登录密码
    - 打卡补充说明
    - 免测申请原因
    - 免测情况说明
- 已验证：
  - `BNBUStudentTests` 全部通过
  - `iphoneos` 真机架构编译通过
  - 真机签名 Debug build 通过
