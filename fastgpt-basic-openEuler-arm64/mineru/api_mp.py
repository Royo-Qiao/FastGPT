"""
MinerU PDF 解析 FastAPI 服务（mineru 3.x 适配版）

设计差异（相对旧版 api_mp.py）：
- 旧版手动拼装 pipeline_doc_analyze + result_to_middle_json + union_make + prepare_env
  这些 API 在 mineru 3.x 中签名已变（doc_analyze → doc_analyze_streaming，回调式）
- 新版改用顶层 API mineru.cli.common.do_parse，一次调用完成解析+写盘
- 输出从磁盘读取 .md，嵌入图片为 base64，返回 JSON

环境变量：
  PORT, HOST                  - 服务监听
  MINERU_BACKEND              - pipeline (默认) / vlm-transformers / vlm-sglang-engine / vlm-sglang-client
  MINERU_SERVER_URL           - vlm-sglang-client 必填
  MINERU_LANG                 - ch (默认) / en / ...
  MINERU_PARSE_METHOD         - auto (默认) / ocr / txt
  MINERU_FORMULA_ENABLE       - true (默认)
  MINERU_TABLE_ENABLE         - true (默认)
  TABLE_OUTPUT_FORMAT         - markdown (默认) / html
  CPU                         - True 时强制 CPU 模式
  PROCESSES_PER_GPU           - 每 GPU/CPU 的 worker 数 (默认 1)
"""
import os
import time
import base64
import tempfile
import asyncio
import multiprocessing as mp
from pathlib import Path
from contextlib import asynccontextmanager
from concurrent.futures import ProcessPoolExecutor

from fastapi import FastAPI, File, UploadFile, HTTPException
import uvicorn
from loguru import logger

# 全局进程池
_pool: ProcessPoolExecutor | None = None


# ─── 配置 ────────────────────────────────────────────────────────────────────
class MinerUConfig:
    def __init__(self):
        self.backend = os.getenv("MINERU_BACKEND", "pipeline")
        self.server_url = os.getenv("MINERU_SERVER_URL", None)
        self.lang = os.getenv("MINERU_LANG", "ch")
        self.parse_method = os.getenv("MINERU_PARSE_METHOD", "auto")
        self.formula_enable = os.getenv("MINERU_FORMULA_ENABLE", "true").lower() == "true"
        self.table_enable = os.getenv("MINERU_TABLE_ENABLE", "true").lower() == "true"
        self.table_output_format = os.getenv("TABLE_OUTPUT_FORMAT", "markdown").lower()
        if self.table_output_format not in ("html", "markdown"):
            logger.warning(f"Invalid TABLE_OUTPUT_FORMAT '{self.table_output_format}', use markdown")
            self.table_output_format = "markdown"

        valid_backends = {"pipeline", "vlm-transformers", "vlm-sglang-engine", "vlm-sglang-client"}
        if self.backend not in valid_backends:
            logger.warning(f"Invalid backend {self.backend}, fall back to pipeline")
            self.backend = "pipeline"

        if self.backend == "vlm-sglang-client" and not self.server_url:
            raise ValueError("MINERU_SERVER_URL is required for vlm-sglang-client backend")


config = MinerUConfig()


# ─── Worker（子进程内执行解析）─────────────────────────────────────────────
def _worker_init():
    pid = os.getpid()
    logger.info(f"Worker {pid} initialized (lazy model load on first request)")


def _parse_document(pdf_bytes: bytes, file_name: str, backend: str, cfg: dict) -> dict:
    """子进程内运行：调用 do_parse，从结果目录读取 markdown + 嵌图。"""
    from mineru.cli.common import do_parse

    pid = os.getpid()
    logger.info(f"Worker {pid} parsing {file_name} (backend={backend})")
    t0 = time.time()

    with tempfile.TemporaryDirectory() as output_dir:
        # 调用 mineru 顶层 API，关闭所有不需要的 dump 加速
        do_parse(
            output_dir=output_dir,
            pdf_file_names=[file_name],
            pdf_bytes_list=[pdf_bytes],
            p_lang_list=[cfg["lang"]],
            backend=backend,
            parse_method=cfg["parse_method"],
            formula_enable=cfg["formula_enable"],
            table_enable=cfg["table_enable"],
            server_url=cfg.get("server_url"),
            f_draw_layout_bbox=False,
            f_draw_span_bbox=False,
            f_dump_md=True,
            f_dump_middle_json=False,
            f_dump_model_output=False,
            f_dump_orig_pdf=False,
            f_dump_content_list=False,
        )

        # 输出结构：{output_dir}/{file_name}/{parse_method 或 vlm}/{file_name}.md
        # 对 pipeline backend，parse_method = auto/ocr/txt
        # 对 vlm-* backend，prepare_env 内部传 "vlm"
        candidates = list(Path(output_dir).glob(f"{file_name}/*/{file_name}.md"))
        if not candidates:
            # 兜底：找任何 .md
            candidates = list(Path(output_dir).rglob("*.md"))
        if not candidates:
            raise FileNotFoundError(f"do_parse 没有产出 markdown 文件（{output_dir} 下未找到 .md）")

        md_path = candidates[0]
        image_dir = md_path.parent / "images"
        logger.info(f"Worker {pid} markdown produced: {md_path}")

        md_content = md_path.read_text(encoding="utf-8", errors="replace")
        md_with_images = _embed_images_as_base64(
            md_content,
            str(image_dir) if image_dir.exists() else str(md_path.parent),
            table_format=cfg.get("table_output_format", "markdown"),
        )

        # 页数估算：以 images/ 中布局图数量近似（每页一张）
        pages = len(list(image_dir.glob("*"))) if image_dir.exists() else 1

        logger.info(f"Worker {pid} done in {time.time()-t0:.2f}s, pages={pages}")
        return {
            "success": True,
            "message": "",
            "markdown": md_with_images,
            "pages": pages,
        }


# ─── 图片 / 表格后处理 ────────────────────────────────────────────────────
def _img_to_base64(img_path: str) -> str:
    with open(img_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def _html_table_to_markdown(html_table: str) -> str:
    """HTML 表格 → Markdown，正确处理 colspan / rowspan。"""
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html_table, "html.parser")
    table = soup.find("table")
    if not table:
        return ""
    rows = table.find_all("tr")
    if not rows:
        return ""

    max_cols = 0
    for row in rows:
        cells = row.find_all(["td", "th"])
        col_count = sum(int(c.get("colspan", 1)) for c in cells)
        max_cols = max(max_cols, col_count)

    matrix: list[list] = [[None for _ in range(max_cols)] for _ in range(len(rows))]
    for r_idx, row in enumerate(rows):
        c_idx = 0
        for cell in row.find_all(["td", "th"]):
            while c_idx < max_cols and matrix[r_idx][c_idx] is not None:
                c_idx += 1
            if c_idx >= max_cols:
                break
            colspan = int(cell.get("colspan", 1))
            rowspan = int(cell.get("rowspan", 1))
            content = cell.get_text(strip=True)
            for r in range(r_idx, min(r_idx + rowspan, len(rows))):
                for c in range(c_idx, min(c_idx + colspan, max_cols)):
                    if matrix[r][c] is None:
                        matrix[r][c] = content if (r == r_idx and c == c_idx) else ""
            c_idx += colspan

    for r in range(len(matrix)):
        for c in range(len(matrix[r])):
            if matrix[r][c] is None:
                matrix[r][c] = ""

    out = []
    for i, row in enumerate(matrix):
        out.append("| " + " | ".join(row) + " |")
        if i == 0:
            out.append("| " + " | ".join(["---"] * len(row)) + " |")
    return "\n".join(out)


def _embed_images_as_base64(md_content: str, image_dir: str, table_format: str = "markdown") -> str:
    """图片引用替换为 base64 data URL；可选将 HTML 表格转 Markdown。"""
    md_content = md_content.encode("utf-8", "replace").decode("utf-8")
    lines = md_content.split("\n")
    out: list[str | None] = []

    i = 0
    while i < len(lines):
        line = lines[i]
        if line is None:
            i += 1
            continue

        if line.startswith("![") and "](" in line and ")" in line:
            start = line.index("](") + 2
            end = line.index(")", start)
            img_rel = line[start:end]
            img_name = os.path.basename(img_rel)
            img_path = os.path.join(image_dir, img_name)
            if os.path.exists(img_path):
                b64 = _img_to_base64(img_path)
                out.append(f"![](data:image/png;base64,{b64}{line[end:]}")
            else:
                out.append(line)
        elif "<table" in line.lower():
            # 找到 </table> 结束
            j = i
            while j < len(lines) and "</table>" not in (lines[j] or "").lower():
                j += 1
            full_table = "\n".join(lines[i : j + 1])
            if table_format == "markdown":
                out.append(_html_table_to_markdown(full_table))
            else:
                out.append(full_table)
            i = j  # 跳过原始表格行
        else:
            out.append(line)
        i += 1

    return "\n".join(x for x in out if x is not None)


# ─── FastAPI ─────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        mp.set_start_method("spawn")
    except RuntimeError:
        pass

    global _pool
    workers = int(os.getenv("PROCESSES_PER_GPU", "1"))
    logger.info(f"Starting process pool: workers={workers}, backend={config.backend}, cpu_mode={os.getenv('CPU')}")
    _pool = ProcessPoolExecutor(max_workers=workers, initializer=_worker_init)
    yield
    if _pool:
        _pool.shutdown(wait=True)
    logger.info("Application shutdown")


app = FastAPI(title="MinerU Parser API", version="2.0.0", lifespan=lifespan)


@app.get("/health")
async def health():
    return {"status": "ok", "backend": config.backend}


@app.post("/v2/parse/file")
async def parse_file(file: UploadFile = File(...)):
    """解析上传的 PDF / 图片，返回 markdown + base64 内嵌图片。"""
    allowed = {".pdf", ".png", ".jpeg", ".jpg"}
    suffix = Path(file.filename).suffix.lower()
    if suffix not in allowed:
        raise HTTPException(400, f"Unsupported file type: {suffix}. Allowed: {sorted(allowed)}")

    try:
        pdf_bytes = await file.read()
        file_stem = Path(file.filename).stem
        t0 = time.time()

        cfg = {
            "lang": config.lang,
            "parse_method": config.parse_method,
            "formula_enable": config.formula_enable,
            "table_enable": config.table_enable,
            "server_url": config.server_url,
            "table_output_format": config.table_output_format,
        }

        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            _pool, _parse_document, pdf_bytes, file_stem, config.backend, cfg
        )

        logger.info(f"Request done in {time.time()-t0:.2f}s, pages={result.get('pages')}")
        return result
    except Exception as e:
        logger.exception(f"parse_file failed: {file.filename}")
        raise HTTPException(500, f"Failed to parse: {e}")


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8010"))
    host = os.getenv("HOST", "0.0.0.0")
    logger.info(f"Starting MinerU API server on {host}:{port}")
    uvicorn.run(app, host=host, port=port)
