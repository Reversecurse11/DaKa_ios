# BNBU Student iOS 后端对接状态

更新时间：2026-07-02

## 当前结论

- iOS App 已按最新《iOS服务器对接手册》切换为双环境配置。
- Debug 默认连接测试服：`http://123.207.5.70:3333/api`。
- Release 默认连接生产服：`http://123.207.5.70:96/api`。
- 写入联调只使用测试服，生产服禁止提交/上传测试。
- 2026-07-02 18:22 复测：测试服登录、读取、凭证上传、免测写入、打卡写入完整链路已通。

## 2026-07-10 本周联调复查

- 测试服入口在线，`POST /api/auth/login` 使用 `clientType: "mobile"` 登录成功。
- `GET /api/sport/records` 当前返回 4 条记录，状态全部为 `pending`。
- `GET /api/student/exemptions` 当前返回 3 条申请，状态全部为 `pending`。
- 当前没有老师审批后的 `approved / rejected` 样本，因此“老师审批 → 学生端读回状态和评语”仍需 Web/老师端配合完成。
- 登录 user 与 `/sport/summary` 当前均未返回 `enrollmentYear / admissionYear`；只返回 `gender: female`、`gradeLevel: sophomore`。本周年份自动推算需要后端补充稳定的入学年份字段。
- iOS 已移除真实模式下的 Mock 列表兜底；服务器返回空课程、空任务、空认证时，学生端会展示真实空状态。
- iOS 已增加断网、超时、连接中断、服务器错误、字段解码变化和 token 失效反馈，并使用按环境隔离的最近工作台缓存。

## 已对齐接口

| 模块 | 接口 | iOS 状态 |
|---|---|---|
| 登录 | `POST /api/auth/login` | 已使用 `account`、`password`、`clientType: "mobile"` |
| 体育总览 | `GET /api/sport/summary` | 已接入 |
| 打卡记录 | `GET /api/sport/records` | 已接入 |
| 凭证上传 | `POST /api/upload/proof` | 已使用 multipart 字段 `files` |
| 提交打卡 | `POST /api/sport/records` | 已提交 `taskId`、`courseId`、`creditType`、`hours`、`note`、`proofFiles` |
| 免测列表 | `GET /api/student/exemptions` | 已接入 |
| 免测提交 | `POST /api/student/exemptions` | 已使用 `type`、`reason`、`proofFiles` |
| 通知列表 | `GET /api/common/notifications` | 已接入 |
| 通知已读 | `PUT /api/common/notifications/{id}/read` | 已接入 |

## iOS 已完成的兼容处理

- ATS 已允许 `123.207.5.70` 的 HTTP 明文访问。
- 上传限制已按手册处理：最多 6 张图片、1 个视频；图片 8MB、视频 100MB。
- 上传请求超时已设置为 60 秒。
- 测试服和生产服 token 分开存储，避免串环境。
- 免测没有补材料接口，iOS 远程模式不会调用不存在的免测补材料路径。
- 当测试服上传接口返回 404 时，iOS 会提示后端未部署 `/api/upload/proof`，避免显示模糊的 404。

## 2026-07-02 测试服实测结果

| 用例 | 结果 | 备注 |
|---|---|---|
| Health Check | 通过 | `GET /api/health` 返回 `ok: true`、`db: true` |
| 学生登录 | 通过 | `[历史 QA 凭据已脱敏] / clientType=mobile` 返回 token |
| 体育总览 | 通过 | `GET /api/sport/summary` 返回 200 |
| 免测列表 | 通过 | `GET /api/student/exemptions` 返回 200 |
| 打卡记录 | 通过 | `GET /api/sport/records` 返回 200 |
| 凭证上传 | 通过 | `POST /api/upload/proof` 返回 200，示例文件：`/uploads/1782987526180-o3212z.jpg` |
| 免测提交 | 通过 | `POST /api/student/exemptions` 返回 201，测试记录：`ex-1782986699309-olwtck` |
| 打卡提交 | 通过 | `POST /api/sport/records` 返回 201，测试记录：`sr-1782986700168-8gsxwd` |

## 2026-07-02 18:22 上传修复后复测

| 用例 | 结果 | 备注 |
|---|---|---|
| 凭证上传 | 通过 | `POST /api/upload/proof` 返回 200，`urls` 数组正常 |
| 上传后免测提交 | 通过 | `POST /api/student/exemptions` 返回 201，测试记录：`ex-1782987527070-zmxbnk` |
| 上传后打卡提交 | 通过 | `POST /api/sport/records` 返回 201，测试记录：`sr-1782987528057-935tq1` |
| 免测读回 | 通过 | `GET /api/student/exemptions` 返回 200，能读回新记录 |
| 打卡读回 | 通过 | `GET /api/sport/records` 返回 200，能读回新记录 |

> 说明：测试服 `/api/upload/proof` 已由后端修复，当前 iOS 端完整链路为：登录 → 上传凭证 → 提交免测 / 打卡 → 读回记录。

## 2026-07-03 真机上传打卡复测

| 用例 | 结果 | 备注 |
|---|---|---|
| 真机连接测试服登录 | 通过 | `[历史 QA 凭据已脱敏]`，旧测试服 `http://123.207.5.70:3333/api` |
| 真机提交打卡 | 通过 | 服务器打卡记录数从 3 增至 4 |
| 服务器读回记录 | 通过 | 新记录：`sr-1783048692990-ltm84e` |
| 备注匹配 | 通过 | `iOS真机联调 20260703-打卡-2` |
| proofFiles 写入 | 通过 | `["/uploads/1783048692911-ebqyo4.jpg"]` |
| 上传图片访问 | 通过 | `http://123.207.5.70:3333/uploads/1783048692911-ebqyo4.jpg` 返回 200 |

> 结论：iOS 真机端“选择图片 → 上传到服务器 → 提交打卡 → 服务器保存 proofFiles → API 读回记录 → 图片 URL 可访问”链路已完整跑通。

## 2026-07-03 真机免测申请复测

| 用例 | 结果 | 备注 |
|---|---|---|
| 真机连接测试服登录 | 通过 | `[历史 QA 凭据已脱敏]`，旧测试服 `http://123.207.5.70:3333/api` |
| 真机提交免测申请 | 通过 | 服务器免测记录数从 2 增至 3 |
| 服务器读回申请 | 通过 | 新申请：`ex-1783049892593-6z5bsy` |
| 申请类型 | 通过 | `1000m` |
| 备注匹配 | 通过 | `iOS真机联调 20260703-免测` |
| proofFiles 写入 | 通过 | `["/uploads/1783049892525-c8aaui.jpg"]` |
| 上传图片访问 | 通过 | `http://123.207.5.70:3333/uploads/1783049892525-c8aaui.jpg` 返回 200 |

> 结论：iOS 真机端“选择图片 → 上传到服务器 → 提交免测申请 → 服务器保存 proofFiles → API 读回申请 → 图片 URL 可访问”链路已完整跑通。

## 给后端同学的联调重点

- 确认测试服 `http://123.207.5.70:3333/api/health` 在线。
- 使用从环境或密码管理器取得的专用 QA 学生账号，登录体必须带 `"clientType": "mobile"`；不得把凭据写入文档。
- 如提交打卡失败，请重点看后端是否要求 `proofFiles`，以及是否接受 iOS 同时保留的兼容字段 `proof_files`。
- 如上传失败，请确认后端 multipart 字段名为 `files`。
- 当前测试服上传接口已恢复，后续若再次失败，优先检查 `/api/upload/proof` 路由和 multipart 字段 `files`。
