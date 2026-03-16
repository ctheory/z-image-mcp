# z-image-mcp

**Génération d'images locale** avec [Z-Image-Turbo](https://github.com/Tongyi-MAI/Z-Image) (6B) 
pilotée par un LLM local dans [LM Studio](https://lmstudio.ai) via le protocole [MCP](https://modelcontextprotocol.io).

> Demandez à votre LLM local de générer des images — sans ComfyUI, sans cloud, sans API payante.

## Démonstration

Dans le chat LM Studio :

```
Toi : « Génère une image photoréaliste d'un lever de soleil sur Mars,
        avec des rochers rouges au premier plan, volumetric lighting, cinematic, en 16:9 »

LLM → appelle generate_image(prompt="...", aspect_ratio="16:9")
    → Z-Image-Turbo génère l'image en ~30s
    → "Image générée ! Fichier : ~/Pictures/z-image-mcp/zimage_20260315_143022_42.png"
```

## Prérequis

| | Minimum | Recommandé |
|---|---|---|
| **Mac** | Apple Silicon (M1+) | M3/M4 Pro/Max |
| **Mémoire** | 16 GB | 32+ GB |
| **Disque** | 15 GB libres | 20+ GB |
| **macOS** | 13+ | 15+ |
| **LM Studio** | 0.3.18+ | dernière version |

### Budget mémoire indicatif

| Config LM Studio | + Z-Image | Total pic | Résolution max |
|---|---|---|---|
| Qwen 3.5 4B Q4 (~2.5 GB) | ~17 GB | ~20 GB | 1280×720 |
| Qwen 3.5 9B Q4 (~5.5 GB) | ~17 GB | ~23 GB | 1280×720 |
| Qwen 3.5 35B-A3B Q4 (~20 GB) | ~17 GB | ~37 GB | 512×512 |

## Installation

### Méthode rapide (une seule commande)

```bash
curl -sSL https://raw.githubusercontent.com/VOTRE_REPO/z-image-mcp/main/install.sh | bash
```

### Méthode manuelle

```bash
git clone https://github.com/VOTRE_REPO/z-image-mcp.git
cd z-image-mcp
chmod +x install.sh
./install.sh
```

L'installateur :
1. ✅ Vérifie votre système (macOS, Apple Silicon, mémoire)
2. ✅ Installe Python 3.12 si nécessaire (via Homebrew)
3. ✅ Crée un environnement virtuel isolé
4. ✅ Installe PyTorch, diffusers, MCP SDK
5. ✅ Recommande une résolution selon votre mémoire
6. ✅ Configure automatiquement `mcp.json` pour LM Studio
7. ✅ Propose d'ajuster la limite GPU VRAM
8. ✅ Lance un test de génération

## Utilisation

### Premiers pas

1. Ouvrez (ou relancez) **LM Studio**
2. Chargez un modèle avec **tool-calling** :
   - **Qwen 3.5 4B** (16 GB de RAM) — suffisant pour piloter les images
   - **Qwen 3.5 9B** (32+ GB) — meilleure qualité de prompting
3. Premier message : **« Précharge le modèle d'image »**
4. Puis : **« Génère un chat cosmique en 16:9 »**

### Presets de résolution

| Preset | Résolution | Temps (~M4) | Usage |
|---|---|---|---|
| `1:1` | 512×512 | ~30s | Rapide, avatar |
| `16:9` | 640×368 | ~25s | Paysage |
| `9:16` | 368×640 | ~25s | Portrait, mobile |
| `4:3` | 576×432 | ~28s | Photo classique |
| `hd_1:1` | 1024×1024 | ~2-3 min | Haute qualité |
| `hd_16:9` | 1280×720 | ~90s | Cinématique |
| `hd_9:16` | 720×1280 | ~90s | Affiche verticale |

### Outils MCP disponibles

| Outil | Description |
|---|---|
| `preload_model` | Charge le modèle en mémoire (évite le timeout au 1er appel) |
| `generate_image` | Génère une image depuis un prompt texte |
| `unload_model` | Libère la mémoire (modèle rechargé automatiquement ensuite) |
| `get_status` | État du serveur |
| `list_generated_images` | Historique des images générées |

### Conseils de prompting

Z-Image-Turbo est très littéral. Pour de bons résultats :

- **Soyez spécifique** : décrivez le sujet, la pose, les vêtements, le fond, l'éclairage
- **Mots-clés qualité** : `volumetric lighting`, `cinematic`, `4k`, `studio softbox`
- **Photo-réalisme** : ajoutez `photorealistic`, `DSLR photo`, `35mm film`
- **Styles** : `oil painting`, `watercolor`, `pixel art`, `anime`
- **Bilingue** : le modèle comprend l'anglais et le chinois

### Images

Les images sont sauvées dans `~/Pictures/z-image-mcp/` au format PNG.

## Optimisation mémoire

### Augmenter la VRAM GPU (macOS)

Par défaut, macOS ne donne que ~66% de la RAM au GPU. Pour augmenter :

```bash
# Exemple pour un Mac 36 GB → 32 GB pour le GPU
sudo sysctl iogpu.wired_limit_mb=32768
```

Relancez LM Studio après. Ce réglage se réinitialise au redémarrage.

### Réduire la pression mémoire

- Utilisez **Qwen 3.5 4B** au lieu de 9B quand vous générez des images
- Restez en résolution **standard** (pas hd_) sur les Mac ≤ 32 GB
- Fermez les navigateurs et apps lourdes pendant la génération
- Après la génération, demandez : **« Décharge le modèle d'image »**

## Limitations

- **LM Studio n'affiche pas les images dans le chat** — le LLM retourne le chemin du fichier
- Le **text encoder Qwen3-4B est obligatoire** dans le pipeline de diffusion — il ne peut pas être remplacé par le LLM de LM Studio
- `guidance_scale` doit rester à **0.0** pour Z-Image-Turbo (modèle distillé)
- Le premier appel est plus lent (~30s supplémentaires) — utilisez `preload_model`

## Désinstallation

```bash
rm -rf ~/z-image-mcp
```

Puis retirez l'entrée `"z-image"` de `~/.lmstudio/mcp.json`.

## Crédits

- [Z-Image-Turbo](https://github.com/Tongyi-MAI/Z-Image) par Alibaba Tongyi Lab (Apache 2.0)
- [LM Studio](https://lmstudio.ai) par LM Studio, Inc.
- [MCP](https://modelcontextprotocol.io) par Anthropic
- [diffusers](https://github.com/huggingface/diffusers) par Hugging Face

## Licence

MIT
