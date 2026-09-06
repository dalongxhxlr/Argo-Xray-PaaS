这份 README 文档为你梳理了整套 Koyeb 自动化防扣费脚本的逻辑和配置方法。你可以直接将以下内容保存到你项目根目录下的 `README.md` 文件中，或者作为单独的说明文档（比如 `KOYEB_AUTO_LIMIT.md`）存放到 `.github` 目录下。

---

# Koyeb Auto-Worker: 代理节点防超额启停方案

本项目利用 GitHub Actions 实现 Koyeb 平台的容器实例自动化定时启停，旨在最大化利用 Koyeb 每月赠送的 1 美元（约 462 小时 Eco-nano 实例）免费计算额度，同时通过严格的**本地累加记账机制**，防止实例运行超时导致信用卡被意外扣费。

## 核心痛点与解决思路

Koyeb 的 API 状态响应存在延迟，直接抓取平台时间戳进行覆盖计算会导致记账逻辑失效（例如每天覆盖为 14 小时，永远无法触发月度限额）。

**本方案采用“本地时间戳状态机”逻辑：**

1. **启动时**：GitHub Actions 将当前时间戳写入本地文件 `platform_limits.json`。
2. **停止时**：读取启动时间戳，计算本次运行时长的精确秒数，并**累加**到当月总时长中。
3. **熔断保护**：当本地累加的 `usage_hours` 达到设定的安全红线（如 456 小时）时，自动跳过启动步骤，彻底阻断扣费风险。
4. **自动重置**：每月初检测到月份变更时，自动将所有使用量清零。

## 配置文件说明

脚本的运行强依赖于项目根目录下的 `platform_limits.json` 文件。请确保该文件包含完整的初始结构，特别是 `last_start_time` 字段：

```json
{
  "koyeb": {
    "monthly_limit_hours": 456,
    "usage_hours": 0,
    "year": 2026,
    "month": 6,
    "estimated_cost": 0,
    "last_start_time": null
  }
}

```

* `monthly_limit_hours`: 月度安全运行上限（建议设为 456，预留一点缓冲时间）。
* `usage_hours`: 当前已累计运行的小时数。
* `last_start_time`: 内部状态标记，记录最后一次启动的系统时间戳（平时应为 `null`）。

## GitHub Secrets 配置

在运行此 Workflow 之前，必须在 GitHub 仓库的 **Settings > Secrets and variables > Actions** 中配置以下环境变量：

* `KOYEB_TOKEN`: 你的 Koyeb Personal Access Token（在 Koyeb 账户设置的 API 选项卡中生成）。
* `KOYEB_SERVICE`: 你需要控制的 Koyeb 服务 ID。
* *注意：如果你的构建流程（`build.yml`）还需要推送镜像，请确保同时配置了 `DOCKER_USERNAME` 和 `DOCKER_PASSWORD`。*

## 运行策略

当前 `koyeb-worker-auto.yml` 默认的 Cron 策略如下：

* **启动时间**：每天 09:00 CST (UTC 01:00)
* **停止时间**：每天 23:00 CST (UTC 15:00)
* **每日耗时**：14 小时
* **月度理论总耗时**：420 - 434 小时（完全在 456 小时的安全线内）

## ⚠️ 重要注意事项

1. **避免手动干预**：请尽量**不要**在 Koyeb 网页控制台手动启动或停止实例。本套逻辑依赖 GitHub Actions 本地记录的 `last_start_time` 进行闭环计算。如果手动操作，会导致本地记录的时长与平台实际消耗脱节。
2. **强制提交权限**：该脚本在运行结束后会自动将更新后的 `platform_limits.json` 提交回仓库。请确保你的 GitHub Actions 具有对仓库的写入权限（在仓库设置的 **Actions > General > Workflow permissions** 中勾选 `Read and write permissions`）。
3. **时区问题**：GitHub Actions 的 cron 任务使用的是 UTC 时间，修改启停策略时请注意加上 8 小时的时差换算为北京时间。


########################################################################################################################################

因github工作流排队导致延时5小时启动，延时3小时停止。
改用定时任务网站无服务定时任务启停koyeb服务，不再使用github工作流，但也没有超额判断停机功能。仅仅准时启停。

# 使用 cron-job.org 定时控制 Koyeb 服务启停完全指南

本指南详细记录了如何利用免费的定时任务服务 **cron-job.org**，通过调用 **Koyeb REST API** 自动定时暂停（Pause）与恢复（Resume）从 GitHub 部署在 Koyeb 上的服务。

适用于希望在夜间或非工作时段关停 Koyeb 服务以节省额度或资源的场景。

---

## 目录
1. [准备工作](#一准备工作)
   - [1.1 生成 Koyeb API Token](#11-生成-koyeb-api-token)
   - [1.2 获取 Koyeb Service ID](#12-获取-koyeb-service-id)
2. [API 接口说明](#二api-接口说明)
3. [在 cron-job.org 配置定时任务](#三在-cron-joborg-配置定时任务)
   - [3.1 配置定时恢复/启动任务 (Resume)](#31-配置定时恢复启动任务-resume)
   - [3.2 配置定时暂停/停止任务 (Pause)](#32-配置定时暂停停止任务-pause)
4. [常见问题与踩坑排查](#四常见问题与踩坑排查)
   - [4.1 401 Unauthorized 报错排查](#41-401-unauthorized-报错排查)
   - [4.2 404 Not Found 报错排查](#42-404-not-found-报错排查)
5. [安全建议](#五安全建议)

---

## 一、准备工作

### 1.1 生成 Koyeb API Token
1. 登录 [Koyeb 控制台](https://app.koyeb.com/)。
2. 点击右上角个人头像，进入 **Settings**。
3. 在左侧菜单中选择 **API Keys**，点击 **Create API Key**。此处复用github的已经使用的api key，不需新建。
4. 输入描述名称（如 `cron-job-auth`），生成 API Key。
5. **务必立即复制并保存该 API Token**（格式通常形如 `kyp_xxxxxxxx...`），生成后它将不再完整显示。

### 1.2 获取 Koyeb Service ID
1. 在 Koyeb 控制台中打开你通过 GitHub 部署的目标服务。
2. 查看浏览器地址栏的 URL：
   `https://app.koyeb.com/services/serv_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
3. 其中 `serv_` 开头的一串字符串即为你的 **Service ID**。

---

## 二、API 接口说明

Koyeb 提供官方 REST API 来支持控制服务的状态：

| 操作名称 | 请求方法 (HTTP Method) | 请求 URL |
| :--- | :--- | :--- |
| **恢复 / 启动服务** | `POST` | `https://app.koyeb.com/v1/services/<SERVICE_ID>/resume` |
| **暂停 / 停止服务** | `POST` | `https://app.koyeb.com/v1/services/<SERVICE_ID>/pause` |

**必需请求头 (Headers)：**
- `Authorization`: `Bearer <YOUR_KOYEB_API_TOKEN>`
- `Content-Type`: `application/json`

---

## 三、在 cron-job.org 配置定时任务

注册并登录 [cron-job.org](https://cron-job.org/) 仪表盘。

### 3.1 配置定时恢复/启动任务 (Resume)

1. 点击 **Create Cronjob**。
2. **Common Settings（基础设置）**：
   - **Title**: `Start Koyeb Service`
   - **URL**: `https://app.koyeb.com/v1/services/YOUR_SERVICE_ID/resume` *(请将 `YOUR_SERVICE_ID` 替换为实际 ID)*
   - **Execution Schedule**: 根据需求设置定时启动时间（例如：每天 08:00）。
3. **Advanced Settings（高级设置）**：
   - **Request Method**: 选择 `POST`。
   - **Request Headers**: 添加以下两个请求头：
     - Header 1: Key = `Authorization` | Value = `Bearer YOUR_KOYEB_API_TOKEN` *(注意 `Bearer` 和 Token 之间有且仅有一个英文空格)*
     - Header 2: Key = `Content-Type` | Value = `application/json`
4. 点击 **Save** 保存配置。

### 3.2 配置定时暂停/停止任务 (Pause)

1. 再次点击 **Create Cronjob**。
2. **Common Settings（基础设置）**：
   - **Title**: `Stop Koyeb Service`
   - **URL**: `https://app.koyeb.com/v1/services/YOUR_SERVICE_ID/pause` *(请将 `YOUR_SERVICE_ID` 替换为实际 ID)*
   - **Execution Schedule**: 设置定时关停时间（例如：每天 23:00）。
3. **Advanced Settings（高级设置）**：
   - **Request Method**: 选择 `POST`。
   - **Request Headers**: 填入与启动任务完全相同的 `Authorization` 和 `Content-Type` 请求头。
4. 点击 **Save** 保存配置。

---

## 四、常见问题与踩坑排查

### 4.1 401 Unauthorized 报错排查

如果在测试运行（Test Run）时收到以下错误：
> `401 Unauthorized: the endpoint requires authentication. Add the necessary credentials or an authorization header.`

**排查方案：**
1. **检查 `Bearer` 空格**：确认 `Authorization` 的值中，`Bearer` 与 Token 之间包含了单个英文空格。
   - 错误例子：`Bearerkyp_xxx...` 或 `bearer kyp_xxx...`
   - 正确例子：`Bearer kyp_xxx...`
2. **误用 Basic Auth**：确保**没有**勾选 cron-job.org 界面上的 `Requires HTTP authentication`（Basic Authentication）选项。身份验证只需通过 Request Headers 传递。
3. **Token 无效**：检查 API Token 是否被误删或过期，如有疑问可重新生成一个 Token。

### 4.2 404 Not Found 报错排查

**排查方案：**
1. 检查 URL 中的 `SERVICE_ID` 是否拼写正确，必须包含 `serv_` 前缀。
2. 检查请求 URL 结尾是否有误多加了斜杠或拼错 action 动词（必须是 `/pause` 或 `/resume`）。

---

## 五、安全建议

1. **最小权限原则**：妥善保管 Koyeb API Token，避免泄露至公开的 GitHub 仓库或公开发布的脚本中。
2. **通知监控**：可在 cron-job.org 的 Cronjob 设置中开启 **Execution failure notifications**（执行失败通知），当 API 调用异常或鉴权失效时及时接收邮件提醒。
