# main 改动说明（供 `agent/android-ui-parity-complete-20260729` rebase 使用）

日期：2026-07-29
适用分支：`agent/android-ui-parity-complete-20260729`（commit `1caa9f5`）
目标基线：`main`（commit `c036229`）
共同祖先：`ac9df9d`

## 为什么需要这份文档

两条分支都从 `ac9df9d` 出发，各自完成了一遍"以 Android 实际界面为基线的 iOS 复刻"。
`main` 上是 7 个提交、5013 行新增；parity 分支是 1 个提交、12433 行新增。
两边改到的 Swift 文件完全重合——parity 分支动过的 20 个 Swift 文件，`main` 上一个不漏地也动过，
因此无法按文件挑选，只能 rebase。

本文档按文件说明 `main` 做了什么、rebase 时该保留哪一侧，用于减少逐 hunk 判断的成本。

## main 的 7 个提交

| 提交 | 内容 |
| --- | --- |
| `cba9e50` | 设计系统重建在 Android 基线上（颜色、间距、圆角、动效、字号） |
| `964115e` | 各页面语义字号替换为显式字号层级 |
| `7f798a3` | 首页按 Android 基线重排区块结构 |
| `a0c2ca6` | 成绩页按 v6.0 学生端口径重做 |
| `d6a0051` | 补齐 8 个不依赖服务端契约的 Android 页面 |
| `d323c79` | 修 demo 暴露的外观切换与学时格式化问题 |
| `c036229` | 移除个人中心顶部色条（深色模式下呈现为黑线） |

## 逐文件说明

### 设计系统层

**`Core/Theme.swift`（+179）— 建议整体采用 main 侧**

所有 token 都标注了 Android 对应文件，rebase 时按 main 为准，不要与 parity 分支的取值混用，
否则会出现同一页面上两套色阶。

- 颜色改为逐条抄自 Android `Theme.kt`，浅色背景 `0xF2F2F7`、深色背景纯黑 `0x000000`、
  卡片深色 `0x1C1C1E`。补齐了 `onSecondary` / `tertiaryContainer` / `outlineVariant` /
  `surfaceContainerLow|High|Highest` 等原先缺失的槽位。
- 新增 `officialBlue`（`0x0166A4`，BNBU 标识蓝，不随外观切换）与 `overlayBlack`。
- `BNBUSpacing` 改为抄自 Android `Layout.kt`：新增 `space4`…`space32` 阶梯，
  `screen` 由 18 改 20，`panel` 由 16 改 18，`bottomSpacer` 由 40 改 28，
  新增 `touchTarget: 48` 与 `primaryControlHeight: 52`。
- `BNBURadius` 整体上移：`extraSmall` 4→8、`small` 8→10、`medium` 12→14、
  `large` 16→18、`extraLarge` 28→24，新增 `pill`。
- 新增 `BNBUMotion`（时长与按压反馈）与 `BNBUFont`（显式字号层级 + 行距 + 字距）。
  `BNBUFont` 是 `964115e` 的落点，页面里不再出现 `.title2` / `.caption` 这类语义字号。
- 新增 `BNBUAppearanceMode.interfaceStyle` 与 `applyToWindows()`，见下方"必须保留的三处修复"。

### 组件层

**`Features/Components.swift`（+427）— 建议整体采用 main 侧**

以下 8 个类型在 `ac9df9d` 上不存在，是 main 新建的，parity 分支若有同名实现会重复声明：

`BNBUPressStyle`、`BNBUBackRow`、`BNBUGroupLabel`、`BNBUNavigationSettingRow`、
`BNBUSegmentedControl<Value>`、`BNBUFilterChip`、`ValidationPanel`、`StatusMessagePanel`

其中 `BNBUBackRow` 是全站统一的返回栏，`ProfileDetailViews.swift` 与
`JoinRequestStatusView.swift` 都依赖它；`BNBUSegmentedControl` 用于设置页的外观与语言选择。

### 模型层

**`Core/Models.swift`（+150）— 分三块，处理方式不同**

1. **新增 `CourseJoinRequest` + `JoinRequestStatus`（必须保留）**
   对应 parity 日志第 15 条"iOS 当前没有独立的课程加入申请/状态详情接口和模型"——现在有了。
   `JoinRequestStatus` 有四态 `pending / active / rejected / needsCorrection`，
   解码时兼容服务端可能返回的英文同义词与中文字面量。
   `StudentWorkspace` 增加 `courseJoinRequest: CourseJoinRequest?`，旧缓存缺该字段时按 `nil` 兼容。

2. **成绩相关的删除（必须保留删除结果）**
   移除 `GradeRow.resolvedComponents` 与 `unrecordedComponents`。
   依据：负责人在上周周会明确要求学生端成绩页不显示总分与各项权重。
   parity 分支的成绩页仍保留"总分预估""总分计算""加权合计"和权重百分比，需按此口径去掉。

3. **与 parity 分支重叠的部分（择一即可，内容基本一致）**
   `EnduranceRunStatus`（`recorded / exempt / absent / notRecorded`，带同义词兼容）、
   `enduranceRunTimeSeconds / enduranceRunStatus / enduranceRunScore`、
   `gradeCalculatedAt`、`StudentProgress.rawCourse`。
   两边都实现了，取任一侧都行，但要和各自页面的调用保持一致。

**`Core/AppState.swift`（+6）**
仅一处：`submitCourseJoinRequest(rawCode:)` 开头加了 `guard isAuthenticated else`，
未登录时不发申请，与 Android 行为一致。门禁有对应规则。

**`Core/MockStudentRepository.swift`（+59）/ `RemoteStudentRepository.swift`（+2）**
增加 `courseJoinRequest` 的 mock 构造（可通过启动参数切到 rejected / needsCorrection / pending
三种状态用于 UI 测试）。另修了一条 mock 文案 `差课程 4h` → `差课程 4 小时`。

### main 新增的三个文件（parity 分支上不存在）

**`Features/AppShellViews.swift`（661 行）**

Android `AuthUiState` 的启动流程。parity 分支把等价功能写在 `AppRootView.swift` 与
`LoginView.swift` 里，rebase 时需要二选一，不能两套并存。

- `BNBUDevicePrivacyConsent`：设备级隐私同意，带策略版本号，换版本会重新询问。
- `BNBUPreLoginGuide`：登录前加课引导是否看过。
- `AppShellStage`：`restoring → privacyConsent → preLoginGuide → login → authenticated`。
  提供 `AppShellStage.resolved(...)`，在 `BNBUStudentApp.init` 内同步定档，
  避免首帧闪一下 splash 导致 UI 测试取不到 tab 的 accessibility identifier。
- `AppShellView` / `AuthenticatedShellView` / `StartupSplashView` /
  `PrivacyConsentView` / `PreLoginCourseGuideView` / `BNBUGuideFlow` / `BNBUGuideArtwork`。
- 隐私文案按 iOS 实际行为改写：声明麦克风用途（`NSMicrophoneUsageDescription`），
  通知说明为本地通知，不提 Firebase Cloud Messaging。

**`Features/ProfileDetailViews.swift`（435 行）**

个人中心拆出来的下级页面，parity 分支把这些写在 `ProfileView.swift` 内。

`AccountDetailsView`、`ProfileSettingsView`（账户与安全 / 偏好设置 / 帮助与支持 / 退出登录
四组，顺序有门禁规则约束）、`AboutView`、`ChangelogView`、`BNBUAppVersion`。
联系方式绑定与问题反馈两行置灰，副标题写明"接口发布后开放"，不伪造可用状态。

**`Features/JoinRequestStatusView.swift`（301 行）**

对应 Android `JoinRequestStatusScreen`。含 `JoinRequestEntryPanel`（首页与课程页共用的入口卡片）
及 pending / needsCorrection / rejected / 入口不可用 / 申请不可用五种面板。
首页与课程页都引用了 `JoinRequestEntryPanel`，门禁检查它在首页区块顺序中的位置。

### 页面层

**`Features/GradesView.swift`（+533/-533）— 建议整体采用 main 侧**

按 v6.0 学生端口径重做，只保留耐力跑成绩与打卡学时完成度。
新增 `EnduranceRunCard`、`CheckInHoursCard`、`GradeCardTitle`、`GradeHourBreakdown`、
`GradeHourFormatter`、`GradeTimeFormatter`；
删除 `GradeWeightFormatter`、`GradeComponentCard`、`GradeContributionRow`。
门禁有 6 条规则钉死这一口径（禁止 `resolvedComponents`、`GradeWeightFormatter`、
`weightedTotal`、`grades.total`、客户端默认权重表，并要求区块顺序）。

**`Features/DashboardView.swift`（+807/-807）— 建议整体采用 main 侧**

按 Android 基线重排区块：`header → todayCheckInPanel → JoinRequestEntryPanel →
courseJoinEntryPanel → ExerciseResumePanel → progressOverview → progressBreakdown`，
门禁有顺序规则。
新增 `DashboardJoinEntry`、`HomeCard`、`HomeStatusPill`、`HomeProgressBar`、
`NotificationBell`、`CheckInWindowStatusRow`、`ExerciseResumePanel`、`ProgressMetric`、
`DashboardFactRow`；删除 `FocusPlanItem` / `FocusPlanRow` / `ActionMiniMetric` /
`DashboardShortcutButton` / `ProgressLine`。

另外修了一个通知竞态：原先用 `NavigationLink` + `simultaneousGesture` 标记已读，
一旦该通知从筛选列表中消失，导航状态会错乱。改为 `Button` 设置 `openedNotice` 再标记已读，
配合 `navigationDestination(item: $openedNotice)`。门禁禁止 `simultaneousGesture(TapGesture(`
出现在首页。

**`Features/ProfileView.swift`（+328/-328）**

设置面板整体移出到 `ProfileDetailViews.swift`，页面本身只剩资料卡与快捷服务，
顶部齿轮进设置、资料卡进账户详情。
删除了顶部的 `.safeAreaInset(edge: .top) { BNBUTheme.background.frame(height: 2) }`，
详见下方"必须保留的三处修复"。

**`Features/CoursesView.swift`（+75）**

待审核课程列表位置改为渲染 `JoinRequestEntryPanel`。
原先两个独立的 `@State` sheet 开关（加入课程 / 申请状态）合并为单个枚举驱动的 sheet，
避免两个 `.sheet` 互相抢占。

**`Features/DetailViews.swift`（+56）**

4 处 `.hourText` 改为 `.localizedHourText`，见下方"必须保留的三处修复"。

**`Features/CheckInView.swift`（+101）、`CourseJoinViews.swift`（+21）、
`StudentExperienceViews.swift`（+50）、`ExerciseCaptureComponents.swift`（+18）、
`LoginView.swift`（+23）、`AppRootView.swift`（+3）**

主体是字号与间距对齐（`964115e`）产生的改动，量小、机械，但有两处需要注意：

原生 `Picker(...).pickerStyle(.segmented)` 统一换成了 `BNBUSegmentedControl`
（`CheckInView.swift` 里的"运动/记录"分段与"运动类型"分段都在此列），
换的同时给每个分段挂了 accessibility identifier，UI 测试依赖这些 id。

`LoginView.swift` 另有一处逻辑改动：`BNBUPrivacyConsent.hasAccepted(account:)` 先检查
`BNBUDevicePrivacyConsent.hasAccepted()`，避免设备级隐私门通过后登录页再问一次。
`AppRootView.swift` 被 `AppShellViews.swift` 接管，只保留 `AppRootView` 本体。

**`BNBUStudentApp.swift`（+50）**

- `WindowGroup` 内容换成 `AppShellView(isUITesting:stage:)`，
  `shellStage` 用 `AppShellStage.resolved(...)` 在 `init` 中同步定档。
- 移除 `.preferredColorScheme(...)`，改为在 `onAppear`、`onChange(appearanceModeRaw)`
  和 `scenePhase == .active` 三处调用 `appearanceMode.applyToWindows()`。
- `-ui-testing-reset` 增加清理 `BNBUDevicePrivacyConsent` 与 `BNBUPreLoginGuide`。

### 资源与工程文件

**`Resources/Localizable.xcstrings`（+1182）**
新增页面的中英文条目，以及补齐教师相关提示的英文翻译。
另外把 `BNBU SPORTS` 与 `PE1024` 从字符串表移除——品牌名改用 `Text(verbatim:)`，
否则英文模式下会被当作待翻译文案。

**`BNBUStudent.xcodeproj/project.pbxproj`（+12）**
注册 `AppShellViews.swift`、`ProfileDetailViews.swift`、`JoinRequestStatusView.swift`。
rebase 时这个文件容易冲突，冲突后请确认这三个文件仍在 `BNBUStudent` target 的
Sources 构建阶段里，否则会报"类型找不到"这类误导性错误。

### 测试与门禁

**`BNBUStudentTests/BNBUStudentModelTests.swift`（+274）**
新增：加入申请四态解码、工作区缓存对 `courseJoinRequest` 的读写与旧缓存兼容、
设备级隐私同意的版本化、未登录时不得提交加入申请、启动阶段的同步定档。

**`BNBUStudentUITests/BNBUStudentSmokeUITests.swift`（+414）**
新增启动门流程、个人中心三级页面导航、外观切换后设置页重绘（用截图平均亮度断言）、
若干临时截图用例。
`tabButton` 辅助方法增加了按位置兜底：identifier 找不到时退回 `element(boundBy:)`，
解决 tab identifier 在阶段切换后偶发取不到的问题。

**`scripts/ios-contract-audit.mjs`（+189）**
parity 分支没有动过这个文件，rebase 后会直接生效。新增规则涉及：
成绩页区块顺序与禁用项、首页区块顺序、启动门顺序、隐私同意版本化、
未登录不得提交加入申请、设置页分组顺序、外观应用到 window、
禁止 `.hourText`、禁止 `preferredColorScheme`、禁止钉在安全区的背景色条、
三个新文件必须注册进工程。

跑法：

```bash
cd ios-app
BNBU_BACKEND_ROOT=/path/to/BNBU-Sports-Android-week2/backend \
  node scripts/ios-contract-audit.mjs
```

脚本是 fail-fast 的，一次只报第一条，修完再跑。

## 必须保留的三处修复

这三处是 2026-07-29 晚间 demo 现场被负责人看到的问题，rebase 时不要被覆盖回去。

**1. 中文界面显示 "4h"**

`DetailViews.swift` 中 4 处 `.hourText` 改为 `.localizedHourText`
（`progress.course.hourText`、`courseRemaining.hourText`、`record.hours.hourText`）。
`.hourText` 是硬编码英文后缀。门禁规则会扫描整个 `Features/` 目录拒绝 `.hourText`。

parity 分支现状：`DetailViews.swift` 仍有 4 处 `.hourText`、0 处 `localizedHourText`。

**2. 切换深浅色时设置页不重绘**

根视图的 `preferredColorScheme` 只作用于它所包含的视图树；设置页是以 sheet 形式呈现的，
挂在独立的 presentation controller 上，收不到这个修饰符，所以切换外观后它保持原配色直到关闭。
改为 `BNBUAppearanceMode.applyToWindows()` 遍历 `connectedScenes` 的所有 window
设置 `overrideUserInterfaceStyle`。
测试 `testAppearanceSwitchRepaintsThePresentedSettingsSheet` 通过截图平均亮度断言。

parity 分支现状：`BNBUStudentApp.swift:131` 仍是 `preferredColorScheme(appearanceMode.colorScheme)`。

**3. 深色模式下的一条黑线**

`ProfileView.swift` 顶部曾有
`.safeAreaInset(edge: .top, spacing: 0) { BNBUTheme.background.frame(height: 2) }`。
深色模式下 `background` 是纯黑 `0x000000`，而卡片是 `0x1C1C1E`，
这条钉在安全区的 2pt 色条就成了一道贯穿屏幕的黑线。已删除，并加了门禁规则禁止该写法。

parity 分支现状：不存在此问题。

## 建议的 rebase 顺序

先落地基础层，再落地页面层，可以显著减少重复判断：

1. `Theme.swift`、`Components.swift` — 取 main 侧，先让 token 和组件唯一。
2. `Models.swift`、`AppState.swift`、两个 Repository — 按上面第 3 节的三块分别处理。
3. 三个新文件与 `AppRootView.swift` / `BNBUStudentApp.swift` / `LoginView.swift` —
   决定启动流程用哪一套实现，不要两套并存。
4. `GradesView.swift`、`DashboardView.swift`、`ProfileView.swift` — 取 main 侧。
5. 其余页面 — 以 parity 分支的功能为主，套用 main 的 token 与字号。
6. `project.pbxproj` — 确认三个新文件在 Sources 构建阶段。
7. 测试文件 — 两边合并，重名用例保留一份。

## 验证

```bash
# 构建
xcodebuild -project BNBUStudent.xcodeproj -scheme BNBUStudent \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build-for-testing

# 全量测试（约 11 分钟）
xcodebuild -project BNBUStudent.xcodeproj -scheme BNBUStudent \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# 门禁
BNBU_BACKEND_ROOT=/path/to/BNBU-Sports-Android-week2/backend \
  node scripts/ios-contract-audit.mjs
```

`main@c036229` 当前状态：118 条测试全部通过，门禁全绿。

## 仍待确认（两条分支共同的开口项）

parity 日志里列的 15 条后端/产品开口项，与 iOS 侧此前提给负责人的 OpenAPI 清单基本重合，
本次 rebase 不涉及，等统一接口文档发布后再一并处理。

已有结论的一条：学生端成绩页不显示总分与各项权重（负责人上周周会口径）。
