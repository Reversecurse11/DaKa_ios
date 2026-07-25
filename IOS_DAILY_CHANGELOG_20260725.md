# iOS 每日修改日志（2026-07-25）

## 修改目标

本次修改集中解决中英文切换不完整、英文长文本显示不全、成绩页卡片错位、“我的”页卡片宽度不一致，以及底部导航栏语言与图标显示异常等问题。

## 已完成内容

### 1. 中英文与动态文本

- 新增运行时动态文本、格式化占位符和学时文本的统一本地化方法。
- 首页“当前风险提示”、行动计划、状态标签和剩余学时可随语言切换。
- 打卡页运动状态、开始时间、结束时间、定位状态、可计学时和提交提示完成本地化。
- 成绩页四个成绩构成、计算公式、缺失项、来源追踪和状态完成本地化。
- 课程页学期、学年、选课状态等界面字段完成本地化。
- “我的”页性别、年级、状态、设置项和操作状态完成本地化。
- 补齐字符串目录中的中英文条目，并增加完整性检查。

### 2. 首页与底部导航栏

- 首页风险提示不再强制显示中文。
- 底部导航栏改为系统原生 `TabView`，切换语言后立即更新。
- 禁止 iOS 26 在滚动时自动收起导航文字，避免导航项文字消失或重叠。
- 首页导航图标恢复为原 BNBU 校徽，并设置为适合标签栏的 25pt 固有尺寸。

### 3. 成绩页布局

- 修复英文环境下四个成绩看板高度和内容区域不一致的问题。
- 标题、分数、进度条和说明文字采用稳定的统一布局。
- 长英文说明允许完整换行，不再被固定行数截断。
- 辅助功能大字号下自动切换为单列，避免看板相互挤压。
- 总分计算、加权公式和缺失项区域可在窄屏下自动改为纵向排列。

### 4. “我的”页布局

- 修复“申请与审核”两个入口卡片在中英文环境下宽度不一致的问题。
- 卡片始终占满可用宽度，左右边缘和箭头位置保持一致。
- 个人信息、设置行和导航卡片支持长文本换行。
- 增加中英文卡片位置与宽度的 UI 自动断言。

### 5. 课程、打卡与通用组件

- 课程卡片在大字号下自动切换为单列信息布局。
- 打卡详情行根据空间在横向和纵向布局之间自动切换。
- 通用状态标签、信息行和说明文字支持动态本地化及完整换行。
- 新手指引的动态演示内容和辅助功能描述跟随当前语言。

## 自动化测试与验证

- Swift 源码编译检查通过。
- String Catalog 编译及中英文条目完整性检查通过。
- `git diff --check` 通过。
- 本地化模型测试通过，0 个失败。
- 中文核心流程 UI 测试通过。
- 英文导航、风险提示、打卡字段和成绩构成 UI 测试通过。
- 英文六个核心页面截图回归通过。
- 标准字号和辅助功能大字号截图检查通过。
- “我的”页中英文卡片宽度自动测量通过，误差不超过 1pt。

## 当前限制

- 学生姓名、学院、教师、课程名称、组织名称和备注等属于服务端或管理员录入的数据，当前保持原文。
- 若这些业务数据也需要中英文切换，后端接口需提供对应的英文名称字段或稳定的翻译键。

## 涉及文件

- `BNBUStudentApp/Core/Theme.swift`
- `BNBUStudentApp/Features/AppRootView.swift`
- `BNBUStudentApp/Features/CheckInView.swift`
- `BNBUStudentApp/Features/Components.swift`
- `BNBUStudentApp/Features/CoursesView.swift`
- `BNBUStudentApp/Features/DashboardView.swift`
- `BNBUStudentApp/Features/GradesView.swift`
- `BNBUStudentApp/Features/ProfileView.swift`
- `BNBUStudentApp/Features/StudentExperienceViews.swift`
- `BNBUStudentApp/Resources/Assets.xcassets/bnbu_emblem.imageset/bnbu_emblem.svg`
- `BNBUStudentApp/Resources/Localizable.xcstrings`
- `BNBUStudentTests/BNBUStudentModelTests.swift`
- `BNBUStudentUITests/BNBUStudentSmokeUITests.swift`
