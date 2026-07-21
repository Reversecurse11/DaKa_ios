# BNBU Student iOS App

SwiftUI 原生学生端 MVP，第一阶段聚焦体育打卡与体育成绩透明化，不包含老师端或管理端功能。

> **现行口径（2026-07-16）**：Debug 使用 `http://123.207.5.70:82/api/v1`；Release 必须由学校确认的 HTTPS 域名提供 `/api/v1`。本页后半部分按轮次保留的是历史开发记录，其中的 3333/96 端口、`/api` 前缀、旧上传路径和历史测试结论不得再作为构建或部署说明。当前执行入口以 [`IOS_QA_RUNBOOK.md`](IOS_QA_RUNBOOK.md)、`scripts/ios-contract-audit.mjs` 和 `scripts/run-macos-release-gate.sh` 为准。

> **主线切换（2026-07-19）**：本目录源自负责人 7.18 回传的反馈版源码（`7.18 Feedback/BNBUStudent-iOS-Source-20260717-Aligned-API-Version.zip`），经编译修复、68 项单元测试、UI 冒烟和真实服务器提交/读回闭环验证后升级为主线。旧 3333/96 主线保留在 `../ios-app-legacy-20260715/`，仅作归档不再开发。2026-07-19 验证记录：`test-evidence-20260718/`；Debug 演示图片凭证已携带真实字节，可在真实服务器模式走通上传与提交（演示视频仍为预览占位）。

## 范围

- 学生账号真实登录；演示数据仅保留给自动化 UI 测试，不在学生界面展示
- 首页体育学时进度看板：总 20h、课程相关 10h、其他运动 10h
- 我的课程：当前学期 + 可折叠历史课程，按 `课程代码 / Section` 展示教学班
- 自主运动打卡：1h/2h、运动项目、图片/视频凭证、真实上传进度，以及统一显示“已提交”的历史记录
- 成绩进度：体育打卡、专项考试、平时表现 / 签到、体测、总分预估
- 校队 / 社团认证与其他运动抵扣状态
- 首页通知弹层：通知筛选、全部已读、截止提醒和申请材料消息
- 个人中心：免测申请、耐力跑成绩换算、我的老师、组织认证与抵扣
- 入学年份、当前学年、学期、年级与体测匹配组别自动推算
- 跟随系统 / 浅色 / 深色外观，设计 token 对齐《BNBU Sports Design System v1.0》
- 设置、当前学生信息、退出登录、版本信息

## 数据与后端对齐

App 的学生可见流程使用真实学生 API。Debug 默认连接 IP:82 测试服，Release 必须显式注入正式 HTTPS 地址；本地 Mock 仅用于自动化测试。模型命名与字段语义以三端共用 OpenAPI 为准：

- `Course`
- `StudentProgress`
- `CourseTask`
- `CheckInRecord` / `ReviewRecord` 视角
- `Membership`
- `GradeRow`
- `ProofAttachment`
- `CheckInDraft`

登录 Token 只由 Keychain 保存；工作台缓存和打卡草稿由 `Core/AppLocalStore.swift` 写入应用私有、完整文件保护且排除云备份的存储，并按 API Base URL 与学生账号隔离。退出或鉴权失效会清除当前账号的 Token、缓存和未提交草稿。

`Core/RemoteStudentRepository.swift` 已接入学生登录、体育总览、课程、打卡记录、凭证上传、免测申请、运动身份和通知接口。远程提交只有在服务器确认成功后才展示成功状态；断网、超时、服务器错误、字段变化与 token 失效均有学生可理解的反馈。

## 构建与门禁

正式候选优先在 Mac 的 `ios-app` 目录执行一条完整门禁（尖括号内容必须替换）：

```bash
./scripts/run-macos-release-gate.sh \
  --release-api-base-url 'https://<学校确认的正式域名>/api/v1'
```

需要单独调试 Xcode 时再使用下面的底层命令：

```bash
xcodebuild -project ios-app/BNBUStudent.xcodeproj -scheme BNBUStudent -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

UI smoke test bundle 编译：

```bash
xcodebuild -project ios-app/BNBUStudent.xcodeproj -target BNBUStudentUITests -configuration Debug -sdk iphonesimulator build
```

当本机 Xcode SDK 与已安装 Simulator runtime 匹配时，可运行：

```bash
xcodebuild test -project ios-app/BNBUStudent.xcodeproj -scheme BNBUStudent -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Bundle ID:

```text
edu.bnbu.student.mvp
```

## 当前可证明的验证状态

- Windows 静态契约审计已覆盖 API、任务 fail-closed、缓存隔离、Keychain、ATS、隐私清单、上传临时文件、Release 配置及 XCTest 回归点。
- 当前源码包含 48 个 XCTest 方法和 5 个 UI Test 方法；**它们尚未在本轮当前源码上通过 Mac/Xcode 实际执行，因此不能写成已通过**。
- Debug clean build、XCTest、XCUITest、无签名 Release build/analyze 必须由 `run-macos-release-gate.sh` 七步全部 PASS 才算完成；签名 Archive 与 iPhone 真机仍需另行验收。
- 打卡记录学生 UI 已在静态契约中禁止审核筛选、审核状态和教师反馈；真实私有 COS 图片仍需用同一 `recordId` 在 Edge、Android 真机和 iPhone 真机共同读回。

## 2026-07-15 当前前端口径

负责人确认 iOS 学生端以 `BNBU-Sports-Android-week2/app` 的 Compose 源码为前端对齐基准。当前已经统一五栏导航、18pt 页面边距、单层中文标题、官方 BNBU 校徽、首页通知、当前/历史课程、`提交 / 记录` 两段式打卡、成绩页和个人中心结构。

以下“第 N 轮迭代”为历史开发记录。若历史记录中的任务页、审核筛选、补材料、底栏 badge、个人页调试/同步面板等描述与当前口径冲突，以本节和 `WEEK3_ANDROID_IOS_ALIGNMENT_AUDIT_20260715.md` 为准；这些开发者或旧审核入口已经从当前学生 UI 移除。

## 第二轮迭代

- 课程卡片可进入教学班详情，展示 Section、老师、截止时间、课程相关缺口和本教学班任务
- 打卡任务支持按 `全部 / 课程相关 / 其他运动` 筛选
- 提交打卡新增图片 / 视频凭证区域，并校验至少 1 个凭证
- 打卡记录支持状态筛选，并可进入记录详情查看凭证数量、老师反馈和学生说明
- 通知可进入详情并标记为已读
- 新增 `StudentAPIClient`，预留学生端 API 请求路径：登录、体育总览、打卡记录、运动身份、通知

## 第三轮迭代

- 新增 `AppLocalStore`，使用 `UserDefaults` 持久化学生工作台、通知已读状态、提交后的本地记录与打卡草稿
- `CheckInRecord` 增加 `proofFiles`，记录详情可展示具体图片 / 视频凭证文件
- 提交页接入 SwiftUI `PhotosPicker`，支持从相册选择图片/视频；保留“拍摄占位”按钮，方便模拟器完整走提交审核流程
- 提交页支持保存、恢复、清空本地草稿；提交成功后自动清理草稿
- 设置页展示未读通知数、打卡草稿状态，并提供“重置本地演示数据”入口
- 新增验证截图：
  - `ios-app/build/screenshots/06-record-proof-files.jpg`
  - `ios-app/build/screenshots/07-profile-settings-local-state.jpg`

## 第四轮 Debug / 优化

- 修复课程详情的相关记录过滤：教学班详情只展示属于该 Section 的课程记录，不再混入无课程归属的组织抵扣记录
- 修复提交时长边界：提交页 Stepper、展示文案、草稿保存和最终提交均统一使用 `min(task.hours, dailyLimit)`，例如 1.5h 任务不能提交 2h
- 清理旧的未使用凭证占位组件，避免后续误读实现状态
- 新增设置页“本地调试”面板，展示活跃任务、本地记录、待审核记录、需补材料、草稿凭证和 Bundle ID
- 调整 Debug 构建配置 `ONLY_ACTIVE_ARCH = NO`，消除命令行 target build 的 active arch 警告
- 已扫描本次运行日志，无 App 级 crash/fatal/exception；仅存在 iOS Simulator 系统级 WebKit/WebCore accessibility duplicate class 提示
- 新增验证截图：
  - `ios-app/build/screenshots/08-debug-panel.jpg`

## 第五轮迭代

- 新增补材料闭环：`需补材料` 与 `被驳回` 记录可在打卡记录页直接进入补交模式
- 补交材料会合并新凭证、更新原记录状态为 `待审核`，并新增“补充材料已提交”通知
- 首页新增“待处理”面板，汇总需补材料、待审核、未读通知，学生可以一眼看到要处理的事项
- 底部 Tab 增加 badge：打卡显示待处理记录数，我的显示未读通知数
- 通知区域新增“全部已读”，可一次性清空未读状态并持久化到本地
- 新增验证截图：
  - `ios-app/build/screenshots/09-supplement-resubmitted.jpg`
  - `ios-app/build/screenshots/10-notifications-read.jpg`

## 第六轮迭代

- 新增本地同步准备面板：展示当前数据源、API Base URL、待同步操作数、最近本地操作和操作队列
- 新增 `SyncOperation` 模型，记录提交打卡、补交材料、通知已读和重置数据等本地操作，为后续替换真实网络 repository 做准备
- 记录详情页支持直接发起“补交材料 / 重新提交材料”，学生看完老师反馈后可一键进入对应补交表单
- `StudentAPIClient` 新增补交材料接口占位和 `SupplementSportRecordRequest`
- 已验证详情页重新提交入口、补交提交、记录状态更新、同步队列展示
- 新增验证截图：
  - `ios-app/build/screenshots/11-record-detail-resubmit.jpg`
  - `ios-app/build/screenshots/12-sync-readiness.jpg`

## 第七轮迭代

- 通知模型新增 `NoticeCategory`，支持截止提醒、审核反馈、组织认证、系统通知分类；旧本地数据会按标题和内容自动推断分类
- “我的”页通知区域新增筛选：全部、未读、截止、审核，通知卡片显示分类图标和标签
- 通知详情页显示通知分类与未读 / 已读状态
- 成绩页新增总分计算面板，展示四项成绩权重、加权贡献和四舍五入后的总分预估
- 记录详情页新增审核进度时间线，清晰展示学生提交、老师审核、最终结果三步状态
- 已验证成绩公式、通知分类筛选、记录审核时间线；构建和模拟器运行通过
- 新增验证截图：
  - `ios-app/build/screenshots/13-grade-formula.jpg`
  - `ios-app/build/screenshots/14-notice-filter.jpg`
  - `ios-app/build/screenshots/15-record-review-timeline.jpg`

## 第八轮迭代

- 首页“待处理”面板新增快捷入口：处理打卡、看通知、看成绩，可直接切换到底部对应 Tab
- 首页新增“本周行动计划”，根据课程相关缺口、补材料、待审核、未读通知自动生成学生下一步行动建议
- AppRoot 将 `TabView` 的选中状态通过闭包传给首页，避免引入额外全局路由
- 已验证首页快捷入口到打卡 / 我的 / 成绩三处跳转；构建和模拟器运行通过
- 新增验证截图：
  - `ios-app/build/screenshots/16-dashboard-action-plan.jpg`

## 第九轮迭代

- 上传凭证面板新增权限状态区：相册显示“仅所选文件”，摄像头显示待授权 / 已允许 / 已拒绝 / 系统限制 / 设备不可用
- 相册继续使用系统 `PhotosPicker`，只读取学生主动选择的图片或视频，不请求完整相册访问
- “拍摄”接入真实摄像头权限链路：首次点击触发系统授权弹窗，允许后进入系统相机；拒绝后可跳转系统设置
- 模拟器或无摄像头设备会提示设备不可用，并保留“添加占位凭证”兜底，方便演示完整提交流程
- 补充麦克风隐私用途说明，用于后续录制视频凭证声音
- 已验证系统摄像头授权弹窗、允许后相机呈现、权限状态更新为“已允许”；模拟器拍照预览未稳定生成最终附件，真机仍需继续验证完整拍摄回填
- 新增验证截图：
  - `ios-app/build/screenshots/17-proof-permissions-camera.jpg`

## 第十轮稳定性 / Debug 优化

- 新增 `LocalStoreHealth`，本地存储可区分工作台 / 草稿的未保存、已读取、解码失败、已丢弃状态
- `AppLocalStore` 的读写结果不再完全静默：写入工作台、保存草稿、清理草稿、重置演示数据都会更新最近读写状态
- App 启动时如遇旧版本或损坏的 `UserDefaults` 数据，会回退到 mock 工作台，并在 Debug 面板显示解码失败原因
- `AppState` 新增数据完整性自检：课程 / 任务 / 记录 ID 重复、任务课程引用失效、记录课程引用失效、草稿任务失效都会显示到本地调试面板
- “我的 - 本地调试”新增数据完整性、工作台存储、草稿存储、最近写入和最近本地事件，方便后续接真实 API 前定位状态问题
- 已验证命令行构建、模拟器安装启动、登录后 Debug 面板渲染；运行日志无 App 级 crash/fatal/exception
- 新增验证截图：
  - `ios-app/build/screenshots/18-debug-store-health.jpg`

## 第十一轮稳定性 / UI 回归

- 新增 `BNBUStudentUITests` UI 测试 target，包含 `BNBUStudentSmokeUITests`
- UI smoke 覆盖演示登录、首页、课程、打卡、成绩、我的、Debug 面板和数据完整性状态
- App 新增 `-ui-testing-reset` 启动参数，测试启动时清空本地 `UserDefaults`，避免手动演示数据污染回归结果
- 为登录按钮、五个底部 Tab、五个根页面和 Debug 面板补充稳定 accessibility identifiers
- 已验证 App target 与 UI test target 均可编译；当前机器 Xcode 26.5 SDK 与 iOS 26.4 Simulator runtime 不完全匹配，`xcodebuild test` 精确运行需等本机安装匹配 runtime 后执行
- 已用 Simulator 手动 smoke 验证同一条路径：登录、切换课程 / 打卡 / 成绩 / 我的、滚动到 Debug 面板；运行日志无 App 级 crash/fatal/exception
- 新增验证截图：
  - `ios-app/build/screenshots/19-ui-smoke-debug-anchor.jpg`

## 第十二轮凭证规则 / 提交确认

- 新增 `ProofUploadRule`，集中定义凭证数量和大小限制：最多 6 张图片 + 1 个视频，图片不超过 8MB，视频不超过 100MB，并在提交前统一校验
- 凭证面板展示上传规则、剩余名额、相册 / 摄像头权限状态和操作反馈，避免学生不知道为什么按钮不可用
- 凭证列表改为预览卡片，展示文件名、类型、大小、来源和“可提交 / 超限”状态；超限凭证会阻止提交
- Debug 构建新增“添加演示凭证”按钮，方便 Simulator、评审和 UI 回归不依赖真实相册文件；Release 构建不会包含该入口
- 提交打卡前新增确认弹窗，明确任务、小时数、凭证数量以及“进入老师审核队列”的后果
- 已验证 App target 与 UI test target 均可编译；已用 Simulator 走通登录、任务提交、添加演示凭证、提交确认、待审核记录生成；运行日志无 App 级 crash/fatal/exception
- 新增验证截图：
  - `ios-app/build/screenshots/20-proof-rules-preview.jpg`
  - `ios-app/build/screenshots/21-submit-confirmation.jpg`
  - `ios-app/build/screenshots/22-record-pending-after-proof.jpg`

## 第十三轮关键前端收尾

- 凭证选择体验继续打磨：图片 / 视频会生成缩略图预览，视频凭证展示时长；图片超过 8MB、视频超过 100MB、图片超过 6 张或视频超过 1 个都会在提交前拦截
- 凭证删除新增二次确认，提示删除后不会随本次打卡提交，避免误删材料
- 相册导入会在后台读取必要的本地元数据，避免大文件先进入重处理；摄像头路径继续保留系统权限链路和模拟器占位凭证
- 完善空状态和异常状态：无任务、无可提交任务、无课程、无通知、无校队 / 社团认证、任务已关闭、本地草稿 / 工作台数据损坏恢复都有明确 UI
- 首页风险提示修正空数据场景，不会把“其他运动缺口”误判成组织认证已覆盖
- 新增 `EmptyStudentRepository` 与 `-ui-testing-empty-state` 启动参数，方便评审和 UI 回归直接查看空状态
- UI smoke case 扩展到提交草稿、正式提交、补材料、通知已读、退出登录和空状态；新增 `BNBUStudentTests` 单元测试 target，覆盖凭证规则、小时数裁剪、本地存储损坏恢复和过期草稿丢弃
- 已验证 App target、UI test target、unit test target 均可编译；当前本机 Xcode 26.5 SDK 与 iOS 26.4 Simulator runtime 不完全匹配，`xcodebuild test` 需要安装匹配 runtime 后再跑完整自动化
- 已用 Simulator 手动验证：凭证缩略图、删除确认、关闭任务不可提交、空课程、空任务、空提交页、空认证、空通知；运行日志无 App 级 crash/fatal/exception
- 真机仍建议补充复测：首次摄像头授权、拍照 / 录像回填、相册完整 / 限制 / 拒绝路径，以及大图片 / 视频选择后的内存和耗时表现
- 新增验证截图：
  - `ios-app/build/screenshots/23-proof-thumbnail-delete-ready.jpg`
  - `ios-app/build/screenshots/24-proof-delete-confirmation.jpg`
  - `ios-app/build/screenshots/25-closed-task-disabled.jpg`
  - `ios-app/build/screenshots/26-empty-dashboard-risk.jpg`
  - `ios-app/build/screenshots/27-empty-submit-state.jpg`
  - `ios-app/build/screenshots/28-empty-profile-state.jpg`

## 第十四轮真机验证状态

- 已检测到真机：`LABYR1NTH的iPhone`，iOS `26.4.2`，UDID `00008150-000260523438401C`
- 当前 CoreDevice 状态为 `unavailable / offline`，详情显示 `pairingState: paired`、`tunnelState: unavailable`、`ddiServicesAvailable: false`
- 已完成 iPhoneOS 真机架构编译校验：`BNBUStudent` 使用 `iphoneos26.5` SDK 编译到 arm64 成功，产物位于 `ios-app/build-device/Debug-iphoneos/BNBUStudent.app`
- 当前 Mac Keychain 中没有可用 Apple Development 证书：`security find-identity -v -p codesigning` 返回 `0 valid identities found`
- 因此本轮还不能完成“安装到真机并操作系统权限弹窗”的最终验证；需要先完成设备可用状态和开发者签名
- 继续真机验证前请确认：
  - iPhone 已连接到 Mac、保持解锁，并在系统弹窗中选择“信任此电脑”
  - iPhone 已开启“设置 > 隐私与安全性 > 开发者模式”
  - Xcode 已登录 Apple ID，并为 `BNBUStudent` target 选择可用 Team，生成 Apple Development 证书 / provisioning profile
  - Xcode Components 中已安装与当前 Xcode / 设备匹配的 iOS platform 支持
- 设备和签名准备好后，需继续实测：
  - 摄像头真实拍照回填
  - 摄像头真实录像回填与 100MB 视频大小限制
  - 相册完整访问 / 限制访问 / 拒绝访问
  - 权限拒绝后跳系统设置再授权
  - 大图片、大视频选择后的缩略图生成、时长读取和页面响应

## 第十五轮服务器对接合并

- 合并 `对接/BNBUStudent-iOS-Source-v0.2.0.zip` 的远程服务器模式，但保留当前已完成的前端、凭证、空状态和测试改动
- 新增 `RemoteStudentRepository`，支持 async/await HTTP 请求、Bearer token、refresh token、工作台同步、提交打卡、补材料、通知已读和凭证 multipart 上传
- 登录页新增“连接到服务器”模式，默认仍保留“学生演示登录”，避免评审时被服务器依赖阻塞
- 默认服务器地址为 `http://127.0.0.1:8080/api/v1`
- 负责人补充的服务器运行方式：后端机器进入 `d:/BNBU/server` 后执行 `npm run dev`
- 负责人补充的测试账号：
  - 学生账号及密码已从文档移除；仅使用密码管理器或环境变量提供的专用 QA 账号，登录页不预填真实学号
  - 管理员账号仅用于 Web 管理端，不作为 iOS 学生端主流程
- 支持用启动参数覆盖服务器地址：

```bash
xcrun simctl launch booted edu.bnbu.student.mvp --args -server-base-url http://你的服务器IP:8080/api/v1
```

- 也支持用环境变量覆盖：

```bash
BNBU_API_BASE_URL=http://你的服务器IP:8080/api/v1 xcodebuild ...
```

- 新增 `BNBUStudentApp/Resources/Info.plist`，补齐：
  - `NSAppTransportSecurity`
  - `NSAllowsArbitraryLoads`
  - `NSAllowsLocalNetworking`
  - `NSLocalNetworkUsageDescription`
  - 相机 / 麦克风 / 相册权限文案
- 模型层已兼容服务器英文枚举值和本地中文枚举值，例如 `pending / 待审核`、`general / 其他运动`、`active / 进行中`
- `ProofAttachment` 新增非持久化 `uploadData`，远程提交时优先上传原始图片 / 视频数据，不再只传缩略图；草稿持久化仍不会写入大文件
- 设置页“当前数据源”可显示“本地 Mock / 服务器”
- 已验证：
  - App target 构建通过
  - Unit test target 构建通过
  - UI test target 构建通过
  - 生成的 App `Info.plist` 已包含 ATS / Local Network 配置
  - Simulator 登录页默认演示模式正常，服务器登录入口正常，演示登录进入首页正常
- 待与后端同事确认：
  - 学生端 API base 是 `/api` 还是 `/api/v1`
  - 后端是否已实现 `/student/workspace`、`/checkins`、`/checkins/{id}/proofs`、`/notices/read-all`
  - 凭证上传字段名是否固定为 multipart `file`
  - 老师 Web 审核通过后学生端工作台是否能通过 `/student/workspace` 立即刷新
- 新增验证截图：
  - `ios-app/build/screenshots/29-server-login.jpg`

## 第十六轮 NewStuff / M1 三端联通迭代

- 已读取 `NewStuff/BNBU 校园生活平台 · 产品全景文档.md` 与腾讯云宝塔教程，确认当前阶段进入 M1：iOS / Android 接入真实后端 API，三端与后端联调 Debug
- iOS 端默认远程 API Base URL 已从旧本地 `/api/v1` 调整为负责人新文档指定的 `http://123.207.5.70:96/api`
- 保留启动参数和环境变量覆盖能力：

```bash
xcrun simctl launch booted edu.bnbu.student.mvp --args -server-base-url http://你的服务器/api
BNBU_API_BASE_URL=http://你的服务器/api xcodebuild ...
```

- `RemoteStudentRepository` 已对齐新文档学生端接口：
  - `POST /api/auth/login`
  - `GET /api/sport/summary`
  - `GET /api/sport/records`
  - `GET /api/sport/identity`
  - `GET /api/common/notifications`
  - `PUT /api/common/notifications/{id}/read`
  - `POST /api/upload/proof`
  - `POST /api/sport/records`
- 远程工作台加载逻辑从旧的单一 `/student/workspace` 改为聚合 `summary + records + identity + notifications`，再映射回当前 SwiftUI 使用的 `StudentWorkspace`
- 提交打卡的远程路径调整为：先上传凭证到 `/upload/proof` 获取服务器文件引用，再提交 `/sport/records` 并携带 `proof_files`
- 模型层新增线上字段兼容：
  - 支持 `snake_case`，例如 `credit_type`、`student_id`、`record_id`、`submitted_at`
  - 支持 `course / general / organization` 等线上枚举值
  - 支持通知 `isRead / read / readAt` 转换为本地 `isUnread`
  - 支持上传凭证响应只返回 `url / path / storagePath` 的情况
- `Info.plist` 已补充 `123.207.5.70` HTTP 明文访问例外，解决 iOS Simulator 对腾讯云 HTTP API 的 ATS 拦截
- 已验证：
  - `http://123.207.5.70:96/api/health` 在线，返回 `BNBU Sports API` 与 `db: true`
  - App target 构建通过
  - Unit test target 构建通过
  - UI test target 构建通过
  - Simulator 可显示腾讯云服务器地址 `http://123.207.5.70:96/api`
  - `POST /api/auth/login` 使用专用 QA 凭据和 `clientType=mobile` 可成功返回学生 token；凭据不得写入仓库
  - 登录后 `GET /api/sport/summary` 可返回学生课程与学时汇总
  - 登录后 `GET /api/student/exemptions` 可访问，当前测试学生返回空数组
  - 演示登录仍可进入首页，Mock 演示流程未被服务器改造破坏
- 当前注意：
  - 学生 App 登录必须传 `clientType: "mobile"`；不传时后端会拒绝 student 角色
  - 免测真实 POST 会写入服务器数据，本轮只做登录、summary、免测列表只读验证，未直接创建线上免测申请
- 新增验证截图：
  - `ios-app/build/screenshots/30-tencent-api-login-error.jpg`

## 第十七轮免测申请补全

- 成绩页新增“免测申请”模块，覆盖学生端 M1/P1 免测申请入口：
  - 展示免测申请列表、状态、提交时间、证明材料摘要和老师反馈
  - 支持后端已确认的 `待审核 / 已通过 / 已驳回` 状态
  - 后端暂不支持免测补材料；被驳回后引导学生重新提交新申请
- 新增免测申请表单：
  - 申请项目：`800 米耐力跑免测`、`1000 米耐力跑免测`
  - 申请原因、情况说明
  - 复用现有图片 / 视频凭证组件，支持相册、摄像头、演示凭证、缩略图、删除确认、大小 / 数量限制提示
  - 提交前二次确认，提交后进入待审核状态
- 模型层新增 `ExemptionApplication`、`ExemptionItem`、`ExemptionStatus`，并挂入 `StudentWorkspace.exemptions`
- 本地 Mock 新增“已驳回”的 800 米免测申请样例，方便评审查看老师反馈和重新申请提示
- AppState 新增：
  - `submitExemption(...)`
  - 本地保存、通知插入、同步队列记录
- 远程层已按后端负责人确认的契约对接：
  - `POST /api/student/exemptions`
  - `GET /api/student/exemptions`
  - 请求体字段为 `type`、`reason`、`proofFiles`
  - `type` 取值为 `800m` 或 `1000m`
  - 后端无 `/api/student/exemptions/{id}/supplements`，免测补材料远程路径不再调用
- 单元测试新增：
  - 本地提交免测申请后创建待审核记录
  - 后端免测申请 payload 解码
- 已验证：
  - App target 构建通过
  - Unit test target 通过
  - Simulator 演示登录进入成绩页，免测入口和申请表单可见
- 新增验证截图：
  - `ios-app/build/screenshots/31-exemption-panel.jpg`
  - `ios-app/build/screenshots/32-exemption-form.jpg`

## 第十八轮后端契约修正 / 真实登录验证

- 根据后端负责人最新确认更新 iOS 契约：
  - 登录请求体改为 `account`、`password`、`clientType: "mobile"`
  - 登录页只显示通用输入提示，不预填账号或密码
  - 免测提交请求体改为 `type`、`reason`、`proofFiles`
  - 免测类型限定为 `800m / 1000m`
  - 免测无补材料接口，前端不再展示补材料按钮
- 更新凭证规则：
  - 最多 6 张图片 + 1 个视频
  - 图片不超过 8MB，视频不超过 100MB
  - 打卡与免测提交层均复用同一份 `ProofUploadRule` 校验
- 修复真实登录后 `/sport/summary` 不返回学生姓名导致首页显示 fallback 名称的问题；现在登录 user 会参与后续 workspace 合成
- 已验证：
  - 真实后端登录成功，返回 student token
  - 登录后首页显示服务器返回的当前 QA 学生资料（历史个人信息已脱敏）
  - `GET /api/sport/summary` 返回 16h / 20h 学时数据
  - `GET /api/student/exemptions` 返回空数组，成绩页免测模块显示 `未申请`
  - 未把 COS SecretId / SecretKey 写入 iOS 代码或文档；iOS 端仍通过后端中转上传
  - App target 构建通过，`BNBUStudentTests` 全部通过
- 新增验证截图：
  - `ios-app/build/screenshots/34-remote-login-exemptions-empty.jpg`

## 第十九轮真实写入链路验证

- 已按真实服务器接口补齐 iOS 写入链路：
  - 凭证上传使用 `POST /api/upload/proof`
  - multipart 字段名实测为 `files`，不是旧猜测的 `file`
  - 上传响应实测返回 `urls: [String]`，iOS 已兼容 `url / urls / path / storagePath`
  - 免测申请使用 `POST /api/student/exemptions`，请求体为 `type`、`reason`、`proofFiles`
  - 体育打卡使用 `POST /api/sport/records`，提交后状态进入 `待审核`
- 真实后端写入验证结果：
  - 上传凭证成功，服务端返回 `/uploads/1782973342744-jxf3a2.jpg`
  - 免测申请写入成功，记录 ID：`ex-1782973379583-ms6q5c`
  - 体育打卡写入成功，记录 ID：`sr-1782973536035-5wvg4n`
  - `GET /api/student/exemptions` 与 `GET /api/sport/records` 均可读回上述记录
- 已同步修正模型层容错：
  - 免测 `proofFiles` 支持服务器返回字符串 URL 数组
  - 打卡 `proofFiles` 支持服务器返回字符串 URL 数组
  - 打卡 `hours` 支持服务器返回字符串数字，例如 `"0.5"`
  - 免测状态以 `待审核 / 已通过 / 已驳回` 为准，不再使用免测补材料状态
- 当前服务器上已创建 2 条 iOS 联调测试数据，备注中均标注“iOS联调测试”，老师端 / 后端可忽略或清理：
  - 免测：`ex-1782973379583-ms6q5c`
  - 打卡：`sr-1782973536035-5wvg4n`
- 安全边界：
  - iOS 端不保存 COS SecretId / SecretKey
  - App 只上传文件到后端，由后端中转到对象存储
- 已验证：
  - App target 构建通过
  - generic iOS Simulator build 通过
  - `BNBUStudentTests` 全部通过

## 第二十轮测试服对接配置收口

- 已读取 `../iOS服务器对接手册.md`，确认当前应使用两套环境：
  - 测试服：`http://123.207.5.70:3333/api`
  - 生产服：`http://123.207.5.70:96/api`
- iOS 端网络配置更新：
  - Debug 构建默认连接测试服 `:3333`，可安全做登录、上传、打卡、免测写入测试
  - Release 构建默认连接生产服 `:96`
  - 仍支持启动参数 `-server-base-url` 和环境变量 `BNBU_API_BASE_URL` 覆盖
  - 测试服和生产服 token 分开存储，避免本地 token 串环境
- 按对接手册补齐请求细节：
  - 登录继续使用 `account`、`password`、`clientType: "mobile"`
  - 凭证上传继续使用 `POST /api/upload/proof`，multipart 字段名为 `files`
  - 大文件请求超时统一设置为 60 秒
  - 体育打卡提交补齐驼峰字段 `proofFiles`，并保留旧 `proof_files` 兼容
  - 免测提交继续使用 `type`、`reason`、`proofFiles`
- 安全边界：
  - 后续写入联调只打测试服 `:3333`
  - 生产服 `:96` 只做必要只读验证，不再做提交/上传测试
- 2026-07-02 测试服实测：
  - `GET /api/health` 通过
  - `POST /api/auth/login` 通过
  - `GET /api/sport/summary`、`GET /api/student/exemptions`、`GET /api/sport/records` 通过
  - `POST /api/student/exemptions` 通过，测试记录 `ex-1782986699309-olwtck`
  - `POST /api/sport/records` 通过，测试记录 `sr-1782986700168-8gsxwd`
  - 首次测试时 `POST /api/upload/proof` 返回 `404 Cannot POST /api/upload/proof`
  - 后端修复后 18:22 复测：`POST /api/upload/proof` 返回 200，服务端返回 `/uploads/1782987526180-o3212z.jpg`
  - 含凭证免测提交通过，测试记录 `ex-1782987527070-zmxbnk`
  - 含凭证打卡提交通过，测试记录 `sr-1782987528057-935tq1`
  - `GET /api/student/exemptions` 与 `GET /api/sport/records` 均可读回上述新记录
