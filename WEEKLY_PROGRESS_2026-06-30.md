# iOS 端周进度更新 - 2026-06-30

| 端 | 负责人 | 本周完成 | 下周计划 | 阻塞项 |
|---|---|---|---|---|
| iOS | 周润基 | 读取 NewStuff 最新产品全景文档和腾讯云宝塔教程；确认 M1 阶段重点为三端联通；将 iOS 默认远程 API Base URL 调整为 `http://123.207.5.70:96/api`；改造 `RemoteStudentRepository`，对齐 `/auth/login`、`/sport/summary`、`/sport/records`、`/sport/identity`、`/common/notifications`、`/upload/proof`；补充模型层 snake_case 和线上枚举兼容；修复 iOS ATS 对腾讯云 HTTP API 的拦截；完成 App / Unit Test / UI Test target 编译验证；Simulator 已验证能到达腾讯云后端并显示后端真实错误。 | 等后端确认可用学生账号后，继续跑通真实登录、体育总览、打卡记录、通知、上传凭证、提交打卡全链路；随后补真机签名与相册/摄像头/网络权限实测。 | 历史测试凭据已脱敏；需要后端通过密码管理器确认专用 QA 账号及登录 account 格式。 |

## 本周验证记录

- `GET http://123.207.5.70:96/api/health` 返回 `ok: true`、`service: BNBU Sports API`、`db: true`
- iOS App 服务器登录页显示 `http://123.207.5.70:96/api`
- 点击服务器登录已到达后端，返回真实文案 `账号或密码错误`
- 演示登录仍可正常进入学生端首页
- 验证截图：`ios-app/build/screenshots/30-tencent-api-login-error.jpg`

## 需要后端协助确认

1. 密码管理器中的专用 QA 学生账号是否已在对应测试数据库中；不要在文档或工单写出密码。
2. `POST /api/auth/login` 的学生端登录字段是否固定为 `account + password + role=student`。
3. `account` 应传邮箱、学号，还是其他登录名。
4. 登录成功后 `/sport/summary`、`/sport/records`、`/sport/identity`、`/common/notifications` 返回字段是否与 Android 端一致。
5. `POST /api/upload/proof` 返回的是 `url`、`path`、`storagePath` 还是完整文件对象。

## 2026-07-01 追加进度

- 已补齐 iOS 学生端“免测申请”前端闭环：
  - 成绩页新增免测申请模块
  - 新增申请表单和补材料表单
  - 复用图片 / 视频凭证上传 UI
  - 支持待审核、通过、驳回、需补材料状态展示
  - 本地 Mock 支持提交申请和补充材料
- 已补远程接口占位：
  - `POST /api/student/exemptions`
  - `GET /api/student/exemptions` 读取尝试
  - `POST /api/student/exemptions/{id}/supplements` 补材料尝试
- 已验证：
  - `xcodebuild build` 通过
  - `xcodebuild test -only-testing:BNBUStudentTests` 通过，6 个单元测试全部通过
  - Simulator 演示登录后可看到免测申请模块和申请表单
- 新增截图：
  - `ios-app/build/screenshots/31-exemption-panel.jpg`
  - `ios-app/build/screenshots/32-exemption-form.jpg`

## 免测申请后端待确认

1. `POST /api/student/exemptions` 的字段名是否使用 `exemption_type + reason + description + proof_files`。
2. 是否提供 `GET /api/student/exemptions` 供学生端读取历史申请。
3. 补材料接口是 `/student/exemptions/{id}/supplements` 还是其他路径。
4. 审核状态枚举是否为 `pending / approved / rejected / needs_supplement`。
