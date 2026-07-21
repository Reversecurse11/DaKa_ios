# iOS 第二轮安全与发布审计（2026-07-15）

## 结论

iOS 源码侧的高风险项已经完成收敛，并由 Windows 静态契约审计覆盖。当前 Debug 仍可连接 `123.207.5.70:82` 测试；Release 刻意配置为不可发布占位地址，直到提供正式 HTTPS API 域名后才允许构建通过。

本轮未修改 Web、Android、后端或 QA 目录。

## 已修复

- 短期 Access Token 改存设备专属 Keychain：`WhenUnlockedThisDeviceOnly`，禁用同步，不进入备份。
- 冻结 v1 没有 refresh/logout 接口：退出改为纯本地清理，并清除 Token、当前账号缓存、未提交草稿及内存工作区。
- 登录与退出增加会话世代校验，迟到的登录响应不能恢复已退出会话；工作区刷新与关键写操作增加 single-flight/重复提交保护。
- 学生缓存从偏好设置迁移到 Application Support 受保护文件，使用 `NSFileProtectionComplete`、排除备份，并哈希账号/服务器相关文件名。
- 凭证上传只使用冻结 v1 `POST /upload/proof`；删除旧 `/checkins/{id}/proofs` 回退。multipart 使用受保护临时文件流式上传，成功或失败均清理，启动时清理崩溃遗留文件。
- 任务资格在客户端再次校验：只有 Active、未完成，且具有非空无首尾空白的任务/课程 ID、受支持的 credit type、后端允许的 1/2 小时值和可解析未过期截止时间的服务端任务，才可进入首页待办/提交路径；字段缺失、未知类型、非法学时、不可解析日期、Draft、Closed、Completed、Expired 均失败关闭。非法 credit type 状态在受保护缓存编码/回读后仍保持失败关闭。
- 日期型截止值按后端业务时区 `Asia/Shanghai` 的当日 23:59:59.999 处理，非法日历日期禁止宽松纠正；带时区的 ISO 8601 时间仍按其明确时区解析。
- 服务端 general 任务提交保留 `courseId + taskId`；只有 AppState 在内存中合成且不可由 JSON/Codable 授权的 `self-general` 自主打卡省略二者。服务端或缓存中的同名、缺字段任务不能冒充该例外。
- Debug/Release ATS 分离：Debug 仅为当前测试 IP 保留窄 HTTP 例外；Release 禁止任意加载、本地网络和测试 IP。
- Release API 地址必须是非占位 HTTPS 且以 `/api/v1` 结尾；构建脚本会阻止错误归档。
- 使用系统 `PhotosPicker` 的选择项访问，不申请整库相册权限；保留相机与视频录音的最小用途说明。
- 增加 `PrivacyInfo.xcprivacy`、Required Reason API 声明和数据类型声明。
- 当前未注册自定义 URL Scheme、Universal Link entitlement 或隐式 deep-link handler，因此没有可外部唤起的 deep-link 攻击面。
- 删除运行时明文日志入口，未知服务端错误统一映射为不泄露内部信息的用户提示。
- 补充关键 VoiceOver 标签、状态组合语义、上传进度提示和退出确认。

## Windows 已完成验证

- `node --check scripts/ios-contract-audit.mjs`
- `node scripts/ios-contract-audit.mjs`（198 项静态断言全部通过）
- 三个 plist/xcprivacy 文件均通过 XML 解析。
- Xcode 工程对象 ID 无重复；新增 Swift、隐私清单、Debug plist 和 Release 构建阶段均已进入工程。
- `validate-release-config.sh` 通过 shell 语法检查；Debug 与合法 HTTPS Release 配置通过，HTTP、占位域名和错误 API 路径均被拒绝。
- Swift 文件分隔符、冲突标记及尾随空白静态检查通过。

新增 XCTest 覆盖：Keychain 迁移与本地退出、退出/登录竞态、重复 mutation、唯一上传路径与临时文件清理、受保护缓存、退出清理、任务资格过滤、缺失/非法任务字段失败关闭、上海日期型截止边界与非法日期，以及 general 服务端任务与 self-general 的请求体差异。

## Mac/Xcode 必须完成的发布前验证

Windows 无法运行 Apple Swift 编译器、iOS Simulator 或签名工具，因此以下项目仍是发布门槛：

1. 在当前 Xcode 正式版运行单元测试和 UI smoke tests：

   ```sh
   xcodebuild -project BNBUStudent.xcodeproj \
     -scheme BNBUStudent \
     -configuration Debug \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     test
   ```

2. 提供正式 HTTPS API 域名后做无签名 Release 编译验证：

   ```sh
   xcodebuild -project BNBUStudent.xcodeproj \
     -scheme BNBUStudent \
     -configuration Release \
     -destination 'generic/platform=iOS' \
     BNBU_API_BASE_URL='https://正式域名/api/v1' \
     CODE_SIGNING_ALLOWED=NO \
     build
   ```

3. 完成正式签名、Archive、Organizer Validate App，并核对 App Store Connect 隐私标签与实际后端留存/用途一致。
4. 真机验证 Keychain 在锁屏/解锁、退出、重启、卸载重装和设备备份恢复下的行为。
5. 真机验证相机、麦克风、PhotosPicker 最小权限；验证上传中断、锁屏、切后台和大文件失败后的临时文件清理。
6. 开启 Thread Sanitizer/并发诊断复测登录退出竞态、刷新 single-flight 和重复提交。
7. 使用 VoiceOver、超大动态字体、降低动态效果、Switch Control 和高/低对比度完成可访问性走查。

## 当前外部阻塞

- Release 的 `BNBU_API_BASE_URL` 仍为 `https://configuration-required.invalid/api/v1`，这是有意的发布保险。没有正式 HTTPS 域名时，不应绕过门禁归档上线。
- App Store 隐私声明最终内容需要产品/学校依据真实数据保留周期、后端用途及隐私政策确认。
