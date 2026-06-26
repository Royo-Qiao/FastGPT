# FastGPT 基础服务 ARM/openEuler 部署包

目标环境：Kunpeng-920 / `aarch64` / openEuler 22.03 LTS。此包基于 FastGPT 官方 `v4.14.22` PgVector Docker Compose 模板，加入 ARM64 适配、内网访问配置和行为补丁。

## 部署范围

- FastGPT Web
- PgVector（向量数据库）
- MongoDB
- Redis
- MinIO（对象存储）
- FastGPT Plugin
- Code Sandbox
- AIProxy
- MinerU（PDF 解析服务，独立容器，见 `mineru/`）

## 内网访问

目标服务器 IP：`172.16.2.198`

| 服务 | 地址 |
|---|---|
| FastGPT Web | `http://172.16.2.198:13000` |
| MCP | `http://172.16.2.198:13003` |
| MinIO API | `http://172.16.2.198:19000` |
| MinIO Console | `http://172.16.2.198:19001` |
| MinerU PDF 解析 | `http://172.16.2.198:8010` |

## 启动条件

在宿主机级别的 openEuler ARM64 shell 中需要：

- Docker Engine 可用
- Docker Compose plugin `>= 2.24.4`（使用 `!override` 语法，低版本不支持）
- CPU 检测到 `Kunpeng-920`（preflight 硬性检查）
- 端口 `13000/13003/19000/19001` 未被占用

## 使用

```bash
cd /workspace/user_data/fastgpt-basic-openEuler-arm64
bash ./scripts/preflight.sh
bash ./scripts/start.sh
```

root 初始密码：**123456**（由 `.env` 中的 `FASTGPT_DEFAULT_ROOT_PSW` 控制，重启后自动重置为此值）。

### 启动 MinerU PDF 解析服务（推荐先于 FastGPT 启动）

MinerU 是 FastGPT 解析 PDF 的自定义后端，独立容器部署，镜像内置全部依赖与模型：

```bash
cd /workspace/user_data/fastgpt-basic-openEuler-arm64/mineru
bash scripts/deploy.sh        # 一键：加载镜像 + 启动 + 验证
```

详见 [`mineru/README.md`](mineru/README.md)。

## 补丁说明

### patches/ — 崩溃页面跳转消除

FastGPT 原始 `_error.tsx` 被触发时会弹 toast 并在 2 秒内强制跳转到模型配置页。`patches/init-patch.sh` 在容器启动时：

1. 替换 SSR 端 `_error.js` 为无副作用版本
2. 将客户端 chunk 中 `setTimeout(fn,2e3)` 改为 `9e9`（永不触发）
3. 以原始 `server.js` 接管 PID 1

### plugin-patch/ — 清空内置模型预设

FastGPT plugin 镜像内置了 251 个云服务模型预设（OpenAI/Claude/Qwen 等）。`plugin-patch/index.js` 是 patch 过的 bundle，清空了所有 provider 的 model list，使模型配置页从空白开始，按需手动添加本地 NPU 服务。

## 本地模型注册

启动后登录 FastGPT，进入 **账号 → 模型提供商 → 模型配置** 手动添加。参考端口规划：

| 服务 | 端口 | 类型 |
|---|---|---|
| DeepSeek-V4-Flash | 8900 | LLM |
| Qwen3.6-27B | 8901 | LLM |
| Qwen3-Embedding-4B | 8902 | Embedding |
| Qwen3-Embedding-8B | 8903 | Embedding |
| BGE-M3 | 8904 | Embedding |
| BGE-Reranker-v2-m3 | 8905 | Rerank |
| MinerU PDF 解析 | 8010 | PDF 解析（本包自带，CPU 模式） |

## 文件说明

| 文件 | 说明 |
|---|---|
| `docker-compose.upstream.yml` | FastGPT 官方 PgVector 模板原件（不修改） |
| `docker-compose.arm64.override.yml` | ARM64 适配层：platform、端口覆盖、patches 挂载、plugin-patch 挂载 |
| `config.json` | FastGPT 配置（PDF 解析服务地址预配置为 `172.16.2.198:8010`） |
| `.env` | 环境变量（绑定地址、端口、密钥） |
| `.env.example` | `.env` 模板（密钥占位符） |
| `patches/_error.server.js` | 替代 `_error.tsx` 的无副作用 SSR 错误页 |
| `patches/init-patch.sh` | 容器启动 wrapper，注入 _error 补丁后 exec server.js |
| `plugin-patch/index.js` | 清空内置模型预设的 patched plugin bundle |
| `scripts/init-env.sh` | 生成 `.env` 和随机密钥（仅在 `.env` 不存在时执行） |
| `scripts/preflight.sh` | 启动前环境检查 |
| `scripts/start.sh` | 预检通过后拉取并启动 |
| `scripts/stop.sh` | 停止或 down 本项目（不删除卷） |
| `scripts/detect-infer-endpoint.sh` | 检测推理服务在容器内/宿主机不同视角下的可达地址 |
| `mineru/` | MinerU PDF 解析服务自包含部署包（镜像 + 脚本 + 文档，详见 `mineru/README.md`） |
