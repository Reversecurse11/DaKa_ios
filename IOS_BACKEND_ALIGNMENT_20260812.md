# iOS 对齐 Android / Backend 最新规则（2026-08-12）

## 本轮基线

- iOS 基于协作者最新提交 `527a4e6` 开展，变更保存在隔离分支 `client/ios-backend-v1-alignment-2026-08-12/codex`。
- Android 对照版本：`b1254c9`（`master`）。
- Backend 对照版本：`bd2eb36`（`main`）。
- iOS 正式合同仍固定为 tag `1.4.0-contract` 的 SHA-256：`c5d18c4894bbe421074cba27da3b39a9076328c499cc742b273665994c29059b`。
- Backend `main` 当前同样声明 `1.4.0-contract`，但合同 SHA-256 已变为 `079781c04ac201b91026df0b1d391a9abd33d50caee8a7f70b32fc4432553597`，且新增两个邮箱验证 operation。它尚未形成新的不可变版本/tag，因此本轮没有覆盖 iOS 正式快照或重新生成正式模型。

## 已完成的 iOS 改动

- 运动视频最长 15 秒；录像前请求麦克风权限，录像完成后读取真实时长并检查音轨，无音轨或超时视频不进入草稿池。
- 删除 100MB 视频业务上限和 120MB 聚合请求上限，只保留 Backend 公布的 512 MiB 传输安全上限；图片继续执行 8MB 规则。
- 现场照片与视频分开拍摄，禁止相册导入；最多保留 6 张照片和 1 个视频。
- 取消“从草稿中手动选择部分凭证”。最终提交始终包含当前保留的全部现场素材，只有删除草稿才能排除素材。
- 学生登录入口改为邮箱验证码唯一入口，移除手机/SMS 登录入口；账号找回和设置中的联系方式界面改为邮箱唯一。
- 未登录页面和首次启动引导不再开放扫码入课；入课入口移动到登录后的课程空状态。
- 移除学生端耐力跑成绩录入/换算入口，成绩页继续展示服务端结果。
- 修复 `-ui-testing-empty-state` 被完整 Mock workspace 覆盖的回归。
- 图片上传前统一解码并重新编码为 JPEG，不携带原文件的 EXIF、GPS 或其他属性字典。
- 视频不再原样复制上传；统一重新导出，并应用系统 sharing metadata filter 和空输出 metadata，移除 QuickTime 位置等用户识别信息。导出后仍校验真实时长和音轨。

## 尚未宣称完成的事项

- AppState 的正式数据源仍未全面切换到现有 `/api/v1` typed gateways；旧 `RemoteStudentRepository` 中仍存在历史 `student/*`、`common/*` 路径。正式联调前必须按业务闭环完成迁移，不能把本轮 UI/规则对齐描述成“iOS 已全面接入 `/api/v1`”。
- 新增的当前用户邮箱首次绑定/换绑 operation 仅存在于 Backend `main` 候选合同中；等待 `1.5.0-contract` 正式版本、tag 和 hash 后再生成 iOS 类型并接入真实请求。
- 当前录像由系统相机完成 15 秒限制、压缩输出与重拍；尚未实现 Android 同等的自定义暂停/继续录像界面。正式媒体联调还需真机验证导出容器、音轨、MIME、SHA-256 与 Backend worker 的一致性。
- 仍没有获批且可访问的 iOS Staging HTTPS Base URL，本轮只完成编译、Mock 和本地合同回归。

## 负责人确认后的冻结边界

1. `1.4.0-contract` 永久固定为 122 operations、275 schemas 和 SHA-256 `c5d18c4894bbe421074cba27da3b39a9076328c499cc742b273665994c29059b`。Backend `main` 的 `079781…3597` 变化必须作为新的 `1.5.0-contract` 发布；新包到达前不得覆盖当前快照和 generated types。
2. 最终说明规则是 GENERAL 必填、COURSE_RELATED 选填，并由 Backend 负责课程运动的默认描述。由于 1.4 合同和当前运行校验仍要求非空，iOS 现阶段继续对两类运动都执行必填，不引入长期客户端默认字符串；待 1.5 正式包发布后再切换。
3. iOS 第一阶段不申请定位、不采集或上传 GPS。Backend 当前会拒绝含 GPS、EXIF 或容器位置元数据的媒体，因此客户端上传前显式清洗图片和视频元数据，且不把位置用于时长、审核或成绩。
4. 当前只能称为“1.4 冻结基线上的 iOS 预适配与本地回归”，不能称为全面切换 `/api/v1` 或真实联调完成。
5. 等待后端同时交付 1.5 不可变交接包和可访问 Staging：HTTPS `/api/v1` Base URL、部署 commit/合同 SHA、专用合成学生与测试邮箱、真实邮件投递、课程邀请码与运动数据、私有对象存储签名上传、requestId 排障和重置窗口。交付后再执行登录、入课、Session、媒体与 Record 的完整真机 E2E。

## 本轮验证

- `BNBUStudent Mock` Debug 模拟器构建通过。
- `scripts/ios-contract-audit.mjs` 全部通过。
- 148 项单元与 Backend foundation 测试全部通过，包含带 GPS/EXIF 的图片清洗回归。
- 7 项定向 UI 回归全部通过：邮箱唯一登录、登录后入课、空状态、启动引导、邮箱管理、双向运行时语言切换和外观切换。
