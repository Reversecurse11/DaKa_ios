# iOS 学生端质量回归流程

## 1. 每次提交都执行的 Windows 契约门禁

在 `ios-app` 目录执行：

```powershell
node scripts/ios-contract-audit.mjs
```

该门禁会核对现行后端 `backend/openapi/openapi.yaml` 与 iOS 运行时代码，覆盖：

- Debug API 必须是 `http://123.207.5.70:82/api/v1`，运行时代码不得残留旧端口 3333。
- 登录固定发送 `role=student` 与 `clientType=mobile`。
- 工作台必须读取体育摘要、学生资料、课程、任务、成绩、记录、身份、通知、免测接口。
- 提交学时只能是 1 或 2；打卡凭证总大小不超过 120MB；免测证明不超过 5 个。
- ATS 不允许全局任意明文请求，只保留本地开发与临时测试 IP 例外。
- Xcode 工程必须包含关键源码，XCTest 必须覆盖当前后端返回结构。

## 2. macOS/Xcode 单命令发布门禁

### 2.1 前置条件

- 使用装有完整正式版 Xcode 和 iOS Simulator Runtime 的 Mac，并先接受 Xcode License、完成 First Launch Components 安装。
- Mac 上必须有 `node`；门禁会直接复用第 1 节的 `ios-contract-audit.mjs`，不会另建一套较弱的静态检查。
- 保持当前完整仓库目录结构；若 iOS 工程与后端分开放置，使用 `--backend-root` 指向包含 `openapi/openapi.yaml` 的后端根目录。
- 先取得学校确认的正式 HTTPS API 域名。当前 IP/HTTP 测试地址、IP 地址、占位域名、localhost 和带账号密码的 URL 都会被门禁拒绝。

在 `ios-app` 目录执行下面这一条命令；必须先把尖括号内容替换为学校确认的正式域名：

```bash
chmod +x scripts/run-macos-release-gate.sh && \
./scripts/run-macos-release-gate.sh \
  --release-api-base-url 'https://<学校确认的正式域名>/api/v1'
```

门禁默认自动选择模拟器：优先使用已经启动的 iPhone，否则选择最新可用 iOS Runtime 中的 iPhone；只有未安装任何 iPhone Simulator 时才回退到其他可用 iOS Simulator。需要固定 CI 设备时，可显式传入 Xcode destination：

```bash
./scripts/run-macos-release-gate.sh \
  --release-api-base-url 'https://<学校确认的正式域名>/api/v1' \
  --destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest'
```

目录分开放置或需要指定报告目录时使用；`--output-dir` 必须是新的或空目录，避免覆盖既有测试证据：

```bash
./scripts/run-macos-release-gate.sh \
  --release-api-base-url 'https://<学校确认的正式域名>/api/v1' \
  --backend-root '/absolute/path/to/BNBU-Sports-Android/backend' \
  --output-dir '/absolute/path/to/ios-release-gate-output'
```

同名环境变量 `BNBU_RELEASE_API_BASE_URL`、`IOS_SIMULATOR_DESTINATION`、`BNBU_BACKEND_ROOT`、`BNBU_IOS_GATE_OUTPUT_DIR` 也可用于 CI。不要把学生账号、密码、Access Token、COS 密钥或签名凭据传给脚本；该门禁不需要这些信息。

### 2.2 门禁实际执行内容

脚本以 `set -Eeuo pipefail` 严格模式依次执行：

1. 检查 macOS/Xcode/Node、工程、共享 Scheme、测试 Target、后端 OpenAPI、正式 URL 和 Simulator destination，并等待自动选择的 Simulator 完成启动。
2. 对 `ios-contract-audit.mjs` 做 Node 语法检查，再执行完整 iOS 静态契约审计。
3. 执行 Debug Simulator `clean build`。
4. 单独执行 `BNBUStudentTests` XCTest。
5. 单独执行 `BNBUStudentUITests` XCUITest smoke suite。
6. 对 `generic/platform=iOS` 执行 Release build，强制 `CODE_SIGNING_ALLOWED=NO`。
7. 对 `generic/platform=iOS` 执行 Release analyze，同样禁止签名。

预检失败时其余步骤标记为 `SKIPPED`；预检通过后，脚本会尽量跑完其余独立步骤，以便一次收集全部失败证据。Release 无签名 build/analyze 不能替代正式签名、Archive、Organizer Validate App 与真机验收。

### 2.3 机器可读结果与验收标准

默认报告位于：

```text
artifacts/ios-release-gate/<UTC时间>-<进程号>/
```

每个步骤都有独立 `logs/*.log`（未执行步骤会明确写入 `SKIPPED`）；Xcode 步骤保留 `results/*.xcresult`；最终结果写入 `summary.json`。标准输出最后还会给出两行稳定标记：

```text
BNBU_IOS_RELEASE_GATE_RESULT={...单行 JSON...}
BNBU_IOS_RELEASE_GATE_SUMMARY=/absolute/path/to/summary.json
```

即使预检发现 `node` 缺失，脚本也会用纯 Bash 回退写出可解析的 `summary.json` 和同样的单行 JSON 标记，方便 CI 稳定采集失败原因；但该次结果仍然是 `FAIL`，不会绕过静态审计。机器汇总只记录“正式 API 已配置”的布尔值，不写 URL 本身；普通文本日志若出现该 URL，也会在打印与落盘前替换为 `[REDACTED_RELEASE_API_BASE_URL]`。

正式验收必须同时满足：脚本退出码为 0、`summary.json` 顶层 `status` 为 `PASS`、七个步骤均为 `PASS`，且 Unit/UI test 无失败，日志无 crash、fatal error 或未捕获异常。任何 `FAIL`、`SKIPPED`、缺失 `.xcresult` 或仅凭终端中出现 `BUILD SUCCEEDED` 都不能视为整套门禁通过。

## 3. 连接测试服的主链路验收

安装 Debug 构建，使用启动参数显式指定测试服：

```bash
xcrun simctl launch booted edu.bnbu.student.mvp \
  --args -server-base-url http://123.207.5.70:82/api/v1
```

按顺序执行并保留截图、接口状态码和记录 ID：

1. 学生账号登录；教师账号必须被学生入口拒绝。
2. 首页学时、待处理数与 `GET /sport/summary` 一致。
3. 课程页当前/历史分类与 `GET /student/courses` 的 `isCurrent` 一致；老师、Section、任务均可见。
4. 成绩页与 `GET /student/grades` 的 summary 一致，不得用体育摘要臆算考试/考勤/体测分数。
5. 提交 1h 图片打卡：上传成功、记录生成、列表刷新、详情图片可见。
6. 提交 2h 视频打卡：进度可见、失败可重试、成功后不可重复提交。
7. 补材料只发送 1h 或 2h；0.5h 历史草稿必须归一为 1h。
8. 通知标记已读后刷新仍为已读。
9. 个人资料的性别、年级、入学年份来自 `/student/profile`。
10. 免测第 5 个证明可添加，第 6 个在选择阶段即被阻止；提交后能读回记录。
11. 断网后显示最近成功缓存并明确提示；恢复网络后下拉刷新回到服务器数据。
12. 退出后旧 token 清除，切换账号不得看到上一账号缓存。

## 4. 边界与安全回归

- 图片 8MB、视频 100MB、全部凭证 120MB 分别测试边界值与超限值。
- 打卡 7 个凭证允许，免测只允许 5 个。
- 模拟 401、409、413、422、429、500 和超时，确认提示可操作且不会重复写入。
- 检查私有 COS URL 过期后的刷新行为，不在客户端保存 COS SecretId/SecretKey。
- Release 构建必须确认 `NSAllowsArbitraryLoads=false`。
- 正式发布前必须把 `configuration-required.invalid` 替换为学校确认的 HTTPS `/api/v1` 地址；未完成时禁止提交 App Store/正式分发。

## 5. 缺陷闭环标准

每个缺陷至少包含：复现账号/环境、前置数据、操作步骤、期望/实际、请求 ID 或记录 ID、截图/日志、修复提交、自动化回归用例。修复后必须重新执行第 1、2 节以及受影响的第 3、4 节用例。
