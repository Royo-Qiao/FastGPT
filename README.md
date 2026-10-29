# FastGPT openEuler ARM64 部署配置

面向 **openEuler 22.03、Kunpeng-920、aarch64** 主机的 FastGPT 部署配置与辅助脚本，包含 Docker Compose ARM64 覆盖层、MinerU PDF 解析服务和 Ascend 本地模型服务入口。

FastGPT deployment configuration for openEuler ARM64/Kunpeng-920, with Docker Compose overrides, MinerU PDF parsing and Ascend model-service scripts.

本仓库基于外部 FastGPT 容器镜像组织部署，提供配置、补丁和运维脚本；FastGPT 产品源码与功能请查看 [FastGPT 上游](https://github.com/labring/FastGPT)。

## 从哪里开始

| 入口 | 内容 |
|---|---|
| [基础服务部署说明](fastgpt-basic-openEuler-arm64/README.md) | Compose 服务、配置、补丁、启动与停止 |
| [启动前检查](fastgpt-basic-openEuler-arm64/scripts/preflight.sh) | 架构、CPU、系统版本、Docker、Compose 版本与端口检查 |
| [ARM64 覆盖配置](fastgpt-basic-openEuler-arm64/docker-compose.arm64.override.yml) | 平台、端口、挂载和服务覆盖 |
| [MinerU 说明](fastgpt-basic-openEuler-arm64/mineru/README.md) | PDF 解析容器、镜像加载和模型准备要求 |
| [BGE 脚本](models/bge-scripts/deploy-bge.sh) | BGE-M3 embedding 与 reranker 服务部署入口 |
| [Qwen 脚本](models/qwen3.6-27b-scripts/deploy-qwen.sh) | Qwen3.6-27B 的镜像、模型与 NPU 参数检查 |

## 环境与外部资产

- 基础服务的 `preflight.sh` **硬性要求** `aarch64`、`Kunpeng-920`、`openEuler` 且 `VERSION_ID=22.03`；其它 CPU、Linux 发行版或系统版本不在此脚本的接受范围。
- 需要宿主机 Docker Engine、Docker Compose plugin **2.24.4+** 和 Python 3；覆盖文件使用 Compose `!override` 语法。
- Compose 引用外部容器镜像，FastGPT 主镜像固定为 `v4.14.22`。镜像需要在目标机可用；本次审查未验证镜像可拉取性或其 ARM64 支持情况。
- Git 克隆包含 MinerU 的 Dockerfile、API 代码、脚本及校验和，**不包含**大型镜像归档、`mineru.part.*` 分片或模型权重。离线部署前需另行准备匹配的镜像与模型；不能将旧说明中的“自包含包”理解为 Git 仓库已携带这些资产。
- `models/` 是独立模型服务的辅助脚本。它们检查外部模型目录、离线镜像与 Ascend 驱动/NPU 设备；不随仓库分发模型权重，也不由 FastGPT 基础服务自动完成部署。

## 配置与启动入口

先阅读 [基础服务部署说明](fastgpt-basic-openEuler-arm64/README.md)，检查目标机满足以上约束，并准备所需镜像。以下是已有脚本的调用入口：

```bash
git clone https://github.com/Royo-Qiao/FastGPT.git
cd FastGPT/fastgpt-basic-openEuler-arm64

# 仅在 .env 不存在时创建配置和随机密钥
bash scripts/init-env.sh

# 启动前按自己的主机修改 .env 与 config.json，再执行：
bash scripts/preflight.sh
bash scripts/start.sh
```

`init-env.sh` 默认生成随机 root 密码与密钥；应以实际生成的 `.env` 为准，不能依赖旧说明中的固定初始密码。配置中已有环境专用的内网地址，需要替换为自己的绑定地址、服务地址和端口。`.env` 由 Git 忽略，请保留在本地。

`start.sh` 会调用预检并启动 Compose 服务；设置 `PULL_IMAGES=1` 时才显式执行镜像拉取。停止入口为 `bash scripts/stop.sh`，详细行为见对应脚本。MinerU 与模型服务有各自的启动流程，请分别阅读其文档与脚本。

## 验证边界与反馈

本次整理核对了仓库文件、脚本条件与文档入口，**没有执行部署、下载镜像、运行模型或验证目标硬件**。脚本存在、静态检查通过与服务实际可用是不同证据；部署后应使用目标服务的验证脚本与真实请求验收。

提交 [Issue](https://github.com/Royo-Qiao/FastGPT/issues) 时请附环境、具体脚本和脱敏错误信息，不要上传 `.env`、密钥、模型权重或私有文档。欢迎用可复现的结果完善说明。

仓库根目录提供 [MIT License](LICENSE)；外部 FastGPT、容器镜像、依赖与模型的使用仍遵循其各自许可。
