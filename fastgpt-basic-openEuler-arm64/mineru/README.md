# MinerU PDF 解析服务

MinerU 是 FastGPT 的自定义 PDF 解析后端。本目录是自包含的离线部署包：镜像内置全部依赖（Python、PyTorch、CV 库）和模型权重，服务器端无需联网、无需挂载外部模型目录。

- **运行模式**：CPU（pipeline 后端），不占用 NPU
- **镜像**：`mineru:latest`（26.7GB，导出后 7.2GB）
- **端口**：`8010`（可在根目录 `.env` 中通过 `MINERU_BIND_ADDR` / `MINERU_PORT` 调整）
- **FastGPT 对接**：根目录 `config.json` 已预配置 `customPdfParse.url = http://172.16.2.198:8010/v2/parse/file`

## 目录结构

```
mineru/
├── Dockerfile                 # 镜像构建定义（重建时参考）
├── README.md                  # 本文件
├── parts/                     # 镜像分片包（500MB × 15 = 7.2GB）
│   ├── mineru.part.aa         # 分片 1
│   ├── ...
│   ├── mineru.part.ao         # 分片 15
│   ├── mineru.parts.sha256    # 各分片校验和
│   ├── mineru.full.sha256     # 合并后整体校验和
│   └── merge.sh               # 合并脚本（服务器端运行）
└── scripts/
    ├── deploy.sh              # 服务器一键部署：自动合并 + load + start + verify
    ├── load.sh                # 服务器：加载镜像（含分片检测）
    ├── start.sh               # 服务器：启动容器
    ├── stop.sh                # 服务器：停止容器
    ├── verify.sh              # 服务器：验证服务
    ├── build.sh               # macOS：重建镜像（需源码）
    ├── export.sh              # macOS：导出并切分为 500MB 分片
    └── verify-export.sh       # 通用：校验导出完整性
```

## 服务器端部署（离线）

### 方式一：一键部署（推荐）

自动检测分片、合并、加载、启动、验证，一站式完成：

```bash
cd /data/fastgpt-basic-openEuler-arm64/mineru
bash scripts/deploy.sh
```

### 方式二：分步部署

```bash
# 1. 合并分片（若 mineru.tar.gz 不存在则自动提示）
bash parts/merge.sh

# 2. 加载镜像（约 1-3 分钟）
bash scripts/load.sh

# 3. 启动容器
bash scripts/start.sh

# 4. 验证
bash scripts/verify.sh
```

首次启动模型加载需 1-2 分钟，`docker logs -f mineru` 看到 `Application startup` 即就绪。

## 与 FastGPT 的启动顺序

MinerU 是独立容器，与 FastGPT 的 Docker Compose 编排互不依赖。两者可任意顺序启动，但 FastGPT 解析 PDF 时需要 MinerU 已就绪。建议：

```bash
# 1. 先启 MinerU
cd fastgpt-basic-openEuler-arm64/mineru && bash scripts/deploy.sh

# 2. 再启 FastGPT
cd .. && bash scripts/start.sh
```

## 服务管理

```bash
docker logs -f mineru                          # 实时日志
docker restart mineru                          # 重启
bash mineru/scripts/stop.sh                    # 停止
bash mineru/scripts/start.sh                   # 再次启动
```

## 解析测试

```bash
curl -X POST http://172.16.2.198:8010/v2/parse/file \
  -F 'file=@test.pdf'
```

返回 JSON 包含 `markdown` 字段和页数。

## 重建镜像（仅在有网络的 macOS 上）

镜像已预构建并打包，通常无需重建。如需更新 MinerU 版本：

1. 准备源码与模型目录（`<work>/mineru/` 下含 `MinerU`、`MinerU_fastgpt`、`huggingface`）
2. 执行：

```bash
WORK_DIR=/path/to/work bash scripts/build.sh
bash scripts/export.sh     # 导出并自动切分为 500MB 分片
bash scripts/verify-export.sh
```

`WORK_DIR` 指向包含 `mineru/` 源码目录的父目录。

## 技术说明

- **分片机制**：7.2GB 镜像切分为 15 个 500MB 分片，避免 U 盘传输大文件出错（exFAT/NTFS 在拷贝 4GB+ 文件时偶发截断）
- **基础镜像**：`quay.m.daocloud.io/ascend/vllm-ascend:v0.13.0rc3`（仅借用其 Python 3.10 + 系统库环境，不使用 NPU）
- **安装方式**：`pip install "mineru[core]"` 从 PyPI 直接安装，避免 editable 模式的 setuptools 构建依赖问题
- **模型内置**：`PDF-Extract-Kit-1.0` 模型（2.0GB）已 COPY 进镜像，`MINERU_MODEL_SOURCE=local` 阻止运行时联网下载
- **CPU 模式**：`CPU=True` 环境变量使 MinerU 使用 CPU 推理，适合无 GPU 的解析场景
