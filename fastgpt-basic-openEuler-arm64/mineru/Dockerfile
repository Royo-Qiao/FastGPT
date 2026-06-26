FROM quay.m.daocloud.io/ascend/vllm-ascend:v0.13.0rc3
# 基于已有的 Ascend vllm 镜像，包含 Python 3.10 + PyTorch + CANN

LABEL maintainer="MinerU FastGPT Integration"
LABEL description="MinerU PDF parser with all dependencies pre-installed"

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive
ENV MINERU_MODEL_SOURCE=local
ENV HF_HOME=/models/huggingface
ENV HUGGINGFACE_HUB_CACHE=/models/huggingface/hub
ENV PORT=8010
ENV HOST=0.0.0.0
ENV CPU=True
ENV PROCESSES_PER_GPU=1

# 创建目录结构
RUN mkdir -p /models/mineru /models/huggingface /app

# 安装系统依赖（如果需要）
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 升级 pip 和构建工具，确保 setuptools 可用
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# 卸载基础镜像内置的 torch_npu（MinerU CPU 模式不需要 NPU）
# transformers 库会无条件 import torch_npu 探测设备，没挂 NPU 驱动会崩溃。
# 卸载后 importlib.util.find_spec("torch_npu") 返回 None，
# is_torch_npu_available() 提前返回 False，永不触发 import torch_npu。
RUN pip uninstall -y torch_npu torch-npu 2>/dev/null || true

# 安装 MinerU（从 PyPI 直接安装，不需要本地 editable 模式）
RUN pip install --no-cache-dir "mineru[core]"

# 2. 安装额外的 API 依赖
RUN pip install --no-cache-dir \
    fastapi \
    uvicorn \
    python-multipart

# 3. 复制 API 代码
COPY mineru/MinerU_fastgpt /app/api

# 3.1 用 mineru 3.x 适配版替换 api_mp.py
# 旧版基于 mineru 2.x API（doc_analyze 等手工拼装中间步骤）
# 新版改用 mineru.cli.common.do_parse 顶层 API，签名稳定
COPY deploy/mineru-scripts/api_mp.py /app/api/api_mp.py

# 4. 复制模型（单独一层，方便复用）
COPY mineru/huggingface /models/huggingface

# 验证安装
RUN python -c "import mineru; print('MinerU installed successfully')"

# 清理 pip 缓存
RUN pip cache purge && rm -rf /root/.cache/pip

# 设置工作目录为 API
WORKDIR /app/api

# 暴露端口
EXPOSE 8010

# 启动命令
CMD ["python", "api_mp.py"]
