#!/bin/bash
# ============================================================================
#  z-image-mcp — Installateur interactif
#  Génération d'images Z-Image-Turbo via MCP pour LM Studio (macOS)
# ============================================================================
#
#  Usage : curl -sSL <url>/install.sh | bash
#     ou : ./install.sh
#
#  Ce script :
#    1. Vérifie les prérequis (macOS, Apple Silicon, Python, Homebrew)
#    2. Installe les dépendances Python (PyTorch, diffusers, MCP SDK)
#    3. Détecte la mémoire et recommande une configuration
#    4. Configure mcp.json pour LM Studio
#    5. Teste le pipeline
#
# ============================================================================
set -euo pipefail

# ── Couleurs et formatage ─────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${BLUE}→${NC} $1"; }
ask()  { echo -en "  ${CYAN}?${NC} $1 "; }

# ── Variables ─────────────────────────────────────────────────────────────

INSTALL_DIR="$HOME/z-image-mcp"
VENV_DIR="$INSTALL_DIR/.venv"
MCP_JSON="$HOME/.lmstudio/mcp.json"
PICTURES_DIR="$HOME/Pictures/z-image-mcp"

# ── Bannière ──────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                                                       ║${NC}"
echo -e "${BOLD}║   ${CYAN}z-image-mcp${NC}${BOLD} — Image Generation for LM Studio        ║${NC}"
echo -e "${BOLD}║   Z-Image-Turbo (6B) via MCP sur macOS Apple Silicon  ║${NC}"
echo -e "${BOLD}║                                                       ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 1 : Vérification des prérequis
# ══════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}[1/6] Vérification du système${NC}"
echo ""

# macOS
if [[ "$(uname)" != "Darwin" ]]; then
    fail "Ce script nécessite macOS. Système détecté : $(uname)"
    exit 1
fi
ok "macOS détecté"

# Apple Silicon
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    fail "Apple Silicon requis. Architecture détectée : $ARCH"
    echo "     Z-Image-Turbo nécessite MPS (Metal Performance Shaders)"
    echo "     qui n'est disponible que sur les Mac avec puce M1/M2/M3/M4."
    exit 1
fi
ok "Apple Silicon ($ARCH)"

# Mémoire
MEM_GB=$(sysctl -n hw.memsize | awk '{printf "%.0f", $1/1073741824}')
ok "Mémoire unifiée : ${MEM_GB} GB"

if (( MEM_GB < 16 )); then
    fail "16 GB minimum requis. Votre Mac n'a que ${MEM_GB} GB."
    echo "     Z-Image-Turbo nécessite ~14-20 GB pendant la génération."
    exit 1
elif (( MEM_GB < 32 )); then
    warn "Avec ${MEM_GB} GB, la génération fonctionnera mais sera limitée"
    warn "à des résolutions ≤ 512×512. Un modèle LM Studio très léger"
    warn "(≤ 4B) est recommandé."
elif (( MEM_GB < 48 )); then
    ok "Avec ${MEM_GB} GB, vous pourrez générer jusqu'en 1280×720"
    ok "avec un modèle LM Studio de 4-9B."
else
    ok "Avec ${MEM_GB} GB, vous avez une marge confortable."
fi

# Homebrew
if ! command -v brew &>/dev/null; then
    warn "Homebrew non détecté."
    ask "Installer Homebrew ? (recommandé) [O/n]"
    read -r REPLY
    if [[ -z "$REPLY" || "$REPLY" =~ ^[OoYy]$ ]]; then
        info "Installation de Homebrew…"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
        ok "Homebrew installé"
    else
        fail "Homebrew est nécessaire pour installer Python."
        echo "     Installez-le manuellement :"
        echo '     /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi
else
    ok "Homebrew présent"
fi

# Python
PYTHON=""
for cmd in python3.12 python3.11 python3.10 python3; do
    if command -v "$cmd" &>/dev/null; then
        ver=$("$cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        major=$(echo "$ver" | cut -d. -f1)
        minor=$(echo "$ver" | cut -d. -f2)
        if [[ "$major" -ge 3 && "$minor" -ge 10 && "$minor" -le 12 ]]; then
            PYTHON="$cmd"
            break
        fi
    fi
done

if [[ -z "$PYTHON" ]]; then
    warn "Python 3.10-3.12 non trouvé."
    ask "Installer Python 3.12 via Homebrew ? [O/n]"
    read -r REPLY
    if [[ -z "$REPLY" || "$REPLY" =~ ^[OoYy]$ ]]; then
        info "Installation de Python 3.12…"
        brew install python@3.12
        PYTHON="python3.12"
        ok "Python 3.12 installé"
    else
        fail "Python 3.10-3.12 est requis."
        exit 1
    fi
else
    ok "Python : $PYTHON ($("$PYTHON" --version 2>&1))"
fi

# LM Studio
if [[ -d "/Applications/LM Studio.app" ]]; then
    ok "LM Studio détecté"
else
    warn "LM Studio non détecté dans /Applications"
    warn "Installez-le depuis https://lmstudio.ai/download"
    warn "L'installation continue — vous pourrez configurer LM Studio après."
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 2 : Configuration
# ══════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}[2/6] Configuration${NC}"
echo ""

# Résolution par défaut
echo "  Résolution par défaut pour la génération d'images :"
echo ""
echo "    1) 512×512   — Rapide (~30s), recommandé pour ≤ 24 GB"
echo "    2) 768×768   — Équilibré (~60s), recommandé pour 32 GB"
echo "    3) 1024×1024 — Haute qualité (~2-3 min), pour ≥ 48 GB"
echo "    4) 1280×720  — Cinématique 16:9 (~90s), pour ≥ 36 GB"
echo ""

if (( MEM_GB <= 24 )); then
    DEFAULT_CHOICE=1
elif (( MEM_GB <= 36 )); then
    DEFAULT_CHOICE=2
elif (( MEM_GB <= 48 )); then
    DEFAULT_CHOICE=4
else
    DEFAULT_CHOICE=3
fi

ask "Votre choix [${DEFAULT_CHOICE}]:"
read -r RES_CHOICE
RES_CHOICE=${RES_CHOICE:-$DEFAULT_CHOICE}

case $RES_CHOICE in
    1) DEF_W=512;  DEF_H=512  ;;
    2) DEF_W=768;  DEF_H=768  ;;
    3) DEF_W=1024; DEF_H=1024 ;;
    4) DEF_W=1280; DEF_H=720  ;;
    *) DEF_W=512;  DEF_H=512  ;;
esac
ok "Résolution par défaut : ${DEF_W}×${DEF_H}"

# GPU VRAM
echo ""
CURRENT_VRAM=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo "0")
RECOMMENDED_VRAM=$(( (MEM_GB - 4) * 1024 ))
MAX_VRAM=$(( (MEM_GB - 2) * 1024 ))

if (( CURRENT_VRAM > 0 && CURRENT_VRAM < RECOMMENDED_VRAM )); then
    warn "Limite GPU actuelle : $(( CURRENT_VRAM / 1024 )) GB"
    warn "Recommandé : $(( RECOMMENDED_VRAM / 1024 )) GB (${MEM_GB} GB - 4 GB pour macOS)"
    ask "Augmenter la limite GPU à $(( RECOMMENDED_VRAM / 1024 )) GB ? [O/n]"
    read -r REPLY
    if [[ -z "$REPLY" || "$REPLY" =~ ^[OoYy]$ ]]; then
        sudo sysctl iogpu.wired_limit_mb=$RECOMMENDED_VRAM
        ok "Limite GPU mise à $(( RECOMMENDED_VRAM / 1024 )) GB"
        warn "Ce réglage se réinitialise au redémarrage du Mac."
        warn "Pour le rendre permanent, exécutez après l'installation :"
        echo "     sudo tee /Library/LaunchDaemons/com.gpu.vram.plist > /dev/null << 'PLIST'"
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0"><dict>'
        echo '<key>Label</key><string>com.gpu.vram</string>'
        echo '<key>ProgramArguments</key><array>'
        echo "<string>/usr/sbin/sysctl</string><string>iogpu.wired_limit_mb=${RECOMMENDED_VRAM}</string>"
        echo '</array><key>RunAtLoad</key><true/>'
        echo '</dict></plist>'
        echo "PLIST"
    fi
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 3 : Installation des fichiers
# ══════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}[3/6] Installation${NC}"
echo ""

# Dossier du projet
if [[ -d "$INSTALL_DIR" ]]; then
    warn "Dossier $INSTALL_DIR existant."
    ask "Réinstaller ? Les images générées seront conservées. [O/n]"
    read -r REPLY
    if [[ -z "$REPLY" || "$REPLY" =~ ^[OoYy]$ ]]; then
        rm -rf "$INSTALL_DIR/.venv" "$INSTALL_DIR/server.py" "$INSTALL_DIR/test_generate.py"
        ok "Ancienne installation nettoyée"
    else
        echo "  Installation annulée."
        exit 0
    fi
fi

mkdir -p "$INSTALL_DIR"

# ── server.py (généré inline) ────────────────────────────────────────────

cat > "$INSTALL_DIR/server.py" << 'SERVERPY'
#!/usr/bin/env python3
"""
z-image-mcp — Serveur MCP pour Z-Image-Turbo (diffusers/MPS)
Optimisé pour Mac Apple Silicon.
"""

import os, sys, json, time, logging, gc
from pathlib import Path
from datetime import datetime
from mcp.server.fastmcp import FastMCP

OUTPUT_DIR = Path(os.environ.get("ZIMAGE_OUTPUT_DIR", os.path.expanduser("~/Pictures/z-image-mcp")))
MODEL_ID = os.environ.get("ZIMAGE_MODEL_ID", "Tongyi-MAI/Z-Image-Turbo")
DEFAULT_WIDTH = int(os.environ.get("ZIMAGE_DEFAULT_WIDTH", "512"))
DEFAULT_HEIGHT = int(os.environ.get("ZIMAGE_DEFAULT_HEIGHT", "512"))
DEFAULT_STEPS = int(os.environ.get("ZIMAGE_DEFAULT_STEPS", "9"))
DEFAULT_GUIDANCE = float(os.environ.get("ZIMAGE_DEFAULT_GUIDANCE", "0.0"))

logging.basicConfig(level=logging.INFO, format="%(asctime)s [z-image-mcp] %(levelname)s %(message)s", stream=sys.stderr)
log = logging.getLogger("z-image-mcp")

_pipe = None
_device = None

def _get_pipeline():
    global _pipe, _device
    if _pipe is not None:
        return _pipe
    log.info("Chargement du pipeline Z-Image-Turbo…")
    import torch
    from diffusers import ZImagePipeline
    if torch.backends.mps.is_available():
        _device = "mps"; dtype = torch.bfloat16; log.info("  Device : MPS")
    elif torch.cuda.is_available():
        _device = "cuda"; dtype = torch.bfloat16; log.info("  Device : CUDA")
    else:
        _device = "cpu"; dtype = torch.float32; log.warning("  Device : CPU")
    _pipe = ZImagePipeline.from_pretrained(MODEL_ID, torch_dtype=dtype, low_cpu_mem_usage=True)
    try:
        _pipe.enable_sequential_cpu_offload()
        log.info("  ✓ Sequential CPU offload")
    except Exception:
        _pipe.to(_device)
    try: _pipe.enable_attention_slicing(); log.info("  ✓ Attention slicing")
    except Exception: pass
    try: _pipe.enable_vae_slicing(); log.info("  ✓ VAE slicing")
    except Exception: pass
    try: _pipe.enable_vae_tiling(); log.info("  ✓ VAE tiling")
    except Exception: pass
    log.info("Pipeline prêt.")
    return _pipe

def _unload_pipeline():
    global _pipe, _device
    if _pipe is None: return False
    del _pipe; _pipe = None; _device = None
    import torch
    if torch.backends.mps.is_available(): torch.mps.empty_cache()
    elif torch.cuda.is_available(): torch.cuda.empty_cache()
    gc.collect(); log.info("Pipeline déchargé.")
    return True

ASPECT_PRESETS = {
    "1:1": (512,512), "16:9": (640,368), "9:16": (368,640),
    "4:3": (576,432), "3:4": (432,576),
    "hd_1:1": (1024,1024), "hd_16:9": (1280,720), "hd_9:16": (720,1280),
    "hd_4:3": (1152,864), "hd_3:4": (864,1152),
}

mcp = FastMCP("z-image-mcp")

@mcp.tool()
def preload_model() -> str:
    """Pre-load Z-Image-Turbo into memory. Call BEFORE first image generation to avoid timeout. First load downloads ~12 GB on first ever use."""
    t0 = time.time(); _get_pipeline()
    return f"Modèle chargé en {round(time.time()-t0,2)}s. Prêt."

@mcp.tool()
def generate_image(prompt: str, width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT, steps: int = DEFAULT_STEPS, guidance_scale: float = DEFAULT_GUIDANCE, seed: int = -1, negative_prompt: str = "", aspect_ratio: str = "") -> str:
    """Generate an image from a text prompt using Z-Image-Turbo.
    Default 512x512 (~30s). For HD use hd_ prefix: hd_1:1, hd_16:9, hd_9:16, hd_4:3, hd_3:4.
    Standard presets: 1:1, 16:9, 9:16, 4:3, 3:4.
    Tips: add 'volumetric lighting', 'cinematic', '4k' for quality."""
    import torch
    if not prompt.strip(): return "ERREUR: Prompt vide."
    if aspect_ratio and aspect_ratio in ASPECT_PRESETS: width, height = ASPECT_PRESETS[aspect_ratio]
    width = (width//16)*16; height = (height//16)*16
    if seed < 0: seed = int(torch.randint(0, 2**32-1, (1,)).item())
    pipe = _get_pipeline()
    gen_device = "cpu" if _device == "mps" else _device
    generator = torch.Generator(gen_device).manual_seed(seed)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    fp = OUTPUT_DIR / f"zimage_{ts}_{seed}.png"
    log.info(f"Génération {width}x{height}, {steps} steps, seed={seed}")
    t0 = time.time()
    kwargs = dict(prompt=prompt, height=height, width=width, num_inference_steps=steps, guidance_scale=guidance_scale, generator=generator)
    if negative_prompt.strip(): kwargs["negative_prompt"] = negative_prompt
    with torch.inference_mode(): result = pipe(**kwargs)
    result.images[0].save(str(fp))
    elapsed = round(time.time()-t0, 2)
    log.info(f"Image → {fp} ({elapsed}s)")
    return f"Image générée !\nFichier : {fp}\nRésolution : {width}x{height}\nSeed : {seed}\nSteps : {steps}\nTemps : {elapsed}s"

@mcp.tool()
def unload_model() -> str:
    """Unload model to free RAM. Auto-reloads on next generate_image call."""
    return "Modèle déchargé." if _unload_pipeline() else "Modèle non chargé."

@mcp.tool()
def get_status() -> str:
    """Get server status: model loaded, device, output dir, presets."""
    import torch
    return json.dumps({"model_loaded": _pipe is not None, "model_id": MODEL_ID, "device": _device or "non chargé", "output_directory": str(OUTPUT_DIR), "mps_available": torch.backends.mps.is_available(), "default_resolution": f"{DEFAULT_WIDTH}x{DEFAULT_HEIGHT}", "aspect_presets": list(ASPECT_PRESETS.keys())}, indent=2, ensure_ascii=False)

@mcp.tool()
def list_generated_images(last_n: int = 10) -> str:
    """List recent generated images."""
    if not OUTPUT_DIR.exists(): return "Aucune image."
    pngs = sorted(OUTPUT_DIR.glob("zimage_*.png"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not pngs: return "Aucune image."
    lines = [f"  {p.name}  ({p.stat().st_size/1048576:.1f} MB, {datetime.fromtimestamp(p.stat().st_mtime).strftime('%Y-%m-%d %H:%M')})" for p in pngs[:last_n]]
    return f"Images ({len(lines)}/{len(pngs)}) :\n" + "\n".join(lines)

if __name__ == "__main__":
    log.info(f"z-image-mcp démarré (sortie: {OUTPUT_DIR}, défaut: {DEFAULT_WIDTH}x{DEFAULT_HEIGHT})")
    mcp.run(transport="stdio")
SERVERPY

# Appliquer la résolution choisie
sed -i '' "s/ZIMAGE_DEFAULT_WIDTH\", \"512\"/ZIMAGE_DEFAULT_WIDTH\", \"${DEF_W}\"/" "$INSTALL_DIR/server.py"
sed -i '' "s/ZIMAGE_DEFAULT_HEIGHT\", \"512\"/ZIMAGE_DEFAULT_HEIGHT\", \"${DEF_H}\"/" "$INSTALL_DIR/server.py"

chmod +x "$INSTALL_DIR/server.py"
ok "server.py installé (résolution ${DEF_W}×${DEF_H})"

# ── test_generate.py ─────────────────────────────────────────────────────

cat > "$INSTALL_DIR/test_generate.py" << 'TESTPY'
#!/usr/bin/env python3
"""Test rapide de Z-Image-Turbo sans MCP."""
import time, os
from pathlib import Path

print("Chargement de PyTorch…")
import torch
from diffusers import ZImagePipeline

device = "mps" if torch.backends.mps.is_available() else "cuda" if torch.cuda.is_available() else "cpu"
dtype = torch.bfloat16 if device != "cpu" else torch.float32
print(f"Device: {device}")

print("Chargement du pipeline (premier lancement: téléchargement ~12 GB)…")
t0 = time.time()
pipe = ZImagePipeline.from_pretrained("Tongyi-MAI/Z-Image-Turbo", torch_dtype=dtype, low_cpu_mem_usage=True)
pipe.to(device)
try: pipe.enable_attention_slicing()
except: pass
print(f"Pipeline chargé en {time.time()-t0:.0f}s")

print("Génération…")
gen_dev = "cpu" if device == "mps" else device
t1 = time.time()
with torch.inference_mode():
    img = pipe(prompt="a cosmic cat in deep space, nebulae, photorealistic, 4k", height=512, width=512, num_inference_steps=9, guidance_scale=0.0, generator=torch.Generator(gen_dev).manual_seed(42)).images[0]
out = Path(os.path.expanduser("~/Pictures/z-image-mcp/test.png"))
out.parent.mkdir(parents=True, exist_ok=True)
img.save(str(out))
print(f"\n✓ Image générée en {time.time()-t1:.0f}s → {out}")
print(f"  Ouvrir : open \"{out}\"")
TESTPY

chmod +x "$INSTALL_DIR/test_generate.py"
ok "test_generate.py installé"

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 4 : Environnement Python
# ══════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}[4/6] Installation des dépendances Python${NC}"
echo ""
info "Cela peut prendre 5-15 minutes selon votre connexion."
echo ""

if [[ ! -d "$VENV_DIR" ]]; then
    "$PYTHON" -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"

pip install --upgrade pip -q 2>/dev/null
ok "pip mis à jour"

info "Installation de PyTorch (MPS)…"
pip install torch torchvision -q 2>/dev/null
ok "PyTorch installé"

info "Installation de diffusers (source, pour ZImagePipeline)…"
pip install git+https://github.com/huggingface/diffusers -q 2>/dev/null
ok "diffusers installé"

info "Installation des dépendances…"
pip install transformers accelerate safetensors sentencepiece huggingface-hub Pillow protobuf -q 2>/dev/null
ok "Dépendances installées"

info "Installation du SDK MCP…"
pip install "mcp[cli]" -q 2>/dev/null
ok "MCP SDK installé"

# Vérification
echo ""
"$VENV_DIR/bin/python" -c "
import torch, mcp
from diffusers import ZImagePipeline
print('  ✓ PyTorch', torch.__version__, '— MPS:', torch.backends.mps.is_available())
print('  ✓ ZImagePipeline OK')
print('  ✓ MCP SDK OK')
" || { fail "Vérification échouée."; exit 1; }

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 5 : Configuration de LM Studio
# ══════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}[5/6] Configuration de LM Studio${NC}"
echo ""

PYTHON_ABS="$VENV_DIR/bin/python"
SERVER_ABS="$INSTALL_DIR/server.py"

MCP_ENTRY=$(cat << MCPJSON
{
  "mcpServers": {
    "z-image": {
      "command": "$PYTHON_ABS",
      "args": ["$SERVER_ABS"],
      "timeout": 300000
    }
  }
}
MCPJSON
)

# Tenter de créer/mettre à jour mcp.json automatiquement
if [[ -d "$HOME/.lmstudio" ]]; then
    if [[ -f "$MCP_JSON" ]]; then
        # Vérifier si z-image est déjà configuré
        if grep -q '"z-image"' "$MCP_JSON" 2>/dev/null; then
            warn "z-image déjà présent dans mcp.json"
            ask "Mettre à jour la configuration ? [O/n]"
            read -r REPLY
            if [[ -z "$REPLY" || "$REPLY" =~ ^[OoYy]$ ]]; then
                # Sauvegarder puis réécrire
                cp "$MCP_JSON" "$MCP_JSON.bak"
                echo "$MCP_ENTRY" > "$MCP_JSON"
                ok "mcp.json mis à jour (backup: mcp.json.bak)"
            fi
        else
            # mcp.json existe mais sans z-image — on le remplace
            # (simplifié, ne gère pas le merge avec d'autres MCP servers)
            warn "mcp.json existant détecté avec d'autres serveurs MCP."
            echo "     Vous devrez ajouter z-image manuellement."
            echo ""
            echo "     Ouvrez LM Studio → Program → Edit mcp.json"
            echo "     Ajoutez ceci dans le bloc \"mcpServers\" :"
            echo ""
            echo "       \"z-image\": {"
            echo "         \"command\": \"$PYTHON_ABS\","
            echo "         \"args\": [\"$SERVER_ABS\"],"
            echo "         \"timeout\": 300000"
            echo "       }"
        fi
    else
        # Pas de mcp.json, on le crée
        mkdir -p "$HOME/.lmstudio"
        echo "$MCP_ENTRY" > "$MCP_JSON"
        ok "mcp.json créé automatiquement"
    fi
else
    warn "Dossier ~/.lmstudio non trouvé."
    warn "Installez et lancez LM Studio au moins une fois, puis :"
    echo ""
    echo "     Ouvrez LM Studio → Program → Edit mcp.json"
    echo "     Collez :"
    echo ""
    echo "$MCP_ENTRY"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 6 : Test optionnel
# ══════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}[6/6] Test${NC}"
echo ""
echo "  Le premier test télécharge le modèle Z-Image-Turbo (~12 GB)."
echo "  Cela peut prendre 5-15 minutes la première fois."
echo ""
ask "Lancer le test maintenant ? [O/n]"
read -r REPLY

if [[ -z "$REPLY" || "$REPLY" =~ ^[OoYy]$ ]]; then
    echo ""
    info "Lancement du test…"
    echo ""
    "$VENV_DIR/bin/python" "$INSTALL_DIR/test_generate.py"
    echo ""
    ok "Test terminé !"
else
    echo ""
    info "Test ignoré. Vous pouvez le lancer plus tard avec :"
    echo "     source $VENV_DIR/bin/activate"
    echo "     python $INSTALL_DIR/test_generate.py"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  RÉSUMÉ FINAL
# ══════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                                                       ║${NC}"
echo -e "${BOLD}║   ${GREEN}✓ Installation terminée !${NC}${BOLD}                          ║${NC}"
echo -e "${BOLD}║                                                       ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}  Comment utiliser :${NC}"
echo ""
echo "  1. Ouvrez (ou relancez) LM Studio"
echo "  2. Chargez un modèle avec tool-calling :"
echo "     • Qwen 3.5 4B Q4  (16 GB de RAM)"
echo "     • Qwen 3.5 9B Q4  (32+ GB de RAM)"
echo "  3. Premier message : « Précharge le modèle d'image »"
echo "  4. Puis : « Génère un paysage martien en 16:9 »"
echo ""
echo -e "${BOLD}  Presets de résolution :${NC}"
echo ""
echo "    Standard (rapide) : 1:1, 16:9, 9:16, 4:3, 3:4"
echo "    HD (lent, 2-3 min): hd_1:1, hd_16:9, hd_9:16, hd_4:3, hd_3:4"
echo ""
echo -e "${BOLD}  Images sauvées dans :${NC} ~/Pictures/z-image-mcp/"
echo ""
echo -e "${BOLD}  Commandes utiles dans le chat LM Studio :${NC}"
echo ""
echo "    « Précharge le modèle d'image »    (charger le pipeline)"
echo "    « Décharge le modèle d'image »     (libérer la mémoire)"
echo "    « Liste les images générées »      (voir l'historique)"
echo "    « Montre le statut du serveur »    (diagnostic)"
echo ""
echo -e "${BOLD}  Désinstallation :${NC}"
echo ""
echo "    rm -rf ~/z-image-mcp"
echo "    Puis retirez \"z-image\" de ~/.lmstudio/mcp.json"
echo ""
