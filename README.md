<div align="center">

# 🎬 CogVideoX-Mac-Setup

### CogVideoX-5B Video Generation on Apple Silicon M4 Pro

![Made with Mac](https://img.shields.io/badge/Made_with-Apple_Silicon-999999?style=for-the-badge&logo=apple&logoColor=white)
![CogVideoX](https://img.shields.io/badge/CogVideoX-5B-blue?style=for-the-badge)
![Python](https://img.shields.io/badge/Python-3.13-3776AB?style=for-the-badge&logo=python&logoColor=white)
![ComfyUI](https://img.shields.io/badge/ComfyUI-Workflow-00C853?style=for-the-badge)

**Generate stunning AI videos locally without cloud GPUs!**

[📖 Documentation](#documentation) • [🚀 Quick Start](#quick-start) • [🎥 Examples](#examples) • [⚙️ Performance](#performance)

---

</div>

## ✨ What This Does

Successfully runs **CogVideoX-5B** (10GB model) for text-to-video generation on **Mac M4 Pro with 64GB RAM** using Apple's Metal Performance Shaders (MPS).

### 🎯 Key Achievements

- ✅ **Fixed MPS autocast incompatibility** - The main blocker for Mac users
- ✅ **Resolved node registration errors** - Custom patches for ComfyUI
- ✅ **Found optimal memory limits** - 30 frames max for stable generation
- ✅ **4-second videos in ~18 minutes** - No cloud GPUs needed
- ✅ **99% GPU utilization** - Full Apple Silicon power

---

## 🎥 Generated Examples

### Waterfall in Mossy Forest
*Prompt: "A serene waterfall flowing through a mossy ancient forest"*  
*30 frames, 30 steps, 512x384, 18 minutes generation time*

https://github.com/user-attachments/assets/f756588c-2bfa-4a37-af1d-1577b85fd01a

<table>
<tr>
<td width="33%">

**Example 1**

https://github.com/user-attachments/assets/92cbac80-d2ed-4745-a77c-8c1c9c12ff0e

*25 frames, 20 steps, 12 min*

</td>
<td width="33%">

**Example 2**

https://github.com/user-attachments/assets/ee226225-1c2d-4d47-8f4b-f42932e9987f

*25 frames, 20 steps, 12 min*

</td>
<td width="33%">

**Example 3**

https://github.com/user-attachments/assets/a7fc65d9-06bb-46b5-817c-6336ff245527

*25 frames, 20 steps, 12 min*

</td>
</tr>
</table>

---

## 🖥️ Hardware Requirements

### Tested Configuration

| Component | Spec |
|-----------|------|
| **Model** | Mac Mini M4 Pro |
| **CPU** | 14-core (10P + 4E) |
| **GPU** | 20-core |
| **RAM** | 64GB Unified Memory |
| **Storage** | 2TB+ recommended |
| **OS** | macOS 26.1+ |

### Minimum Requirements

- **RAM**: 64GB (critical - 32GB insufficient)
- **Storage**: 50GB free (models + workspace)
- **Chip**: M4 Pro or better

---

## ⚡ Performance

### Generation Times

| Frames | Seconds | Steps | Resolution | Time | Success Rate |
|--------|---------|-------|------------|------|--------------|
| **25** | 3s | 20 | 512x384 | 12 min | ✅ 100% |
| **30** | 4s | 30 | 512x384 | 18 min | ✅ 100% |
| **49** | 6s | 30 | 512x384 | 40 min | ⚠️ 50% |
| **49** | 6s | 50 | 512x384 | 70 min | ❌ Corrupts |
| **>30** | >4s | Any | Any | - | ❌ White screen |

### GPU Utilization
```
During generation: 99% GPU usage
Memory bandwidth: 273 GB/s fully utilized
Power draw: ~50W sustained
Thermals: Cool (< 60°C)
```

---

## 🚀 Quick Start

### 1. Install ComfyUI
```bash
cd ~/Desktop
git clone https://github.com/comfyanonymous/ComfyUI
cd ComfyUI
python -m venv ../venv
source ../venv/bin/activate
pip install torch torchvision torchaudio
pip install -r requirements.txt
```

### 2. Install CogVideoX Wrapper
```bash
cd custom_nodes
git clone https://github.com/kijai/ComfyUI-CogVideoXWrapper
cd ComfyUI-CogVideoXWrapper
pip install -r requirements.txt
```

### 3. Apply Mac Fixes

**Critical**: The default nodes don't work on Mac. Apply our fixes:
```bash
# Backup original
cp nodes.py nodes.py.backup

# Apply fixes (see fixes/nodes_fixed.py in this repo)
# OR manually apply the patches below
```

#### Fix 1: MPS Autocast Compatibility

Find line ~755 in `nodes.py` and replace:
```python
# OLD (breaks on Mac):
autocast_context = torch.autocast(
    mm.get_autocast_device(device), dtype=dtype
) if any(q in model["quantization"] for q in ("e4m3fn", "GGUF")) else nullcontext()

# NEW (Mac compatible):
# MPS-safe autocast with fallback
if str(device.type) == "mps":
    autocast_context = nullcontext()
else:
    autocast_context = torch.autocast(
        mm.get_autocast_device(device), dtype=dtype
    ) if any(q in model["quantization"] for q in ("e4m3fn", "GGUF")) else nullcontext()
```

#### Fix 2: Default H/W Values

Around line ~684, verify these default values exist:
```python
else:
    # Default dimensions for text-to-video
    H = 60  # 480 / 8
    W = 90  # 720 / 8
    B = 1
    T = num_frames
    C = 16
    latents = None
```

### 4. Download Models
```bash
# T5 Text Encoder (9GB)
cd ../../models/clip
wget https://huggingface.co/mcmonkey/google_t5-v1_1-xxl_encoderonly/resolve/main/t5xxl_fp16.safetensors

# CogVideoX-5B will auto-download on first run (10GB)
```

### 5. Start ComfyUI
```bash
cd ~/Desktop/ComfyUI
export PYTORCH_ENABLE_MPS_FALLBACK=1
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
python main.py --force-fp16 --lowvram
```

### 6. Load Workflow

1. Open http://127.0.0.1:8188
2. Drag `workflows/cogvideox_1_0_5b_T2V_02.json` into browser
3. Adjust settings (see Optimal Settings below)
4. Queue Prompt!

---

## ⚙️ Optimal Settings

### Recommended Configuration

**For Maximum Success Rate:**
```yaml
Empty Latent Image:
  width: 512
  height: 384
  batch_size: 1

CogVideo Sampler:
  num_frames: 30      # CRITICAL: Don't exceed!
  steps: 20-30        # Higher = better quality but slower
  cfg: 6.0-6.5
  scheduler: CogVideoXDDIM
  
Load CLIP:
  clip_name: t5xxl_fp16.safetensors
  type: sd3
```

### ⚠️ Critical Limits

- **Max frames: 30** (31+ causes white screen corruption)
- **Max steps: 30** (50+ exhausts memory during VAE decode)
- **Resolution: 512x384** (higher resolutions untested/risky)

---

## 🔧 Troubleshooting

### White Screen Output

**Symptoms**: Generation completes 100% but video is white with artifacts

**Causes**:
- Too many frames (>30)
- Too many steps (>30)
- Memory exhaustion during VAE decode

**Solutions**:
1. Reduce to 25-30 frames
2. Use 20-30 steps maximum
3. Enable VAE tiling in CogVideo Decode node
4. Restart ComfyUI to clear memory

### Out of Memory Crash

**Error**: `Failed to allocate private MTLBuffer for size XXXGB`

**Solutions**:
- Reduce frames to 25
- Reduce steps to 20
- Close all other applications
- Restart Mac to clear unified memory

### Node Registration Failure

**Error**: `Cannot import CogVideoXWrapper module`

**Solutions**:
- Check indentation in nodes.py (line 674 must have 8 spaces)
- Verify fixes were applied correctly
- Restore from `nodes.py.backup` and reapply fixes

---

## 📚 Documentation

### File Structure
```
CogVideoX-Mac-Setup/
├── README.md
├── fixes/
│   ├── nodes_original.py      # Backup of original
│   └── nodes_fixed.py          # Mac-compatible version
├── workflows/
│   └── cogvideox_1_0_5b_T2V_02.json
└── examples/
    ├── videos/          # (hosted on GitHub)
    └── screenshots/
```

### Technical Details

**What We Fixed:**

1. **MPS Autocast Bug**: PyTorch's `torch.autocast()` doesn't support MPS device type, causing `RuntimeError`. Wrapped in device check with `nullcontext()` fallback.

2. **H/W Variable Bug**: Text-to-video mode didn't initialize height/width when no input image present, causing `UnboundLocalError`. Added default values based on model expectations.

3. **Memory Limits**: Through testing, discovered 30-frame hard limit on M4 Pro 64GB due to VAE decode memory requirements (~46GB buffer allocation at 49 frames).

---

## 🤝 Contributing

Found this helpful? Consider:

- ⭐ Star this repo
- 🐛 Report issues you encounter
- 💡 Share your successful configurations
- 🎥 Submit example videos

### Related Projects

- [ComfyUI](https://github.com/comfyanonymous/ComfyUI) - The UI framework
- [CogVideoX](https://github.com/THUDM/CogVideo) - Original model
- [ComfyUI-CogVideoXWrapper](https://github.com/kijai/ComfyUI-CogVideoXWrapper) - The wrapper we fixed

---

## 📊 Comparisons

### vs NVIDIA RTX 4090

| Metric | Mac M4 Pro 64GB | RTX 4090 + 128GB |
|--------|----------------|------------------|
| **30 frames, 30 steps** | 18 minutes | ~5 minutes |
| **Max video length** | 4 seconds | 40+ seconds |
| **Resolution** | 512x384 | 1024x768+ |
| **Power draw** | 50W | 450W |
| **Noise** | Silent | Jet engine |
| **Cost** | $2,200 | $4,500+ |

**Verdict**: Mac is perfect for learning/experimenting. RTX for production.

---

## 📝 License

This guide and fixes are MIT licensed. Original CogVideoX and ComfyUI have their own licenses.

---

## 🙏 Acknowledgments

- **kijai** for the ComfyUI-CogVideoXWrapper
- **THUDM** for CogVideoX model
- **comfyanonymous** for ComfyUI
- **Apple** for M4 Pro silicon that makes this possible

---

<div align="center">

**Made with ❤️ on Apple Silicon**

[Report Bug](https://github.com/nicedreamzapp/CogVideoX-Mac-Setup/issues) • [Request Feature](https://github.com/nicedreamzapp/CogVideoX-Mac-Setup/issues)

</div>
