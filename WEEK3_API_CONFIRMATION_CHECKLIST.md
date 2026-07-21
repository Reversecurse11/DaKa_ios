# Week 3 三端接口待确认清单（iOS 输入）

## 当前已使用接口

| 功能 | 方法与路径 | iOS 当前约定 |
|---|---|---|
| 学生登录 | `POST /auth/login` | `account`、`password`、`clientType: mobile` |
| Token 刷新 | `POST /auth/refresh` | `refreshToken` |
| 体育总览 | `GET /sport/summary` | 学生、进度、课程、任务及聚合数据 |
| 打卡记录 | `GET /sport/records` | 学生历史提交记录 |
| 凭证上传 | `POST /upload/proof` | multipart 字段 `files`，逐文件上传 |
| 提交打卡 | `POST /sport/records` | 任务、课程、类型、时长、说明和 `proofFiles` |
| 运动身份 | `GET /sport/identity` | 校队/社团抵扣 |
| 通知 | `GET /common/notifications` | 通知列表 |
| 通知已读 | `PUT /common/notifications/{id}/read` | 单条已读 |
| 免测 | `GET/POST /student/exemptions` | `type`、`reason`、`proofFiles` |

## P0/P1 待产品与后端确认

| 项目 | 建议统一内容 | iOS 当前处理 | 状态 |
|---|---|---|---|
| 打卡日期范围 | `startAt`、`endAt`、ISO 8601、明确时区 | 只展示字符串 `deadline`，不本地硬判 | 待确认 |
| 服务器时间 | 响应提供 `serverTime` 或统一 Date header | 以服务端提交结果为准 | 待确认 |
| 日期边界错误 | 稳定错误码，例如 `CHECKIN_NOT_STARTED / CHECKIN_ENDED` | 根据 HTTP/API 文案映射学生提示 | 待确认 |
| 重复打卡 | HTTP 409 + 稳定错误码 | 显示“已提交过”，禁止重复提交 | 待确认 |
| 幂等机制 | Header `Idempotency-Key` 或请求字段 `requestId` | 仅做客户端防重入和不确定结果先刷新 | 待确认 |
| 上传响应 | 文件 ID、类型、大小、时长、对象键、访问 URL、状态 | 当前兼容 `urls` 和附件对象 | 待确认 |
| 上传进度 | 客户端按已发送字节展示；服务端无需返回假百分比 | iOS 已实现真实发送进度 | iOS 已完成 |
| 413 限制 | 单文件限制和 Nginx 请求体限制保持一致 | 图片 8MB、视频 100MB 本地拦截 | 待容量结论 |
| 上传取消/续传 | 明确是否支持取消、分片和断点续传 | 当前单文件失败后整文件重试 | P2/容量调研 |
| 成绩字段 | 原始值、显示值、单位、换算分、百分制分、规则版本、权重 | iOS 不内置学校评分表 | 待确认 |
| 通知信息架构 | 是否独立通知 Tab，未读数与已读接口一致 | 当前位于首页和“我的” | 待产品确认 |
| 分页与排序 | records/notices/courses 的 page、pageSize、sort | 当前按服务器数组顺序 | 待确认 |

## 明确不由 iOS 单方面决定

- 不新增未经确认的日期字段并假设服务器已经支持。
- 不自行定义与 Android/Web 不同的错误码。
- 不把学校评分表或耐力跑换算规则硬编码进 App。
- 不在服务端无幂等支持时提供“无条件重新提交”。
- 不修改生产环境上传架构或 Nginx 限制。
