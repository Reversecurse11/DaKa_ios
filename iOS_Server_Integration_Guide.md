# BNBU iOS 客户端 — 服务器连接 & 接口对接手册

> **历史环境说明（2026-07-15）**：本文记录的 `/api`、HTTP IP 和 96/3333 端口属于旧联调环境，不是新统一主后端的正式发布契约。新版本以主后端 `openapi/openapi.yaml` 为准，Base URL 必须以 `/api/v1` 结尾；Release 必须使用学校确认的 HTTPS 域名。旧地址不得写入正式安装包。

---

## 1. 文档说明

| 项目 | 内容 |
|---|---|
| 适用人员 | iOS 客户端开发 |
| 环境划分 | 测试服务器（开发调试用）、生产服务器（全校师生在用） |
| 前置工具 | Apifox 或 Postman（接口调试）、Charles 或 Proxyman（抓包） |

> ⚠️ 测试服和生产服**数据完全隔离**，互不影响。测试服可以随便写删数据，生产服禁止任何测试操作。

---

## 2. 服务器基础连接信息

### 测试服务器

| 项目 | 值 |
|---|---|
| 域名/IP | `123.207.5.70` |
| 端口 | `3333` |
| 协议 | HTTP |
| API 根地址 | `http://123.207.5.70:3333/api` |
| Health Check | `http://123.207.5.70:3333/api/health` |
| 状态 | ✅ 运行中 |

### 生产服务器

| 项目 | 值 |
|---|---|
| 域名/IP | `123.207.5.70` |
| 端口 | `96` |
| 协议 | HTTP |
| API 根地址 | `http://123.207.5.70:96/api` |
| Health Check | `http://123.207.5.70:96/api/health` |
| 状态 | ✅ 运行中（全校师生在用，**禁止写操作测试**） |

### 在线接口文档

| 项目 | 值 |
|---|---|
| Swagger / Apifox 链接 | _待后端提供_ |
| 登录账号 | _待后端提供_ |

### 静态资源文件访问

| 项目 | 值 |
|---|---|
| 测试服 | `http://123.207.5.70:3333/uploads/` |
| 生产服 | `http://123.207.5.70:96/uploads/` |

---

## 3. iOS 对接服务器完整操作流程

### 3.1 调试工具环境配置

**Apifox / Postman 新建两套环境：**

| 环境变量 | 测试服值 | 生产服值 |
|---|---|---|
| `baseUrl` | `http://123.207.5.70:3333/api` | `http://123.207.5.70:96/api` |
| `token` | 登录后自动填充 | 登录后自动填充 |

**全局公共请求头（所有接口都需要）：**

```
Content-Type: application/json
Accept: application/json
Authorization: Bearer {{token}}
```

### 3.2 接口通用调用规范

**统一请求头：**

| Header | 值 | 说明 |
|---|---|---|
| `Content-Type` | `application/json` | 请求体格式 |
| `Accept` | `application/json` | 期望返回格式 |
| `Authorization` | `Bearer <token>` | 登录后拿到 token，拼上 `Bearer ` 前缀 |

**请求数据格式：** JSON（camelCase 驼峰命名）

**标准成功返回：**

```json
{
  "token": "bnbu-xxx-xxx",
  "user": {
    "id": "<QA_STUDENT_ID>",
    "name": "<QA_STUDENT_NAME>",
    "email": "<QA_STUDENT_EMAIL>",
    "role": "student",
    "college": "工商管理学院",
    "gender": "female",
    "gradeLevel": "sophomore",
    "status": "正常"
  },
  "defaultRoute": "student-dashboard"
}
```

**标准失败返回：**

```json
{
  "code": "AUTH_FAILED",
  "message": "账号或密码错误"
}
```

**通用错误码含义表：**

| code | HTTP | 含义 | iOS 处理 |
|---|---|---|---|
| `AUTH_FAILED` | 401 | 账号或密码错误 | 提示用户重新输入 |
| `AUTH_REQUIRED` | 401 | 未登录 / Token 失效 | 跳转登录页 |
| `FORBIDDEN_ROLE` | 403 | 角色无权限 | 提示"学生端不支持此操作" |
| `VALIDATION` / `VALIDATION_FAILED` | 400/422 | 请求参数校验失败 | 显示 message 给用户 |
| `RESOURCE_NOT_FOUND` | 404 | 数据不存在 | 显示空状态页面 |
| `SERVER_ERROR` | 500 | 服务器内部错误 | 提示"服务器繁忙，请稍后重试" |

### 3.3 鉴权连接核心流程

#### 登录接口

```
POST {{baseUrl}}/auth/login
Content-Type: application/json

// 请求体：
{
  "account": "<QA_STUDENT_ACCOUNT>", // 从环境或密码管理器读取
  "password": "<QA_STUDENT_PASSWORD>", // 不得写入文档或源码
  "clientType": "mobile"          // ⚠️ 必填！不传学生会被 403 拦截
}
```

**登录成功返回：**

```json
{
  "token": "bnbu-test-0fe1e366-e3fd-495e-84a2-85ec0bebe501",
  "user": {
    "id": "<QA_STUDENT_ID>",
    "name": "<QA_STUDENT_NAME>",
    "email": "<QA_STUDENT_EMAIL>",
    "role": "student",
    "college": "工商管理学院",
    "gender": "female",
    "gradeLevel": "sophomore",
    "scope": "",
    "status": "正常"
  },
  "defaultRoute": "student-dashboard"
}
```

**登录失败返回：**

```json
{
  "code": "AUTH_FAILED",
  "message": "账号或密码错误"
}
```

```json
{
  "code": "VALIDATION",
  "message": "请输入账号和密码"
}
```

#### Token 携带规则

登录成功后，所有业务接口请求头都必须带：

```
Authorization: Bearer <token值>
```

示例：

```
Authorization: Bearer bnbu-test-0fe1e366-e3fd-495e-84a2-85ec0bebe501
```

#### Token 过期处理

| 情况 | HTTP | code | iOS 处理 |
|---|---|---|---|
| Token 过期或无效 | 401 | `AUTH_REQUIRED` | 清除本地 token → 跳转登录页 |
| Token 即将过期 | — | — | 目前后端不支持 refresh token，过期直接重新登录 |

> Token 格式：`bnbu-<uuid>`（生产）/ `bnbu-test-<uuid>`（测试），存在内存中，服务器重启全部失效。

> 当前**无签名加密**。所有请求走明文 HTTP，正式上线前需切 HTTPS。

---

## 4. iOS 项目本地对接配置要点

### 4.1 ATS 网络适配

iOS App 的 `Info.plist` 中需配置 App Transport Security 例外：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <key>NSAllowsLocalNetworking</key>
    <true/>
    <!-- 如果只想放开特定域名，用下面这个代替 NSAllowsArbitraryLoads -->
    <key>NSExceptionDomains</key>
    <dict>
        <key>123.207.5.70</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <true/>
        </dict>
    </dict>
</dict>
```

| 环境 | HTTP | HTTPS |
|---|---|---|
| 测试服 | ✅ 允许 | 目前不支持 |
| 生产服 | ✅ 允许 | 正式上线后强制 |

### 4.2 项目内环境切换方案

iOS 项目中 `StudentServerConfig.swift` 已有两套地址：

```swift
enum StudentServerConfig {
    // 测试服
    static let testBaseURL = URL(string: "http://123.207.5.70:3333/api")!

    // 生产服（默认）
    static let defaultBaseURL = URL(string: "http://123.207.5.70:96/api")!

    static func resolvedBaseURL() -> URL {
        // 通过启动参数切换：xcrun simctl launch booted edu.bnbu.student.mvp --args -server-base-url http://123.207.5.70:3333/api
        if let url = argumentValue(named: "-server-base-url", in: ProcessInfo.processInfo.arguments) {
            return URL(string: url) ?? defaultBaseURL
        }
        // 通过环境变量切换：BNBU_API_BASE_URL=http://123.207.5.70:3333/api
        if let rawURL = ProcessInfo.processInfo.environment["BNBU_API_BASE_URL"] {
            return URL(string: rawURL) ?? defaultBaseURL
        }
        return defaultBaseURL
    }
}
```

**快速切换方式（不重新编译）：**

```bash
# Simulator 启动时用测试服
xcrun simctl launch booted edu.bnbu.student.mvp --args -server-base-url http://123.207.5.70:3333/api

# 或者设环境变量
BNBU_API_BASE_URL=http://123.207.5.70:3333/api

# 切回生产服
xcrun simctl launch booted edu.bnbu.student.mvp --args -server-base-url http://123.207.5.70:96/api
```

### 4.3 移动端特有参数上传规则

当前后端**暂不要求**以下字段，但建议预留：

| 参数 | 说明 | 建议 |
|---|---|---|
| 设备 UUID | `UIDevice.current.identifierForVendor` | 后续可能用于设备绑定 |
| 系统版本 | `UIDevice.current.systemVersion` | 日志排查用 |
| App 版本 | `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` | 做版本兼容判断 |
| 推送 DeviceToken | 暂无推送服务 | 待接入 |

---

## 5. 特殊接口对接规范

### 图片/文件上传接口

```
POST {{baseUrl}}/upload/proof
Content-Type: multipart/form-data
Authorization: Bearer <token>

// multipart 字段名：files
// 支持多文件同时上传
```

**上传限制：**

| 限制项 | 值 |
|---|---|
| 最多图片张数 | 6 张 |
| 单张图片最大 | 8 MB |
| 最多视频个数 | 1 个 |
| 单个视频最大 | 100 MB |
| 请求超时 | 60 秒（大文件上传） |

**iOS 上传代码要点：**

```swift
// multipart body 构建
var request = URLRequest(url: URL(string: "\(baseURL)/upload/proof")!)
request.httpMethod = "POST"
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

let boundary = UUID().uuidString
request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

var body = Data()
for attachment in attachments {
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(attachment.fileName)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
    body.append(attachment.data)
    body.append("\r\n".data(using: .utf8)!)
}
body.append("--\(boundary)--\r\n".data(using: .utf8)!)
request.httpBody = body
```

> ⚠️ multipart 字段名是 **`files`** 不是 `file`！如果传错字段名，后端收不到文件。

**上传成功返回示例（推测，待实测）：**

```json
{
  "urls": ["/uploads/1782973342744-jxf3a2.jpg"],
  "count": 1
}
```

### 分页接口

当前学生端接口暂不支持分页，列表接口一次性返回全部数据。后续如支持分页，统一规范为：

| 请求参数 | 类型 | 说明 |
|---|---|---|
| `page` | Int | 页码，从 1 开始 |
| `pageSize` | Int | 每页条数，默认 20 |

| 返回字段 | 类型 | 说明 |
|---|---|---|
| `items` | Array | 当前页数据 |
| `total` | Int | 总条数 |
| `page` | Int | 当前页码 |
| `totalPages` | Int | 总页数 |

---

## 6. 连接失败常见问题排查（iOS 专属）

### 问题 1：访问不通

| 原因 | 排查方法 | 解决 |
|---|---|---|
| 域名/IP 写错 | 浏览器直接打开 API 地址看能否访问 | 核对 IP 和端口 |
| 端口被防火墙封 | 浏览器访问 `http://IP:端口/api/health`，打不开就是封了 | 腾讯云控制台 → 防火墙 → 放行端口 |
| ATS 拦截 HTTP | Xcode Console 出现 `ATS` 相关报错 | Info.plist 加 `NSAllowsArbitraryLoads` |
| 内网 WiFi 限制 | 切换 4G 试试 | 特定网络环境问题 |

### 问题 2：401 / 403 无权限

| 症状 | 原因 | 解决 |
|---|---|---|
| 登录就返回 401 `AUTH_FAILED` | 缺少 `clientType: "mobile"` | 登录 body 加上 `"clientType": "mobile"` |
| 登录就返回 401 `AUTH_FAILED` | 密码错误 | 从负责人或密码管理器确认专用 QA 密码，不要写入文档 |
| 请求业务接口返回 401 `AUTH_REQUIRED` | Token 过期 | 重新登录获取新 token |
| 请求业务接口返回 401 `AUTH_REQUIRED` | 没传 Authorization 头 | 检查请求头拼写 `Authorization: Bearer xxx` |
| 返回 403 | 角色不匹配 | 确认登录时用的是学生账号 |

### 问题 3：参数格式报错

| 症状 | 原因 | 解决 |
|---|---|---|
| `VALIDATION: 请输入账号和密码` | 字段名用了 `email` 而不是 `account` | 改成 `"account": "学号或邮箱"` |
| `VALIDATION_FAILED: 缺少必填字段` | 提交打卡缺少 `creditType` 或 `hours` | 检查请求体字段名（驼峰 `creditType` 非 `credit_type`） |
| 后端 500 错误 | 服务器内部错误 | 复制完整请求和响应发给后端排查 |
| 返回字段解析失败 | 后端字段名与 iOS 模型不一致 | 对照 `Models.swift` CodingKeys 和实际返回 JSON |

### 问题 4：请求超时 / 图片加载失败

| 症状 | 原因 | 解决 |
|---|---|---|
| 请求超时 | 网络慢或服务器负载高 | 增大 timeout 到 30s；检查服务器 PM2 状态 |
| 图片加载失败 | URL 路径不对 | 确认 `proofFiles` 里的路径拼上正确的域名 |
| 上传超时 | 文件太大 | 检查文件大小限制；视频 >100MB 会被拒 |

### 调试技巧

**在 Apifox/Postman 里先调通，再到 Xcode 里写代码。** 先用工具确认接口没问题，再排查 iOS 代码。这样能快速定位是接口问题还是代码问题。

---

## 7. 重要备注

### 安全红线

| 规则 | 说明 |
|---|---|
| 🚫 测试服与生产服数据隔离 | 测试服随便写，生产服**禁止任何测试写操作** |
| 🚫 生产服 GET 只读可以调 | 查数据可以，提交/删除绝对不行 |
| 🚫 线上禁止调用测试接口 | App Store 版本必须指向生产服 |

### 当前已知问题

| 问题 | 状态 | 影响 |
|---|---|---|
| iOS 登录 body 缺 `clientType: "mobile"` | 🔴 待修复 | 学生无法登录 |
| 上传 multipart 字段名 `file` → `files` | 🔴 待修复 | 上传可能失败 |
| 免测无"补材料"状态 | 🟡 已确认 | iOS 免测 UI 需去掉补材料入口 |

### 对接联系人

| 角色 | 联系人 | 飞书 |
|---|---|---|
| 后端开发 | 陈昊 | _待补充_ |
| Web 端/服务器运维 | 何天一 | _待补充_ |
| iOS 协作测试 | 游锦哲 | _待补充_ |
| iOS 主开发 | 周润基 | _待补充_ |
