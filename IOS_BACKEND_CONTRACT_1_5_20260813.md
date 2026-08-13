# iOS Backend Contract 1.5 接入记录（2026-08-13）

## 可复现基线

- iOS 起点：协作者提交 `27ad986e512377b59efa6bf07b0de35022c7e849`。
- Backend `main` 合并提交：`dac49050ebcf7c07eb6966ed061534128627cf33`。
- Contract：`1.5.0-contract`。
- SHA-256：`f0b4916cb0abd1ec4057f690763de8d7e6f79ca2b7e666a8cd6f3d8c37c69bed`。
- 规模：106 paths、123 operations、279 schemas；106 implemented、17 intentionally disabled、0 not implemented。
- 旧 `1.4.0-contract` 快照仍按原 SHA `c5d18c4894bbe421074cba27da3b39a9076328c499cc742b273665994c29059b` 保存在 `Contracts/history/`。

## 本轮 iOS 变化

- 当前合同快照、生成器、生成模型、构建配置与测试基线全部切换到 1.5 SHA。
- 保存 Backend 1.5 snapshot、release manifest、兼容性报告和客户端 handoff，避免日后从可变 `main` 猜测合同内容。
- GENERAL 运动说明继续必填且不能只含空白；COURSE_RELATED 改为选填，空白在 transport 前归一化为省略/null，不再生成客户端默认说明。
- typed auth controller 增加学生邮箱验证码申请/校验，以及当前用户邮箱首次绑定/换绑请求。
- 保留并复核 QR 入课、权威 Session 与媒体 `initiate → PUT → confirm → bind` 链路；新增 Exercise Record draft/create/get/submit gateway。
- 对视频超过 15 秒、缺少音轨、位置元数据、格式不支持、完整性失败和上传会话过期提供稳定错误码提示，并保留 `requestId`。
- iOS 第一阶段仍不申请定位权限、不采集 GPS；图片和视频继续在上传前清除位置元数据。

## 尚未完成或不可宣称

- Backend 代码和合同已经合并，但 Staging HTTPS Base URL、邮件测试方案、课程/邀请码/运动数据、私有对象存储及实际部署健康状态尚未交付，因此没有真实环境 E2E 证据。
- 当前 SwiftUI/AppState 仍含旧 UI repository 迁移 seam；typed gateway 的合同覆盖不等于所有页面已切换 `/api/v1`。
- 检查时远端尚未看到 `1.5.0-contract` 不可变 Git tag，仓库内 handoff/release 文件仍使用 candidate 命名。iOS 以 merge commit + SHA 固定开发输入，但发布前仍需负责人确认不可变 tag/Release 或等价交付物。
- 真机仍需验证照片/视频重编码后的实际 MIME、容器、音轨、SHA-256、15 秒边界，以及 `MEDIA_LOCATION_METADATA_NOT_ALLOWED` 的服务端复现。

## 后续联调门禁

收到 Staging 信息后，按“邮箱登录 → 入课 → Session → 全部现场媒体上传并绑定 → Record 提交 → 列表读回”的单一数据源闭环执行；失败时记录 iOS 版本、接口、HTTP 状态、稳定错误码、requestId、媒体容器和实际 MIME，不回退旧接口、Mock 或本地假成功。

## 本地验证

- OpenAPI SHA 与 generated models 可重复性门禁通过。
- `scripts/ios-contract-audit.mjs` 通过。
- iPhone 17 Pro / iOS 26.5 Simulator：151 项 XCTest 全部通过，0 failed。
- 未执行 Staging E2E、XCUITest、签名 Archive 或 iPhone 真机媒体验收。
