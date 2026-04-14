#!/bin/bash
# ============================================================================
#  z-image-mcp — Installateur (backend MLX natif Apple Silicon)
#
#  Usage : curl -sSL https://raw.githubusercontent.com/ctheory/z-image-mcp/main/install.sh | bash
#     ou : ./install.sh
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${BLUE}→${NC} $1"; }
ask()  { echo -en "  ${CYAN}?${NC} $1 "; }

INSTALL_DIR="$HOME/z-image-mcp"
MLX_DIR="$HOME/z-image-turbo-mlx"
MCP_VENV="$INSTALL_DIR/.venv"
MCP_JSON="$HOME/.lmstudio/mcp.json"

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   ${CYAN}z-image-mcp${NC}${BOLD} — MLX Backend Installer                  ║${NC}"
echo -e "${BOLD}║   Z-Image-Turbo natif Apple Silicon, 2x plus rapide  ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 1 : Prérequis système
# ══════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[1/7] Vérification du système${NC}"
echo ""

[[ "$(uname)" != "Darwin" ]] && { fail "macOS requis."; exit 1; }
ok "macOS"

[[ "$(uname -m)" != "arm64" ]] && { fail "Apple Silicon requis."; exit 1; }
ok "Apple Silicon (arm64)"

MEM_GB=$(sysctl -n hw.memsize | awk '{printf "%.0f", $1/1073741824}')
ok "Mémoire unifiée : ${MEM_GB} GB"
(( MEM_GB < 36 )) && { fail "36 GB minimum requis (vous avez ${MEM_GB} GB)."; exit 1; }

if ! command -v brew &>/dev/null; then
    warn "Homebrew non détecté."
    ask "Installer Homebrew ? [O/n]"; read -r R
    if [[ -z "$R" || "$R" =~ ^[OoYy]$ ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
        ok "Homebrew installé"
    else
        fail "Homebrew requis."; exit 1
    fi
else
    ok "Homebrew"
fi

if ! command -v git &>/dev/null; then
    info "Installation de git…"; brew install git
fi
ok "git"

# Python — accepte 3.10 à 3.14
PYTHON=""
for cmd in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$cmd" &>/dev/null; then
        ver=$("$cmd" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        major=$(echo "$ver" | cut -d. -f1)
        minor=$(echo "$ver" | cut -d. -f2)
        if [[ "$major" -ge 3 && "$minor" -ge 10 ]]; then
            PYTHON="$cmd"; break
        fi
    fi
done

if [[ -z "$PYTHON" ]]; then
    warn "Python 3.10+ non trouvé."
    ask "Installer Python 3.14 via Homebrew ? [O/n]"; read -r R
    if [[ -z "$R" || "$R" =~ ^[OoYy]$ ]]; then
        brew install python@3.14; PYTHON="python3.14"
        ok "Python 3.14 installé"
    else
        fail "Python 3.10+ requis."; exit 1
    fi
else
    ok "Python : $PYTHON ($("$PYTHON" --version 2>&1))"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 2 : GPU VRAM
# ══════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[2/7] Configuration GPU${NC}"
echo ""

RECOMMENDED_VRAM=$(( (MEM_GB - 4) * 1024 ))
CURRENT_VRAM=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo "0")

if (( CURRENT_VRAM > 0 && CURRENT_VRAM < RECOMMENDED_VRAM )); then
    warn "Limite GPU : $(( CURRENT_VRAM / 1024 )) GB (recommandé : $(( RECOMMENDED_VRAM / 1024 )) GB)"
    ask "Augmenter à $(( RECOMMENDED_VRAM / 1024 )) GB ? [O/n]"; read -r R
    if [[ -z "$R" || "$R" =~ ^[OoYy]$ ]]; then
        sudo sysctl iogpu.wired_limit_mb=$RECOMMENDED_VRAM
        ok "Limite GPU → $(( RECOMMENDED_VRAM / 1024 )) GB"
        warn "Se réinitialise au redémarrage. Voir README pour le rendre permanent."
    fi
else
    ok "Limite GPU OK"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 3 : Cloner z-image-turbo-mlx
# ══════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[3/7] Installation de z-image-turbo-mlx${NC}"
echo ""

if [[ -d "$MLX_DIR" ]]; then
    warn "$MLX_DIR existe déjà."
    ask "Mettre à jour ? [O/n]"; read -r R
    if [[ -z "$R" || "$R" =~ ^[OoYy]$ ]]; then
        cd "$MLX_DIR" && git pull origin main
        ok "Mis à jour"
    fi
else
    info "Clonage du projet MLX…"
    git clone https://github.com/FiditeNemini/z-image-turbo-mlx.git "$MLX_DIR"
    ok "Cloné dans $MLX_DIR"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 4 : Environnement Python pour z-image-turbo-mlx
# ══════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[4/7] Environnement Python (MLX)${NC}"
echo ""

MLX_VENV="$MLX_DIR/.venv"
if [[ ! -d "$MLX_VENV" ]]; then
    "$PYTHON" -m venv "$MLX_VENV"
fi
source "$MLX_VENV/bin/activate"
pip install --upgrade pip -q 2>/dev/null

info "Installation des dépendances MLX (peut prendre 5-10 min)…"
pip install -r "$MLX_DIR/requirements.txt" -q 2>/dev/null
ok "Dépendances MLX installées"

# Vérification MLX
"$MLX_VENV/bin/python" -c "
import mlx.core as mx
print(f'  ✓ MLX {mx.__version__}')
" || { fail "MLX ne fonctionne pas."; exit 1; }

deactivate
echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 5 : Conversion des poids en MLX
# ══════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[5/7] Conversion du modèle Z-Image-Turbo en MLX${NC}"
echo ""

MLX_MODEL="$HOME/models/mlx/Z-Image-Turbo-MLX"
if [[ -f "$MLX_MODEL/weights.safetensors" ]]; then
    ok "Poids MLX déjà présents"
else
    info "Téléchargement et conversion (~12 GB, peut prendre 10-15 min)…"
    source "$MLX_VENV/bin/activate"
    cd "$MLX_DIR"
    "$MLX_VENV/bin/python" src/convert_to_mlx.py
    deactivate

    if [[ -f "$MLX_MODEL/weights.safetensors" ]]; then
        ok "Conversion réussie"
    else
        # Le script utilise des chemins relatifs — vérifier ../models/
        ALT_MODEL="$(dirname "$MLX_DIR")/models/mlx/Z-Image-Turbo-MLX"
        if [[ -f "$ALT_MODEL/weights.safetensors" ]]; then
            ok "Conversion réussie (chemin alternatif)"
            MLX_MODEL="$ALT_MODEL"
        else
            fail "Conversion échouée. Vérifiez manuellement."
            exit 1
        fi
    fi
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 6 : Serveur MCP
# ══════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[6/7] Configuration du serveur MCP${NC}"
echo ""

# Venv léger pour le serveur MCP (juste mcp[cli], pas de PyTorch)
if [[ ! -d "$MCP_VENV" ]]; then
    mkdir -p "$INSTALL_DIR"
    "$PYTHON" -m venv "$MCP_VENV"
fi
source "$MCP_VENV/bin/activate"
pip install --upgrade pip -q 2>/dev/null
pip install "mcp[cli]" -q 2>/dev/null
ok "MCP SDK installé (venv léger, sans PyTorch)"
deactivate

# Vérifier que server.py est présent
if [[ ! -f "$INSTALL_DIR/server.py" ]]; then
    # Télécharger depuis le repo
    curl -sSL "https://raw.githubusercontent.com/ctheory/z-image-mcp/main/server.py" \
        -o "$INSTALL_DIR/server.py"
fi
chmod +x "$INSTALL_DIR/server.py"
ok "server.py présent"

# Configurer mcp.json pour LM Studio
PYTHON_ABS="$MCP_VENV/bin/python"
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

if [[ -d "$HOME/.lmstudio" ]]; then
    if [[ -f "$MCP_JSON" ]] && grep -q '"z-image"' "$MCP_JSON" 2>/dev/null; then
        warn "z-image déjà dans mcp.json"
        ask "Mettre à jour ? [O/n]"; read -r R
        if [[ -z "$R" || "$R" =~ ^[OoYy]$ ]]; then
            cp "$MCP_JSON" "$MCP_JSON.bak"
            echo "$MCP_ENTRY" > "$MCP_JSON"
            ok "mcp.json mis à jour"
        fi
    elif [[ -f "$MCP_JSON" ]]; then
        warn "mcp.json existant avec d'autres serveurs MCP."
        echo "     Ajoutez manuellement dans Program → Edit mcp.json :"
        echo ""
        echo "       \"z-image\": {"
        echo "         \"command\": \"$PYTHON_ABS\","
        echo "         \"args\": [\"$SERVER_ABS\"],"
        echo "         \"timeout\": 300000"
        echo "       }"
    else
        echo "$MCP_ENTRY" > "$MCP_JSON"
        ok "mcp.json créé"
    fi
else
    warn "LM Studio non détecté. Après installation, ajoutez dans mcp.json :"
    echo ""
    echo "$MCP_ENTRY"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  ÉTAPE 7 : Raccourci bureau + test
# ══════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}[7/7] Raccourci bureau et test${NC}"
echo ""

# Raccourci Gradio
cat > "$HOME/Desktop/Z-Image.command" << SHORTCUT
#!/bin/bash
cd "$MLX_DIR"
source .venv/bin/activate
echo ""
echo "  Z-Image-Turbo MLX — démarrage…"
echo "  Pour arrêter : Ctrl+C ou fermez cette fenêtre."
echo ""
(sleep 5 && open http://127.0.0.1:7860) &
python app.py
SHORTCUT
chmod +x "$HOME/Desktop/Z-Image.command"
ok "Raccourci Z-Image créé sur le bureau"

# Test optionnel
echo ""
echo "  Le premier test télécharge le modèle si nécessaire."
ask "Lancer un test de génération ? [O/n]"; read -r R

if [[ -z "$R" || "$R" =~ ^[OoYy]$ ]]; then
    echo ""
    info "Génération de test (512×512)…"
    mkdir -p "$HOME/Pictures/z-image-mcp"
    source "$MLX_VENV/bin/activate"
    "$MLX_VENV/bin/python" "$MLX_DIR/src/generate_mlx.py" \
        --prompt "a cosmic cat floating in deep space, nebulae, photorealistic, 4k" \
        --output "$HOME/Pictures/z-image-mcp/test_mlx.png" \
        --seed 42 --steps 9 --height 512 --width 512 \
        --model_path "$MLX_MODEL"
    deactivate

    if [[ -f "$HOME/Pictures/z-image-mcp/test_mlx.png" ]]; then
        ok "Image générée → ~/Pictures/z-image-mcp/test_mlx.png"
        open "$HOME/Pictures/z-image-mcp/test_mlx.png"
    else
        warn "Test échoué — vérifiez les logs ci-dessus."
    fi
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════
#  RÉSUMÉ
# ══════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   ${GREEN}✓ Installation terminée !${NC}${BOLD}                          ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}  Deux façons de générer des images :${NC}"
echo ""
echo -e "  ${CYAN}1. Via LM Studio (MCP)${NC}"
echo "     → Relancez LM Studio"
echo "     → Chargez Qwen 3.5 4B ou 9B"
echo "     → « Génère un paysage martien en 16:9 »"
echo ""
echo -e "  ${CYAN}2. Interface Gradio (sans LM Studio, pas de swap)${NC}"
echo "     → Double-cliquez Z-Image sur le bureau"
echo "     → Ou : cd ~/z-image-turbo-mlx && source .venv/bin/activate && python app.py"
echo ""
echo -e "${BOLD}  Presets :${NC} 1:1, 16:9, 9:16, 4:3, 3:4, 3:2, 2:3"
echo -e "${BOLD}  Images :${NC} ~/Pictures/z-image-mcp/"
echo ""
echo -e "${BOLD}  Désinstallation :${NC}"
echo "     rm -rf ~/z-image-mcp ~/z-image-turbo-mlx ~/models"
echo "     rm -f ~/Desktop/Z-Image.command"
echo "     rm -rf ~/.cache/huggingface"
echo "     Retirez \"z-image\" de ~/.lmstudio/mcp.json"
echo ""
