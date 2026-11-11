from fastapi import FastAPI
import uvicorn

from formula_api import router, ocr_router

app = FastAPI(title="MindTrace OCR Service")
app.include_router(router, prefix="/api/v1")
app.include_router(ocr_router, prefix="/api/v1")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
