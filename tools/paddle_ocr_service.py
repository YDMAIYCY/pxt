from __future__ import annotations

import os
import tempfile
from typing import Any

from fastapi import FastAPI, File, Form, UploadFile
from fastapi.responses import JSONResponse
from paddleocr import PaddleOCR


# ========== 参数配置 ==========
OCR_LANGUAGE = os.getenv("PADDLE_OCR_LANG", "ch")
USE_ANGLE_CLS = os.getenv("PADDLE_OCR_USE_ANGLE_CLS", "true").lower() == "true"


# ========== 服务初始化 ==========
app = FastAPI(title="PXT PaddleOCR Service")
ocr_engine = PaddleOCR(use_angle_cls=USE_ANGLE_CLS, lang=OCR_LANGUAGE)


# ========== 数据处理 ==========
def _extract_lines(result: Any) -> list[dict[str, Any]]:
    lines: list[dict[str, Any]] = []

    for page in result or []:
        for item in page or []:
            if not isinstance(item, (list, tuple)) or len(item) < 2:
                continue
            box = item[0]
            text_score = item[1]
            if not isinstance(text_score, (list, tuple)) or not text_score:
                continue
            text = str(text_score[0]).strip()
            if not text:
                continue
            score = float(text_score[1]) if len(text_score) > 1 else None
            lines.append({"text": text, "score": score, "box": box})

    return lines


# ========== API ==========
@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "engine": "paddleocr"}


@app.post("/ocr")
async def recognize(
    image: UploadFile = File(...),
    language: str = Form(default="zh-CN"),
) -> JSONResponse:
    suffix = os.path.splitext(image.filename or "")[1] or ".png"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
        temp_file.write(await image.read())
        temp_path = temp_file.name

    try:
        result = ocr_engine.ocr(temp_path, cls=USE_ANGLE_CLS)
        lines = _extract_lines(result)
        raw_text = "\n".join(line["text"] for line in lines).strip()
        return JSONResponse(
            {
                "engine": "paddleocr",
                "language": language,
                "raw_text": raw_text,
                "lines": lines,
            }
        )
    finally:
        try:
            os.remove(temp_path)
        except OSError:
            pass


# ========== 主程序入口 ==========
if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
