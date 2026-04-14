#!/usr/bin/env python3
"""
z-image-mcp — Serveur MCP pour Z-Image-Turbo (backend MLX natif)
=================================================================

Backend MLX Apple Silicon — 2x plus rapide que diffusers, pas de swap.
Appelle generate_mlx.py du projet z-image-turbo-mlx en subprocess.
La mémoire est libérée après chaque génération.

Architecture:
  LM Studio (Qwen 3.5) ──MCP stdio──▶ ce serveur ──▶ generate_mlx.py ──▶ image
"""

import os
import sys
import json
import time
import subprocess
import logging
import random
from pathlib import Path
from datetime import datetime

from mcp.server.fastmcp import FastMCP

# ── Configuration ──────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).parent.resolve()
OUTPUT_DIR = Path(
    os.environ.get("ZIMAGE_OUTPUT_DIR", os.path.expanduser("~/Pictures/z-image-mcp"))
)

# Chemins vers le projet z-image-turbo-mlx (installé par install.sh)
MLX_PROJECT = Path(os.environ.get(
    "ZIMAGE_MLX_PROJECT",
    os.path.expanduser("~/z-image-turbo-mlx")
))
MLX_PYTHON = MLX_PROJECT / ".venv" / "bin" / "python"
MLX_GENERATE = MLX_PROJECT / "src" / "generate_mlx.py"
MLX_MODEL_PATH = Path(os.environ.get(
    "ZIMAGE_MLX_MODEL",
    os.path.expanduser("~/models/mlx/Z-Image-Turbo-MLX")
))

DEFAULT_WIDTH = int(os.environ.get("ZIMAGE_DEFAULT_WIDTH", "1024"))
DEFAULT_HEIGHT = int(os.environ.get("ZIMAGE_DEFAULT_HEIGHT", "1024"))
DEFAULT_STEPS = int(os.environ.get("ZIMAGE_DEFAULT_STEPS", "9"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [z-image-mcp] %(levelname)s %(message)s",
    stream=sys.stderr,
)
log = logging.getLogger("z-image-mcp")

# ── Vérifications ─────────────────────────────────────────────────────────

def _check_setup() -> str | None:
    if not MLX_PYTHON.exists():
        return f"Python venv MLX introuvable: {MLX_PYTHON}\nLancez install.sh"
    if not MLX_GENERATE.exists():
        return f"generate_mlx.py introuvable: {MLX_GENERATE}\nLancez install.sh"
    if not MLX_MODEL_PATH.exists():
        return f"Poids MLX introuvables: {MLX_MODEL_PATH}\nLancez install.sh"
    return None

# ── Presets de résolution ─────────────────────────────────────────────────

ASPECT_PRESETS = {
    "1:1": (1024, 1024),
    "16:9": (1280, 720),
    "9:16": (720, 1280),
    "4:3": (1152, 864),
    "3:4": (864, 1152),
    "3:2": (1216, 832),
    "2:3": (832, 1216),
}

# ── Serveur MCP ───────────────────────────────────────────────────────────

mcp = FastMCP("z-image-mcp")


@mcp.tool()
def generate_image(
    prompt: str,
    width: int = DEFAULT_WIDTH,
    height: int = DEFAULT_HEIGHT,
    steps: int = DEFAULT_STEPS,
    seed: int = -1,
    aspect_ratio: str = "",
    cache: str = "",
) -> str:
    """
    Generate an image from a text prompt using Z-Image-Turbo (MLX native).

    2x faster than diffusers/PyTorch. Memory freed after each generation.

    Args:
        prompt: Detailed text description of the image. Be specific about
                subject, style, lighting, composition. English or Chinese.
                Tips: add 'volumetric lighting', 'cinematic', '4k' for quality.
        width: Image width in pixels (multiple of 8). Default 1024.
        height: Image height in pixels (multiple of 8). Default 1024.
        steps: Inference steps (default 9, recommended 5-12).
        seed: Random seed for reproducibility. -1 for random.
        aspect_ratio: Preset ratio overriding width/height.
                      Options: 1:1, 16:9, 9:16, 4:3, 3:4, 3:2, 2:3
        cache: LeMiCa speed mode: slow, medium, fast. Empty = disabled.

    Returns:
        Summary with file path, resolution, seed, and generation time.
    """
    err = _check_setup()
    if err:
        return f"ERREUR: {err}"

    if not prompt.strip():
        return "ERREUR: Le prompt est vide."

    # Résolution
    if aspect_ratio and aspect_ratio in ASPECT_PRESETS:
        width, height = ASPECT_PRESETS[aspect_ratio]
    width = (width // 8) * 8
    height = (height // 8) * 8

    # Seed
    if seed < 0:
        seed = random.randint(0, 2**32 - 1)

    # Fichier de sortie
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"zimage_{timestamp}_{seed}.png"
    filepath = OUTPUT_DIR / filename

    log.info(f"Génération MLX {width}x{height}, {steps} steps, seed={seed}")
    log.info(f"Prompt: {prompt[:120]}{'…' if len(prompt) > 120 else ''}")

    cmd = [
        str(MLX_PYTHON),
        str(MLX_GENERATE),
        "--prompt", prompt,
        "--output", str(filepath),
        "--seed", str(seed),
        "--steps", str(steps),
        "--height", str(height),
        "--width", str(width),
        "--model_path", str(MLX_MODEL_PATH),
    ]

    if cache and cache in ("slow", "medium", "fast"):
        cmd.extend(["--cache", cache])

    t0 = time.time()

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600,
            cwd=str(MLX_PROJECT),
        )

        elapsed = round(time.time() - t0, 2)

        if result.returncode != 0:
            log.error(f"generate_mlx.py erreur (code {result.returncode})")
            log.error(f"stderr: {result.stderr[-500:]}")
            return (
                f"ERREUR: Génération échouée (code {result.returncode})\n"
                f"Détails: {result.stderr[-300:]}"
            )

        if not filepath.exists():
            return "ERREUR: L'image n'a pas été générée."

        log.info(f"Image → {filepath} ({elapsed}s)")

        return (
            f"Image générée avec succès !\n"
            f"Fichier : {filepath}\n"
            f"Résolution : {width}x{height}\n"
            f"Seed : {seed}\n"
            f"Steps : {steps}\n"
            f"Temps : {elapsed}s"
        )

    except subprocess.TimeoutExpired:
        return "ERREUR: Timeout (>10 minutes)."
    except Exception as e:
        log.exception("Erreur inattendue")
        return f"ERREUR: {str(e)}"


@mcp.tool()
def get_status() -> str:
    """Get the status of the Z-Image MLX server."""
    err = _check_setup()
    status = {
        "ready": err is None,
        "error": err,
        "backend": "MLX (Apple Silicon native)",
        "mlx_project": str(MLX_PROJECT),
        "mlx_model": str(MLX_MODEL_PATH),
        "output_directory": str(OUTPUT_DIR),
        "default_resolution": f"{DEFAULT_WIDTH}x{DEFAULT_HEIGHT}",
        "default_steps": DEFAULT_STEPS,
        "aspect_presets": list(ASPECT_PRESETS.keys()),
    }
    return json.dumps(status, indent=2, ensure_ascii=False)


@mcp.tool()
def list_generated_images(last_n: int = 10) -> str:
    """List recently generated images.

    Args:
        last_n: Number of recent images to list (default 10).
    """
    if not OUTPUT_DIR.exists():
        return "Aucune image générée."
    pngs = sorted(
        OUTPUT_DIR.glob("zimage_*.png"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if not pngs:
        return "Aucune image générée."
    lines = [
        f"  {p.name}  ({p.stat().st_size/1048576:.1f} MB, "
        f"{datetime.fromtimestamp(p.stat().st_mtime).strftime('%Y-%m-%d %H:%M')})"
        for p in pngs[:last_n]
    ]
    return f"Images ({len(lines)}/{len(pngs)}) :\n" + "\n".join(lines)


if __name__ == "__main__":
    log.info("z-image-mcp démarré (backend MLX)")
    log.info(f"  MLX projet : {MLX_PROJECT}")
    log.info(f"  Modèle     : {MLX_MODEL_PATH}")
    log.info(f"  Sortie     : {OUTPUT_DIR}")
    err = _check_setup()
    if err:
        log.warning(f"  ⚠ {err}")
    else:
        log.info("  ✓ Prêt")
    mcp.run(transport="stdio")
