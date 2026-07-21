# Week 3 Android / iOS 前端对齐审计（2026-07-15）

## 基准范围

- Android 学生端源码：`BNBU-Sports-Android-week2/app`
- iOS 学生端源码：`ios-app/BNBUStudentApp`
- 对比依据：Compose/SwiftUI 源码优先，截图仅用于视觉复核。
- 不在范围：Android 目录内的后端、压缩包和其他非校园体育项目。

## 已读取的 Android 核心文件

- `feature/shell/AppRootScreen.kt`
- `core/designsystem/Theme.kt`、`Components.kt`、`Shape.kt`、`Type.kt`、`Motion.kt`
- `feature/login/LoginScreen.kt`
- `feature/dashboard/DashboardScreen.kt`
- `feature/courses/CoursesScreen.kt`
- `feature/checkin/CheckInScreen.kt`
- `feature/grades/GradesScreen.kt`
- `feature/profile/ProfileScreen.kt`、`PrivacyPolicyScreen.kt`
- `feature/notifications/NotificationSheet.kt`
- `feature/exemption/ExemptionScreen.kt`
- `feature/scoring/EnduranceScoringScreen.kt`
- `core/model/StudentModels.kt`、`core/state/StudentAppState.kt`

## 本轮已经关闭的差异

1. 根导航改为五栏同顺序，移除 iOS 顶部重复页面标题，底栏加入 Android 式胶囊选中态。
2. 颜色、圆角、边距、卡片和标题层级统一；默认外观改为浅色，保留浅色/深色/跟随系统。
3. 使用 Android 官方 BNBU 矢量校徽作为 iOS 登录、首页和底栏资产。
4. 登录页统一为真实学生登录，不再展示演示/服务器模式切换、API 地址或测试数据说明。
5. 首页模块顺序、通知铃铛与通知弹层统一；删除 iOS 独有的指标宫格、快捷区和重复通知列表。
6. 课程页统一为当前/历史课程结构及事实字段布局。
7. 打卡页统一为 `提交 / 记录`，增加自主运动、1h/2h、运动项目、其他项目、每日一次和媒体记录布局。
8. 成绩页移除免测模块，恢复为纯成绩进度结构。
9. 个人页统一为申请与审核、老师、组织认证和设置；通知迁至首页，免测迁至个人页。
10. 新增隐私政策和耐力跑成绩换算页面。

## 明确不照抄的 Android 旧逻辑

- Android Week 2 源码仍包含打卡/免测补材料端点及 `supplement_required` 等扩展状态；现有 iOS 后端合同明确免测只有 `pending / approved / rejected` 且没有补材料接口，因此 iOS 保留“驳回后重新申请”。
- Android 首页仍有无统一业务含义的三角风险图标；Week 3 任务书要求 Android 删除，iOS 不新增该图标。
- Android Debug API 使用 3334，iOS 继续使用负责人已确认的 3333；这是平台联调配置，不是前端对齐项。

## 尚待联合验收

- 用同一个测试账号、同一组服务端数据，分别截取 iOS 与 Android 的首页、课程、打卡、成绩、通知和个人页，完成最终像素与换行检查。
- 确认测试服是否部署 `POST /api/scoring/convert-endurance`。iOS 已实现页面和服务器解码，不硬编码评分规则。
- Android 端完成三角提示移除后再做首页最终截图签字。

## 自动验证

- iOS 单元测试：24/24 通过。
- iOS UI 冒烟：5/5 通过；新增登录隐私政策与耐力跑入口回归。
- generic iOS Device Debug：通过。
- generic iOS Device Release：通过。
- Xcode Analyze：通过。
- Debug 安全回归：远程缓存已按服务器和学生账号隔离；退出登录本地 Token 立即清理，并避免旧注销请求覆盖新账号会话。
