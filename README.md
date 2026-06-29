<div align="center">

# MATT MACOSKO — Nice Dreamz LLC

<pre>
┌──────────────────────────────────────────────────────────────────┐
│  Humboldt County, California  ·  Nice Dreamz LLC                │
│  A three-node ambient-computing mesh, built on Apple Silicon.   │
│  Code, curiosity, and the right tools.                          │
└──────────────────────────────────────────────────────────────────┘
</pre>

[![GitHub followers](https://img.shields.io/github/followers/nicedreamzapp?style=for-the-badge&color=236ad3&labelColor=1155ba)](https://github.com/nicedreamzapp)
[![Repos](https://img.shields.io/badge/dynamic/json?label=Public%20Repos&query=%24.public_repos&url=https%3A%2F%2Fapi.github.com%2Fusers%2Fnicedreamzapp&style=for-the-badge&color=58a6ff&labelColor=388bfd)](https://github.com/nicedreamzapp?tab=repositories)

---

### *"If it takes more than 10 minutes, I automate it. If it needs AI, I build it from scratch."*

---

</div>

## WHAT I'M ACTUALLY BUILDING

Most of these repos look standalone. They're not. They're parts of one system spread across three machines that talk to each other 24/7:

- **M5 Max MacBook Pro · 128 GB** — heavy compute on demand: model inference, video generation, image generation, training.
- **M4 Mac mini · 64 GB** — the always-on workhorse. Sits in the closet, runs autonomous agents, hosts the FiaOS web shell, answers Claude prompts on the Max plan for the rest of the mesh to use for free.
- **Hostinger VPS** — public gateway. Hosts the HQ Dashboard, the Ohm chat agent, marketing sites, MediaMTX streaming, and the cron jobs that pull everything together.

The idea: Apple Silicon is finally fast enough that I don't need a cloud subscription for the things I want to do every day. Build a local-first AI stack — code by voice, drive by text, see through my phone camera, ship orders through a dashboard, run autonomous agents in the closet — and stay useful when the internet goes down. The same stack is airgap-ready, which matters to the law / medical / compliance-sensitive firms I work with through Nice Dreamz LLC.

---

## NOW SHIPPING — AIRGAP

The commercial side of the local-first stack. Three rungs for three buyers, all running the same open-source `claude-code-local` engine underneath.

| | What it is | Price |
|---|---|---|
| 🖥️ **[AirGap Box](https://nicedreamzwholesale.com/airgap-box/)** | Pre-configured Mac mini delivered to your office with the stack + 3 agents installed. 90-min Zoom setup. 30 days support. | **$2,995-$3,995** one-time · waitlist open |
| 🔒 **[AirGap Foundation](https://nicedreamzwholesale.com/airgap/)** | 14-day fixed-scope deployment for law / medical / compliance-sensitive firms. Custom workflows + written compliance memo. | scoped per firm |

Reading material on why this exists now: ["The Heppner Ruling, Warner v. Gilbarco, and What Confidential AI Actually Has to Mean"](https://nicedreamzwholesale.com/2026/05/22/the-heppner-ruling-warner-v-gilbarco-and-what-confidential-ai-actually-has-to-mean/) — a federal court just ruled that public-AI work is not privileged. On-device just stopped being optional for privileged work.

---

## THE MESH

### 📡 Always-on agents running across all three nodes

```
                          ┌─────────────────────────────┐
                          │   iPhone (iMessage bridge)  │
                          │   ask · send · image · vid  │
                          └────────────┬────────────────┘
                                       │
       ┌───────────────────────────────┼───────────────────────────────┐
       │                               │                               │
┌──────▼──────────┐         ┌──────────▼──────────────┐     ┌──────────▼────────┐
│  M5 Max         │         │   Mac mini (always-on)  │     │  VPS (Hostinger)  │
│  workstation    │◀──SSH──▶│   the workhorse         │◀───▶│   gateway         │
├─────────────────┤         ├─────────────────────────┤     ├───────────────────┤
│ • ComfyUI       │         │ • FiaOS web shell       │     │ • HQ Dashboard    │
│ • MLX server    │         │ • gh-watcher (5m)       │     │ • Ohm chat agent  │
│ • MakeVideo     │         │ • gh-mail-watcher (10m) │     │ • Marketing Hub   │
│ • Browser Agent │         │ • lead-watcher (5m)     │     │ • Family Planner  │
│ • NarrateClaude │         │ • Morning briefing (9a) │     │ • MediaMTX        │
│ • on-demand     │         │ • mini_claude bridge    │     │ • reddit-agent    │
│   workloads     │         │   (free Opus for VPS)   │     │ • daily-brain     │
└─────────────────┘         └─────────────────────────┘     │ • email-triage    │
                                                            │ • vps-selfreport  │
                                                            └───────────────────┘
```

### What each agent actually does

| Where | Agent | Job |
|-------|-------|-----|
| mini | **FiaOS** | Public web shell at [fia.nicedreamzwholesale.com](https://fia.nicedreamzwholesale.com) — PTY terminal + screen + voice through a Cloudflare tunnel. |
| mini | **gh-watcher** | Auto-discovers all my repos every 5 min. Watches issues, PRs, star milestones, HN mentions. Drafts replies to new issues with local `claude -p` and iMessages me the draft. |
| mini | **gh-mail-watcher** | Reads GitHub-sender emails, classifies (PAT expiry / security / vuln / repo comment / CI fail / noise), handles autonomously, only pings me when a human is required. |
| mini | **lead-watcher** | Watches claude-code-local Discussions/Issues for AirGap consulting leads. |
| mini | **Morning briefing** | 9am daily — pulls HQ state, posts an iMessage business briefing. |
| mini | **mini_claude bridge** | Lets the VPS call Claude on my Max plan (Opus) for $0 by routing through FiaOS. This is the trick. |
| VPS | **Ohm** | The only fully LLM-driven agent. Sonnet 4.6 chat at [hq.nicedreamzwholesale.com/ohm](https://hq.nicedreamzwholesale.com/ohm); offloads heavy work to mini via `mini_claude`. |
| VPS | **HQ Dashboard** | Gunicorn at `:9001` — central command for orders, email, shipping, agents, and Ohm. |
| VPS | **reddit-agent** | Watches Reddit for brand mentions every 15 min. |
| VPS | **daily-brain** | 3:30am — reviews all trading systems, generates a 10-question report via mini_claude (free Opus). |
| VPS | **email-triage** | 6× daily — auto-marks system emails as read, leaves humans for me. |
| M5 | **agent-rollcall** | Monday 9am — audits all three machines, iMessages me the health summary. |
| M5/mini | **hq-state pusher** | Every 30s — pushes node state to the VPS dashboard. |

Cost discipline rule across the mesh: if an agent uses paid API, swap it to `mini_claude` (Max plan, $0/call) unless it explicitly needs a non-Claude model.

---

## THE TOOLBELT — repos by role in the stack

| Role | Repo | What it does |
|------|------|--------------|
| 🧠 Brain | [claude-code-local](https://github.com/nicedreamzapp/claude-code-local) | Claude Code, 100% on-device. The center of everything. |
| 🎙️ Voice | [NarrateClaude](https://github.com/nicedreamzapp/NarrateClaude) + Ohm | I talk to it; it answers in my own cloned voice. |
| 👁️ Eyes | [RealTimeAICam](https://github.com/nicedreamzapp/RealTimeAICam) + [VisionBuilder](https://github.com/nicedreamzapp/VisionBuilder) | iPhone camera that sees 601 objects offline; train new ones from photos I already took. |
| ✋ Hands | [cinch](https://github.com/nicedreamzapp/cinch) + [studio-record](https://github.com/nicedreamzapp/studio-record) | Real work — shipping orders, recording the screen. |
| 📱 Remote | [claude-screen-to-phone](https://github.com/nicedreamzapp/claude-screen-to-phone) + [FiaOS](https://github.com/nicedreamzapp/FiaOS) | Drive the Mac from my iPhone via iMessage; or open any browser and remote into the mini at home. |
| 🌐 Browser | [browser-agent](https://github.com/nicedreamzapp/browser-agent) | Local AI driving Chrome — Shadow DOM, ProseMirror, the whole stack. |
| 🤖 Body | [CemaniHomesteadRobot](https://github.com/nicedreamzapp/CemaniHomesteadRobot) | The long-arc bet: a Lego-clip-in robot platform that uses the same vision pipeline. |
| 👨‍👧 Family | [JaneOS / Bloom](https://github.com/nicedreamzapp/JaneOS) | An adaptive 1st-grade tutor I built for my daughter. **Live at [jane.nicedreamzwholesale.com](https://jane.nicedreamzwholesale.com)**. |

This isn't a portfolio. It's the toolkit the mesh actually uses every day to run Divine Tribe (since 2013), serve Nice Dreamz consulting clients, and chip away at the robotics work that's the actual point.

---

## LIVE ON THE INTERNET RIGHT NOW

Public surfaces of the mesh you can hit from any browser:

| URL | What |
|-----|------|
| [hq.nicedreamzwholesale.com](https://hq.nicedreamzwholesale.com) | HQ Dashboard — orders, email, shipping, Ohm chat |
| [fia.nicedreamzwholesale.com](https://fia.nicedreamzwholesale.com) | FiaOS — full Mac mini in a browser tab |
| [nicedreamzwholesale.com/airgap](https://nicedreamzwholesale.com/airgap) | AirGap AI — private-AI consulting pilot offer |
| [cdsi.click](https://cdsi.click) | Cannabis Device Safety Institute — standards body site (launch video embedded) |
| [marijuanaunion.com/marketplace](https://marijuanaunion.com/marketplace) | The Farmstand 3D — WebXR cannabis marketplace |
| [disclosureday.nicedreamzwholesale.com](https://disclosureday.nicedreamzwholesale.com) | Disclosure Day — SEO + AI chatbot ("D.I.S.C.O.") site |

---

## THE FRONT FIVE

> _Sorted by GitHub stars — the most-loved at the top._

### [Claude Code Local](https://github.com/nicedreamzapp/claude-code-local) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/claude-code-local?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/claude-code-local/stargazers) [![Forks](https://img.shields.io/github/forks/nicedreamzapp/claude-code-local?style=flat-square&color=58a6ff)](https://github.com/nicedreamzapp/claude-code-local/network/members)
Run Claude Code 100% on-device with local AI on Apple Silicon. No cloud, no API fees.
- 3 models to choose from: Gemma 4 31B (fast), Llama 3.3 70B (smartest), Qwen 3.5 122B (biggest)
- 4 modes: Code, Browser Agent, Narrative (voice), and Phone (iMessage remote control)
- Custom MLX server with Anthropic-compatible API — swap models with one env var
- `setup.sh` auto-detects your RAM, picks the right model, and creates a desktop launcher
- Your code never leaves your Mac — not for inference, not for telemetry, not for anything

`MLX` `Apple Silicon` `Claude Code` `Gemma` `Llama` `Qwen` `Python`

---

### [NarrateClaude + Ohm — voice-first AI](https://github.com/nicedreamzapp/NarrateClaude) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/NarrateClaude?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/NarrateClaude/stargazers)
Talk to your Mac, hear it reply in your own cloned voice. Now also accessible from any browser, anywhere.
- NarrateClaude — on-device wake-word + cloned voice + local LLM, 100% private, works on a plane
- Ohm — the same voice loop wrapped in a private web chat I host on my own infrastructure — type from any browser, hear the reply in my own voice
- VPS proxies the chat to a self-hosted bridge on a Mac mini at home; Claude on the Max plan answers, audio pipes back to the browser
- Zero cloud-AI cost, zero paid API calls per message

`Pocket TTS` `Apple Silicon` `Claude Code Max plan` `Flask` `nginx` `Python`

---

### [Browser Agent — Apple Silicon browser control with no cloud](https://github.com/nicedreamzapp/browser-agent) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/browser-agent?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/browser-agent/stargazers)
A local browser-control agent powered by MLX + Chrome DevTools Protocol.
- Handles the cases other agents can't: cross-origin iframes, Shadow DOM, ProseMirror editors
- Inference via local MLX models — zero cloud calls, no rate limits, no API keys
- Pairs with Claude Code Local for fully on-device automation pipelines

`MLX` `Apple Silicon` `Chrome DevTools Protocol` `Python` `Local AI`

<a href="https://youtu.be/SIuMNa2k6Wc"><img src="https://img.youtube.com/vi/SIuMNa2k6Wc/maxresdefault.jpg" width="480" alt="▶ Watch the 56-second demo"></a>

---

### [RealTimeAICam — 601 objects on your phone, fully offline](https://github.com/nicedreamzapp/RealTimeAICam) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/RealTimeAICam?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/RealTimeAICam/stargazers)
The biggest free open-vocabulary detector I could fit on an iPhone — 601 classes, OCR, and LiDAR depth, all running on-device.
- Open YOLOv8 weights converted to CoreML, no subscription, no telemetry
- Pairs with the camera and LiDAR sensors directly — depth-aware bounding boxes
- The seed of the vision stack I'm pulling into the CemaniHomesteadRobot project

`YOLOv8` `CoreML` `Swift` `iOS` `LiDAR`

---

### [Claude → Phone (iMessage remote)](https://github.com/nicedreamzapp/claude-screen-to-phone) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/claude-screen-to-phone?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/claude-screen-to-phone/stargazers)
Control Claude Code from your iPhone via iMessage. Driver-friendly. Doctor-friendly. Walking-the-dog-friendly.
- Send commands by text, get back screenshots, screen recordings, and produced videos automatically
- Hooks into Claude Code on the Mac, returns multimodal output to your phone
- Approve/deny prompts arrive as YES / NO / YES_TO_ALL message buttons

`iMessage` `AppleScript` `Claude Code` `macOS Automation` `Python`

---

## THE DAILY DRIVERS

These aren't the top of the star chart, but they're the ones the mesh actually runs every day.

### [Cinch — one-page WooCommerce shipping dashboard](https://github.com/nicedreamzapp/cinch)
The tool that pays for everything else. Built it for myself after ten years of fighting WordPress, and my partner watched me use it and asked "why aren't you selling that?"
- Orders from every WooCommerce store I own, merged into a single feed
- USPS / UPS / FedEx rates pre-loaded on every order; cheapest is highlighted
- Same-customer orders auto-merge into one card; multi-box shipping with one click
- Fraud risk flags with the actual reasons listed inline
- One-tap thermal print — direct from dashboard to label printer, no PDFs
- End-of-day USPS SCAN manifest with one button
- In a good run: four seconds per order. Down from a minute and a half.
- Open-source, self-hosted, your VPS, your WooCommerce keys, your EasyPost account. No SaaS in the middle.

`Flask` `WooCommerce REST` `EasyPost API` `Python` `vanilla JS`

---

### [FiaOS — your Mac mini, in a browser tab](https://github.com/nicedreamzapp/FiaOS) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/FiaOS?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/FiaOS/stargazers)
Open any browser. You're now driving the Mac mini at home — screen, keyboard, mouse, voice.
- Live remote desktop + a real PTY shell (Claude Code, vim, top — anything you'd run in Terminal)
- On-device voice loop with a cloned warm voice for the responses
- Self-hosted via Cloudflare Tunnel — public URL, zero VPS cost, all the compute on Apple Silicon
- Auto-starts on boot, auto-restarts on crash, runs as a permanent service
- It's the bridge the VPS uses to call `mini_claude` — the trick that gives every other agent free Opus access

`Python` `WebSockets` `Cloudflare Tunnel` `PTY` `Apple Silicon`

---

### [studio-record — screen+facecam with a local HTTP API](https://github.com/nicedreamzapp/studio-record) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/studio-record?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/studio-record/stargazers)
macOS screen + facecam recorder with virtual backgrounds and a local HTTP API.
- Pairs with Claude Code via the API on `localhost:17494` — Claude can record itself working
- Virtual backgrounds without OBS or third-party plugins
- Outputs ready-to-edit MP4 / WebM, no transcoding step

`Swift` `AVFoundation` `macOS` `HTTP API` `Claude Code`

---

## THE LONG-ARC BET

### [Cemani Homestead Robot](https://github.com/nicedreamzapp/CemaniHomesteadRobot) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/CemaniHomesteadRobot?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/CemaniHomesteadRobot/stargazers)
Started with a simple problem: protecting my chickens from predators. Built a 1 kW autonomous tank robot that you text from your phone.
- Tank drive chassis with Xbox controller override + text-command autonomous modes
- YOLOv8 601-class object detection on Jetson Orin Nano (same vision base as RealTimeAICam)
- Dual PTZ ONVIF cameras with depth overlay + 3D LIDAR mapping
- Full hardware postmortem after a real-world testing injury — Xbox-controller-first safety architecture, 20 failure points documented and fixed
- Pulls a cart of firewood. Actually.

The honest goal: turn this into a Lego-clip-in modular robotics kit where the same vision + voice + local-AI brain I've built for the desk runs on the robot too.

https://github.com/user-attachments/assets/6a05e239-ce66-46ee-b951-474730370bfe

<a href="https://youtu.be/NWnGvvdvRik"><img src="https://img.youtube.com/vi/NWnGvvdvRik/maxresdefault.jpg" width="480" alt="▶ Watch the 53-second demo"></a>

`Teensy` `ESP32` `Jetson Orin Nano` `YOLOv8` `TensorRT` `RPLidar` `Modbus` `PTZ ONVIF` `Robotics` `Python` `Node.js`

---

### [VisionBuilder — train your robot's eyes on the phone](https://github.com/nicedreamzapp/VisionBuilder) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/VisionBuilder?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/VisionBuilder/stargazers)
Roboflow on your phone — for training your own robot. Privately. On-device. With photos you already took.
- SAM 2.1 segmentation, MobileCLIP 2 embeddings, YOLO 26 export — all running locally on iOS 26
- Built so I can train new vision classes for CemaniHomesteadRobot without ever uploading frames to a cloud labeling service
- Honest WIP — shipping in the open

`Swift` `iOS 26` `CoreML` `SAM 2.1` `MobileCLIP 2` `YOLO 26`

---

## THE FAMILY PROJECT

### [JaneOS / Bloom — adaptive learning for one little kid](https://github.com/nicedreamzapp/JaneOS) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/JaneOS?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/JaneOS/stargazers)
A FREE 1st-grade adaptive learning tutor I built for my daughter — and gave away.
- Voice-driven and theme-rotating (unicorns, dinosaurs, space, cats, Bluey)
- Covers reading, phonics, sight words, addition, subtraction, place value, science, social-emotional learning, letter tracing
- Every question generated fresh by AI — never sees the same one twice
- Difficulty climbs as she masters skills, gently drops if she struggles
- Click-only safe interface — no microphone, no typing, no chat — built parent-first

`Claude API` `Piper TTS` `Flask` `Anthropic` `Adaptive Learning`

---

## RECEIPTS — DOES LOCAL ACTUALLY WORK?

### [ds4-three-way — local AI vs cloud, same prompt, one MacBook](https://github.com/nicedreamzapp/ds4-three-way)
The day Antirez shipped `ds4`, I gave the same prompt to three different AI engines on the same 128 GB MacBook Pro. Local DeepSeek V4 Flash beat cloud Claude on wall-clock time.

| Engine | Time | Output | Hosted on |
|---|---:|---:|---|
| 🐳 DeepSeek V4 Flash (`ds4` local) | 103 s | 3,259 tokens | Apple Silicon GPU |
| ☁️ Cloud Claude (Max plan) | 192 s | ~3,500 tokens | Anthropic data center |
| 🟢 Gemma 4 31B (MLX local) | 131 s | 1,992 tokens | Apple Silicon GPU |

Companion to [claude-code-local](https://github.com/nicedreamzapp/claude-code-local).

---

## INTERNAL BUILDS (NO PUBLIC REPO)

**HQ Dashboard** — Central command center at [hq.nicedreamzwholesale.com](https://hq.nicedreamzwholesale.com). Email triage across 4 Gmail accounts, real-time WooCommerce order monitoring, full shipping system with USPS/UPS/FedEx rates + one-click label purchase + thermal printing, eBay listing management, 2FA / rate-limited / WSGI hardened. Hosts Ohm, the LLM-driven chat agent. `Python` `Flask` `Gunicorn` `EasyPost API` `WooCommerce API` `Gmail API` `Anthropic Sonnet` `nginx`

**Ohm — the chat agent that bridges the mesh** — Sonnet 4.6 web chat at hq/ohm. When Ohm needs heavy work done, it tools out to `mini_claude(prompt)` → POST to FiaOS `/api/command` → runs `claude -p` on the mini under my keychain → uses Max plan Opus at zero API cost. Tools available: `bash_vps`, `read_file`, `list_dir`, `wc_orders`, `imessage_to_matt`, `add_to_ohm_inbox`, `now_iso`, `mini_claude`. `Python` `Anthropic API` `SSH` `Flask`

**AI Trading System** — Multi-agent autonomous trading with self-improving feedback loop. 6 named agents (Sentinel, Scout, Arb Scanner, Postmortem, Kalshi Sniper, Trade Gate). `daily-brain` on the VPS runs at 3:30am, reviews every trade through Opus (free, via mini_claude), writes lessons learned, feeds them back into the next decision. `Python` `Node.js` `Anthropic Claude` `Coinbase CDP` `Kalshi API`

**AI Customer Chatbot** — Customer support trained on the full Divine Tribe product lineup. Mistral 7B fine-tuned with RLHF + Claude-powered hybrid RAG/CAG. Knows 134 products, recommends by use case. `Mistral 7B` `RLHF` `Claude` `Flask` `WooCommerce`

---

## E-COMMERCE EMPIRE

4 stores, 140+ products, 5,000+ units shipped. All automated.

| Site | What It Is |
|------|-----------|
| [ineedhemp.com](https://ineedhemp.com) | Divine Tribe vaporizers — American-owned since 2013 |
| [nicedreamzwholesale.com/software](https://nicedreamzwholesale.com/software/) | Software projects — open-source tools, AI agents, builds |
| [tribeseedbank.com](https://tribeseedbank.com) | Seed bank |
| [marijuanaunion.com](https://marijuanaunion.com) | Community & marketing hub |

Every store has: SEO-optimized product pages, structured data schema, automated order processing, AI chatbot support.

---

## LAB NOTEBOOK

> _Smaller builds, research experiments, and "I wonder if this works" projects._

<table>
<tr>
<td width="50%" align="center">

### [BitcoinPredictor](https://github.com/nicedreamzapp/BitcoinPredictor)
**Real-time Bitcoin Trading with AI**

Live prices · ML predictions · Trading signals · Web dashboard

<img src="https://raw.githubusercontent.com/nicedreamzapp/BitcoinPredictor/refs/heads/main/BitTraderUiScreen.png" width="300">

`Bitcoin` `Trading` `AI` `WebSockets`

</td>
<td width="50%" align="center">

### [Family Planner](https://github.com/nicedreamzapp/Family-Planner)
**Skylight-Inspired Family Dashboard**

Voice control · OCR scanning · AI assistant · Runs on old tablets

<img src="https://raw.githubusercontent.com/nicedreamzapp/Family-Planner/main/screenshot.png" width="300">

`Dashboard` `Voice Control` `OCR`

</td>
</tr>
<tr>
<td width="50%" align="center">

### [SpeakAnywhere](https://github.com/nicedreamzapp/SpeakAnywhere)
**Voice Control for Your Computer**

Whisper-powered · Works anywhere on desktop · Just speak

`Whisper` `Voice` `Accessibility` `Python`

</td>
<td width="50%" align="center">

### [Parkinson's Vulnerability Predictor](https://github.com/nicedreamzapp/parkinsons-vulnerability-predictor)
**ML for Parkinson's Disease Research**

100% accuracy on test set · 65,000+ cells · 20-gene signature

<img src="https://raw.githubusercontent.com/nicedreamzapp/parkinsons-vulnerability-predictor/main/figures/validation/cross_dataset_vulnerability_comparison.png" width="300">

<a href="https://youtu.be/bC4hgeHS9cg"><img src="https://img.youtube.com/vi/bC4hgeHS9cg/maxresdefault.jpg" width="480" alt="▶ Watch the 64-second demo — narrated walkthrough of the meta-analysis"></a>

`Machine Learning` `Medical` `Research`

</td>
</tr>
<tr>
<td width="50%" align="center">

### [CogVideoX-Mac-Setup](https://github.com/nicedreamzapp/CogVideoX-Mac-Setup)
**AI Video Generation on Apple Silicon**

CogVideoX-5B · M4 Pro · 4-second videos in 18 minutes

https://github.com/user-attachments/assets/f756588c-2bfa-4a37-af1d-1577b85fd01a

`AI Video` `Apple Silicon` `Diffusion`

</td>
<td width="50%" align="center">

### [RealTime Fidget](https://github.com/nicedreamzapp/RealTime-Fidget)
**Photoreal Solar System for iOS**

Three.js + WKWebView · NASA Blue Marble · ACES tonemapping · 60 fps

`Swift` `Three.js` `WebGL` `iOS`

</td>
</tr>
<tr>
<td width="50%" align="center">

### [song-forge](https://github.com/nicedreamzapp/song-forge)
**Local AI Music Generator**

ACE-Step + Gemma + seed-vc voice swap · Fully on-device · No cloud APIs

`AI Music` `Apple Silicon` `MLX` `seed-vc`

</td>
<td width="50%" align="center">

### [dan-aquatic-ecology](https://github.com/nicedreamzapp/dan-aquatic-ecology)
**HSU Master's Thesis project — Aquatic Ecology**

[Live site ↗](https://nicedreamzapp.github.io/dan-aquatic-ecology/) · [▶ 1-min video](https://youtu.be/clXORLW3_1I) · Built end-to-end with Claude Code in one sitting

`HTML` `SVG` `edge-tts` `Playwright` `ffmpeg`

</td>
</tr>
<tr>
<td width="50%" align="center">

### [The Farmstand 3D](https://github.com/nicedreamzapp/the-farmstand-3d)
**Immersive WebXR Cannabis Marketplace**

A-Frame · Live at marijuanaunion.com/marketplace · Walk around in your browser

`WebXR` `A-Frame` `Three.js` `WooCommerce`

</td>
<td width="50%" align="center">

### [DisclosureDay](https://github.com/nicedreamzapp/DisclosureDay)
**SEO + AI chatbot site for the UFO film**

42+ pages · "D.I.S.C.O." AI chatbot · Live at disclosureday.nicedreamzwholesale.com

`SEO` `AI Chatbot` `Web`

</td>
</tr>
<tr>
<td width="50%" align="center">

### [MattPaint](https://github.com/nicedreamzapp/MattPaint)
**MS Paint for the Web**

Pixel-perfect clone · Zero dependencies · Pure vanilla JS

<img src="https://raw.githubusercontent.com/nicedreamzapp/MattPaint/main/screenshot.png" width="300">

`JavaScript` `Canvas` `Web App`

</td>
<td width="50%" align="center">

### [Heat-N-Clean Glass Oven](https://github.com/nicedreamzapp/Heat-N-Clean-Glass-Oven)
**Automated Glass Cleaning Kiln**

Custom built · Temperature controlled · Product design + CAD files

`Hardware` `3D Design` `Automation`

</td>
</tr>
<tr>
<td width="50%" align="center">

### [claude-failover](https://github.com/nicedreamzapp/claude-failover)
**Backup Brain for Claude Code**

One command and your `claude -p` agents keep running on a local MLX model when Max hits its limit. Default Claude, local only when needed.

`MLX` `Claude Code` `Failover` `Python`

</td>
<td width="50%" align="center">

### [story-forge](https://github.com/nicedreamzapp/story-forge)
**Local Generative Cinema**

A 4-minute animated film, end to end, on one laptop. Flux + Wan + Piper + ACE-Step + ffmpeg. No cloud.

`Flux` `Wan` `Piper` `ACE-Step` `ffmpeg`

</td>
</tr>
<tr>
<td width="50%" align="center">

### [x-cleanup-agent](https://github.com/nicedreamzapp/x-cleanup-agent)
**X Follow-List Cleanup Agent**

395 dormant unfollows in 40 minutes, driven through your own logged-in browser. No scraper, no API key, no stored credentials.

`Claude Code` `AppleScript` `Brave` `Automation`

</td>
<td width="50%" align="center">

### [job-search-agent](https://github.com/nicedreamzapp/job-search-agent)
**Daily AI Job-Scoring Agent**

Scores roles across 50+ companies via Ashby, Greenhouse, and Lever, then drafts a 200-word pitch for the top matches. Windows build too.

`Python` `Local AI` `Ashby` `Greenhouse` `Lever`

</td>
</tr>
</table>

---

<div align="center">

## TECH STACK

| Category | Technologies |
|:---------|:------------|
| **Languages** | `Python` `Swift` `TypeScript` `JavaScript` `C++` `PHP` |
| **AI / ML** | `Claude (Opus + Sonnet + Haiku)` `MLX` `Gemma 4 31B` `Llama 3.3 70B` `Qwen 3.5 122B` `Mistral 7B` `YOLOv8` `SAM 2.1` `MobileCLIP 2` `CogVideoX` `Whisper` `CoreML` `Piper TTS` |
| **APIs** | `WooCommerce` `EasyPost` `Gmail` `Google Search Console` `Coinbase CDP` `Kalshi` `eBay` `Reddit` `LinkedIn` |
| **Infrastructure** | `nginx` `gunicorn` `PM2` `Let's Encrypt` `UFW` `SSH` `Cloudflare Tunnel` `LaunchAgents` `systemd` `cron` |
| **Mobile** | `iOS` `Xcode` `Metal` `Apple Silicon` `LiDAR` `iMessage bridge` |
| **Robotics** | `Arduino` `Teensy` `ESP32` `Jetson Orin Nano` `ONVIF` `RPLidar` `Tank Drive` |

---

## WHY THIS EXISTS

I run [Divine Tribe](https://ineedhemp.com) — vaporizer hardware, since 2013. Cinch ships those orders. Everything else is downstream of paying the bills.

**Nice Dreamz LLC** is the consulting umbrella on top. The public surface is [AirGap AI](https://nicedreamzwholesale.com/airgap) — Private AI / Fractional AI work for law, medical, and compliance-sensitive firms — the kind of clients who can't put their data into a cloud chatbot. Every tool above is either something I use on a real engagement or something I built to find out whether the local-AI approach holds up under real workload. The three-node mesh is the demo: it's been my daily driver for a year and a half.

I'm also building out the **[Cannabis Device Safety Institute](https://cdsi.click)** in parallel — a standards body for cannabis-consumption hardware, aiming to be first-in-line when federal research funding lands.

The long arc is the robot. Modular, Lego-clip-in, runs the same local AI stack as my laptop and the mini. That's why the vision pipeline shows up in three places (RealTimeAICam, VisionBuilder, CemaniHomesteadRobot) — same eyes, different bodies.

Still figuring it out. No investors. No team. One MacBook, one Mac mini, one VPS, and a lot of late nights.

---

[ineedhemp.com](https://ineedhemp.com) · [GitHub](https://github.com/nicedreamzapp) · [LinkedIn](https://www.linkedin.com/in/matt-macosko-34708235/)

<sub>Built with code, caffeine, and Claude · Humboldt County, CA</sub>

</div>
