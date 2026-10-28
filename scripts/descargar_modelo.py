"""
Descarga el modelo de embeddings ONNX y su tokenizador para SQL Server 2025, y
prepara la variante sin padding que usa el proyecto.

Es el único script Python del proyecto y solo se usa en la instalación: no
genera embeddings ni consulta la base de datos. Todo el RAG se ejecuta dentro
de SQL Server (AI_GENERATE_EMBEDDINGS) y en GitHub Copilot (@mssql).

Modelo: nsense/all-MiniLM-L6-v2-onnx (licencia MIT, 384 dimensiones), el que
usa el ejemplo oficial de Microsoft Learn para CREATE EXTERNAL MODEL con
API_FORMAT = 'ONNX Runtime'.

Carpetas que genera:
  ORIGINAL     -> model.onnx + tokenizer.json tal como se publican
                  (se conserva como referencia y para repetir la comparación).
  SIN_PADDING  -> model.onnx + tokenizer.json con "padding": null. Es la que
                  usa LOCATION en database\\02_modelo_onnx.sql.

Por qué sin padding: el tokenizer.json original rellena siempre hasta 128
tokens con [PAD] y AIRuntimeHost promedia también esas posiciones, así que
todos los vectores comparten una gran componente [PAD]. Las distancias se
comprimen y aparece un sesgo por longitud del texto (ver
docs/instalacion_onnx.md, "Prueba del padding"). La truncación a 128 tokens
se mantiene, porque es el máximo que admite el modelo.

Uso (PowerShell como administrador, porque escribe en C:\\onnx_runtime):
    pip install huggingface_hub
    python scripts\\descargar_modelo.py
"""
import hashlib
import json
import os
import shutil

from huggingface_hub import hf_hub_download

REPO_ID = "nsense/all-MiniLM-L6-v2-onnx"
ARCHIVOS = ["model.onnx", "tokenizer.json"]   # lo que necesita LOCATION
ORIGINAL = r"C:\onnx_runtime\model\all-MiniLM-L6-v2-onnx"
SIN_PADDING = r"C:\onnx_runtime\model\minilm-sin-padding"


def sha256(ruta):
    h = hashlib.sha256()
    with open(ruta, "rb") as f:
        for bloque in iter(lambda: f.read(1024 * 1024), b""):
            h.update(bloque)
    return h.hexdigest()


# 1. Descarga del modelo original
os.makedirs(ORIGINAL, exist_ok=True)
for nombre in ARCHIVOS:
    print(f"Descargando {REPO_ID}/{nombre} ...")
    ruta = hf_hub_download(repo_id=REPO_ID, filename=nombre, local_dir=ORIGINAL)
    tam_mb = os.path.getsize(ruta) / 1024 / 1024
    print(f"  -> {ruta} ({tam_mb:.1f} MB) sha256={sha256(ruta)}")

# 2. Variante sin padding (la que registra 02_modelo_onnx.sql)
os.makedirs(SIN_PADDING, exist_ok=True)
shutil.copyfile(os.path.join(ORIGINAL, "model.onnx"), os.path.join(SIN_PADDING, "model.onnx"))

with open(os.path.join(ORIGINAL, "tokenizer.json"), encoding="utf-8") as f:
    tokenizer = json.load(f)
print(f"\nPadding original: {tokenizer.get('padding')}")
tokenizer["padding"] = None                      # sin relleno hasta 128 tokens
assert tokenizer["truncation"]["max_length"] == 128  # la truncación se mantiene

destino = os.path.join(SIN_PADDING, "tokenizer.json")
with open(destino, "w", encoding="utf-8") as f:
    json.dump(tokenizer, f, ensure_ascii=False)
print(f"  -> {destino} (padding desactivado) sha256={sha256(destino)}")

print("\nModelo listo. Siguiente paso: scripts\\preparar_onnx_runtime.ps1")
