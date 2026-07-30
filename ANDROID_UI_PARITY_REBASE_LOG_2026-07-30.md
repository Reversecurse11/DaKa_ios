# Android UI 复刻分支 Rebase 日志（2026-07-30）

## 结果

- 分支：`agent/android-ui-parity-complete-20260729`
- 代码基线：`main@c036229`
- 实际 rebase 目标：`origin/main@87f3223`（比 `c036229` 只多一份 `MAIN_REBASE_GUIDE_20260729.md`，没有额外代码改动）
- Android 实际界面仍是唯一视觉基线；本轮没有重新设计页面。
- main 已有实现保持权威，只补入 main 缺少的验证码/账号找回、免测中心和耐力跑换算模块。
- 正式流程不生成本地成功结果，不伪造后端数据。

## 独立功能提交

1. `3c5ff3f Add verification and account recovery screens`
   - 增加邮箱验证码、手机验证码入口和账号恢复页面。
   - 未发布的验证码发送、校验及账号恢复接口保持不可提交，并给出明确说明。
   - 修复账号恢复页面根级辅助功能标识覆盖提交按钮标识的问题。

2. `b712721 Complete exemption application center`
   - 增加免测列表、加载/空/错误状态、详情、创建和补交材料流程。
   - 独立免测 GET 仅在明确 404 时回退到 `sport/summary`；网络、5xx 和解码错误不会伪装成空列表。
   - 正式提交仅接受本机相机现场照片；演示账号不会生成假申请或假补交结果。
   - 同类待审核申请阻止重复提交，不影响另一免测类型。
   - 修复已上传照片在 App 重启后因安全日志移除原始字节而无法继续重试的问题；恢复时仍校验相机来源、图片类型、内容摘要、数量和服务器文件引用。

3. `5b3e130 Complete endurance score converter`
   - 增加 Android 基线样式的耐力跑成绩换算页面。
   - 项目依据学生性别显示 800m / 1000m，结果由现有远程接口返回。
   - 演示账号不执行本地估算，不把客户端结果冒充正式成绩。
   - 同步更新 UI 测试对中文全角冒号文案的断言。

## main 修复保留情况

- 成绩页继续执行负责人确认的口径：学生端不显示总分、总分预估、加权合计和各项权重。
- `DetailViews.swift` 继续使用 `localizedHourText`，中文界面不会显示 `4h`。
- 外观切换继续通过所有 window 的 `overrideUserInterfaceStyle` 生效，没有恢复根视图 `preferredColorScheme`。
- `CourseJoinRequest` 模型及加入申请状态页继续保留，没有重复实现或覆盖。
- 深色模式个人页顶部黑线修复继续保留。
- `scripts/ios-contract-audit.mjs` 保持 main 版本，没有降低或绕过门禁。

## 验证

- iOS Simulator Debug 构建及测试目标编译通过，`CODE_SIGNING_ALLOWED=NO`。
- 103 条 `BNBUStudentTests` 单元测试全部通过。
- 24 条 `BNBUStudentUITests` 全量运行：20 条通过、3 条因未提供真实测试账号按既有条件跳过、1 条旧文案/辅助功能标识断言失败。
- 上述 1 条 UI 失败修复后已单独重跑并通过；本轮没有再次耗时重跑其余已经通过的 20 条。
- `BNBU_BACKEND_ROOT=/Users/louisgan/Desktop/BNBU- Dating/BNBU-Sports-Android-master/backend node scripts/ios-contract-audit.mjs` 全部通过。
- Xcode 26 在 UI 测试诊断收集时输出过 LLDB 版本快照及 `simctl` 诊断警告，但未影响最终通过的测试断言。

未执行的验证：

- 需要 `BNBU_TEST_ACCOUNT`、`BNBU_TEST_PASSWORD`，以及部分用例需要 `BNBU_EXPECT_NOTE` 的 3 条真实后端 E2E。
- 真机上的真实验证码、账号恢复、免测提交和耐力换算端到端验证；相关接口或测试账号尚未提供。

## 仍待后端或产品确认

以下 15 项没有在 iOS 端伪造或自行扩展契约：

1. 邮箱验证码发送与校验接口。
2. 手机验证码发送与校验接口。
3. 账号找回、身份核验和密码/联系方式重置接口。
4. 邀请码查询、课程确认和加入申请接口的最终契约。
5. 联系方式查询、绑定、换绑及验证码接口。
6. 管理员帮助文章接口与离线缓存协议。
7. 问题反馈、附件上传及工单查询接口。
8. App 语言偏好是否需要同步到服务端。
9. 打卡开放时间、统一时区和稳定业务错误码。
10. 校队、社团等组织申请类型、字段、认证状态和抵扣规则。
11. 免测理由采用单字段，还是“摘要 + 详细说明”双字段。
12. 老师审批后的真实 `approved / rejected / supplement_required` 样本及评语读回。
13. 分页、排序、服务器时间、上传容量和稳定错误码的统一约束。
14. 课程相关打卡的运动项目/运动说明规则，以及“补充备注”的服务端字段。
15. main 已有课程加入申请模型和状态页；仍需确认其远程端点、状态载荷及真实返回样本。

## 本地安全保留

- rebase 前提交保留在本地分支 `backup/android-ui-parity-pre-rebase-20260730`。
- Xcode 自动提取产生、但不属于本轮功能的本地化文件改写保留在 `stash@{0}`，没有进入提交。
