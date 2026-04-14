# z-image-mcp

**Génération d'images locale** avec [Z-Image-Turbo](https://github.com/Tongyi-MAI/Z-Image) (6B)
sur **macOS Apple Silicon** via [MLX](https://github.com/ml-explore/mlx) natif.

Deux modes d'utilisation :
- **LM Studio + MCP** — demandez à votre LLM local de générer des images
- **Interface Gradio** — génération directe sans LLM, sans swap mémoire

> Sans ComfyUI, sans cloud, sans API payante. 2x plus rapide que diffusers/PyTorch.

## Prérequis

|  | Minimum | Recommandé |
|---|---|---|
| **Mac** | Apple Silicon (M1+) | M3/M4 Pro/Max |
| **Mémoire** | 36 GB | 48+ GB |
| **Disque** | 20 GB libres | 30+ GB |
| **macOS** | 14+ | 15+ |
| **LM Studio** | 0.3.18+ | dernière version |

## Installation

### Méthode rapide

```bash
curl -sSL https://raw.githubusercontent.com/ctheory/z-image-mcp/main/install.sh | bash
```

### Méthode manuelle

```bash
git clone https://github.com/ctheory/z-image-mcp.git
cd z-image-mcp
chmod +x install.sh
./install.sh
```

L'installateur :
1. Vérifie votre système (macOS, Apple Silicon, 36 GB+ RAM)
2. Clone [z-image-turbo-mlx](https://github.com/FiditeNemini/z-image-turbo-mlx)
3. Installe MLX et les dépendances
4. Convertit le modèle en format MLX quantifié
5. Configure `mcp.json` pour LM Studio
6. Crée un raccourci Gradio sur le bureau
7. Lance un test de génération

## Utilisation

### Mode 1 : LM Studio + MCP

1. Ouvrez **LM Studio** (ou relancez-le après installation)
2. Vérifiez dans **Program** que **z-image** apparaît avec un point vert
3. Chargez un modèle avec tool-calling (**Qwen 3.5 4B** ou **9B**)
4. Demandez : *« Génère un paysage martien en 16:9 »*

LM Studio affichera une confirmation avant l'exécution — cliquez **Allow**.

> **Note :** Avec LM Studio, un léger swap temporaire (~5 GB) est normal
> pendant la génération car le LLM et Z-Image partagent la mémoire.
> Le swap disparaît après la génération.

### Mode 2 : Interface Gradio (pas de swap)

Double-cliquez **Z-Image** sur le bureau. Ou en terminal :

```bash
cd ~/z-image-turbo-mlx
source .venv/bin/activate
python app.py
```

L'interface s'ouvre dans le navigateur sur `http://127.0.0.1:7860`.

### Presets de résolution

| Preset | Résolution | Temps (~M4) |
|---|---|---|
| `1:1` | 1024×1024 | ~60s |
| `16:9` | 1280×720 | ~45s |
| `9:16` | 720×1280 | ~45s |
| `4:3` | 1152×864 | ~50s |
| `3:4` | 864×1152 | ~50s |

### Outils MCP (LM Studio)

| Outil | Description |
|---|---|
| `generate_image` | Génère une image depuis un prompt texte |
| `get_status` | État du serveur |
| `list_generated_images` | Historique des images |

### Conseils de prompting

- **Soyez spécifique** : décrivez sujet, pose, vêtements, fond, éclairage
- **Mots-clés qualité** : `volumetric lighting`, `cinematic`, `4k`, `studio softbox`
- **Photo-réalisme** : `photorealistic`, `DSLR photo`, `35mm film`
- **Styles** : `oil painting`, `watercolor`, `pixel art`, `anime`
- **Accélération** : ajoutez `cache: fast` pour ~30% de speedup (LeMiCa)
- **Bilingue** : anglais et chinois supportés

## Optimisation mémoire

### Augmenter la VRAM GPU

```bash
# Mac 36 GB → 32 GB pour le GPU
sudo sysctl iogpu.wired_limit_mb=32768
```

Se réinitialise au redémarrage. Pour le rendre permanent :

```bash
sudo tee /Library/LaunchDaemons/com.gpu.vram.plist > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.gpu.vram</string>
<key>ProgramArguments</key><array>
<string>/usr/sbin/sysctl</string><string>iogpu.wired_limit_mb=32768</string>
</array><key>RunAtLoad</key><true/>
</dict></plist>
EOF
```

### Réduire le swap avec LM Studio

- Utilisez **Qwen 3.5 4B** au lieu de 9B pendant les générations
- Fermez Chrome et les apps lourdes
- Pour 0 swap : utilisez le mode Gradio (sans LM Studio)

## Architecture

```
┌─ Mode 1 : LM Studio ─────────────────────────────┐
│  LM Studio (Qwen 3.5) ──MCP stdio──▶ server.py   │
│       server.py ──subprocess──▶ generate_mlx.py   │
│           → image PNG sauvée                      │
│           → mémoire MLX libérée                   │
└───────────────────────────────────────────────────┘

┌─ Mode 2 : Gradio ────────────────────────────────┐
│  Navigateur ──▶ app.py (Gradio UI)               │
│       → generate_mlx.py                          │
│       → image PNG sauvée                         │
└───────────────────────────────────────────────────┘
```

## Désinstallation

```bash
rm -rf ~/z-image-mcp ~/z-image-turbo-mlx ~/models
rm -f ~/Desktop/Z-Image.command
rm -rf ~/.cache/huggingface
# Retirez "z-image" de ~/.lmstudio/mcp.json
```

## Crédits

- [Z-Image-Turbo](https://github.com/Tongyi-MAI/Z-Image) par Alibaba Tongyi Lab (Apache 2.0)
- [z-image-turbo-mlx](https://github.com/FiditeNemini/z-image-turbo-mlx) par FiditeNemini
- [MLX](https://github.com/ml-explore/mlx) par Apple
- [LM Studio](https://lmstudio.ai)
- [MCP](https://modelcontextprotocol.io) par Anthropic

## Licence

MIT
