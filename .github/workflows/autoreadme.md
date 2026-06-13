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
