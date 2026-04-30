<div align="center">

# MATT MACOSKO — Nice Dreamz LLC

<pre>
┌──────────────────────────────────────────────────────────────────┐
│  Humboldt County, California  ·  Nice Dreamz LLC                │
│  Building AI tools, automation, and robots.         │
│  Code, curiosity, and the right tools.                   │
└──────────────────────────────────────────────────────────────────┘
</pre>

[![GitHub followers](https://img.shields.io/github/followers/nicedreamzapp?style=for-the-badge&color=236ad3&labelColor=1155ba)](https://github.com/nicedreamzapp)
[![Repos](https://img.shields.io/badge/dynamic/json?label=Public%20Repos&query=%24.public_repos&url=https%3A%2F%2Fapi.github.com%2Fusers%2Fnicedreamzapp&style=for-the-badge&color=58a6ff&labelColor=388bfd)](https://github.com/nicedreamzapp?tab=repositories)

---

### *"If it takes more than 10 minutes, I automate it. If it needs AI, I build it from scratch."*

---

</div>

## WHAT I BUILT (AND USE EVERY DAY)

### [Claude Code Local](https://github.com/nicedreamzapp/claude-code-local) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/claude-code-local?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/claude-code-local/stargazers) [![Forks](https://img.shields.io/github/forks/nicedreamzapp/claude-code-local?style=flat-square&color=58a6ff)](https://github.com/nicedreamzapp/claude-code-local/network/members)
Run Claude Code 100% on-device with local AI on Apple Silicon. No cloud, no API fees.
- 3 models to choose from: Gemma 4 31B (fast), Llama 3.3 70B (smartest), Qwen 3.5 122B (biggest)
- 4 modes: Code, Browser Agent, Narrative (voice), and Phone (iMessage remote control)
- Custom MLX server with Anthropic-compatible API — swap models with one env var
- setup.sh auto-detects your RAM, picks the right model, and creates a desktop launcher
- Your code never leaves your Mac — not for inference, not for telemetry, not for anything

`MLX` `Apple Silicon` `Claude Code` `Gemma` `Llama` `Qwen` `Python`

---

### [NarrateClaude + Ohm — voice-first AI](https://github.com/nicedreamzapp/NarrateClaude) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/NarrateClaude?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/NarrateClaude/stargazers)
Talk to your Mac, hear it reply in your own cloned voice. Now also accessible from any browser, anywhere.
- **NarrateClaude** — on-device wake-word + cloned voice + local LLM, 100% private, works on a plane
- **Ohm** — same voice loop wrapped in a private web chat I host on my own infrastructure — type from any browser, hear the reply in my own voice
- VPS proxies the chat to a self-hosted bridge on a Mac mini at home, claude on the Max plan answers, audio pipes back to the browser
- Zero cloud-AI cost, zero paid API calls per message

`Pocket TTS` `Apple Silicon` `Claude Code Max plan` `Flask` `nginx` `Python`

---

### HQ Business Dashboard
Central command center for all Divine Tribe operations. Accessible from any device.
- Email triage across 4 Gmail accounts — one-click reply, archive, delete
- Real-time order monitoring across 3 WooCommerce stores
- Full shipping system — auto-loads USPS/UPS/FedEx rates, one-click label purchase, thermal printing
- Replaced Stamps.com entirely with custom EasyPost integration
- eBay listing management, site uptime monitoring, Reddit tracking
- Secured with 2FA, rate-limited login, HTTPS, production WSGI server

`Python` `Flask` `Gunicorn` `EasyPost API` `WooCommerce API` `Gmail API` `nginx`

---

### AI Trading System
Multi-agent autonomous trading system with AI oversight and self-improving feedback loop.
- 6 named agents: Sentinel (market mood), Scout (opportunities), Arb Scanner, Postmortem, Kalshi Sniper, Trade Gate
- Opus reviews every trade, writes lessons learned, feeds them back into the next decision
- Coinbase crypto trading + Kalshi prediction markets
- The system literally learns from its own mistakes

`Python` `Node.js` `Anthropic Claude` `Coinbase CDP` `Kalshi API`

---

### AI Customer Chatbot
Customer support chatbot trained on the full Divine Tribe product lineup.
- Mistral 7B fine-tuned with RLHF + Claude-powered hybrid RAG/CAG
- Knows 134 products, recommends by use case
- Handles support questions 24/7

`Mistral 7B` `RLHF` `Claude` `Flask` `WooCommerce`

---

### [Cemani Homestead Robot](https://github.com/nicedreamzapp/CemaniHomesteadRobot) &nbsp; [![Stars](https://img.shields.io/github/stars/nicedreamzapp/CemaniHomesteadRobot?style=flat-square&color=f5c542)](https://github.com/nicedreamzapp/CemaniHomesteadRobot/stargazers)
Started with a simple problem: protecting my chickens from predators. Built a 1 kW autonomous tank robot that you text from your phone.
- Tank drive chassis with Xbox controller override + text-command autonomous modes
- YOLOv8 601-class object detection on Jetson Orin Nano
- Dual PTZ ONVIF cameras with depth overlay + 3D LIDAR mapping
- Full hardware postmortem after a real-world testing injury — Xbox-controller-first safety architecture, 20 failure points documented and fixed
- Pulls a cart of firewood. Actually.

https://github.com/user-attachments/assets/6a05e239-ce66-46ee-b951-474730370bfe

`Teensy` `ESP32` `Jetson Orin Nano` `YOLOv8` `TensorRT` `RPLidar` `Modbus` `PTZ ONVIF` `Robotics` `Python` `Node.js`

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

## MORE PROJECTS

<table>
<tr>
<td width="50%" align="center">

### [RealTimeAICam](https://github.com/nicedreamzapp/RealTimeAICam)
**Largest Free iPhone Object Detection**

601 objects · 100% offline · OCR · LiDAR depth · No subscription

<img src="https://raw.githubusercontent.com/nicedreamzapp/RealTimeAICam/main/EA08B469-F8A2-435D-A3B3-44AEF833E38E.png" width="300">

`YOLOv8` `iOS` `Swift` `CoreML`

</td>
<td width="50%" align="center">

### [Parkinson's Vulnerability Predictor](https://github.com/nicedreamzapp/parkinsons-vulnerability-predictor)
**ML for Parkinson's Disease Research**

100% accuracy on test set · 65,000+ cells · 20-gene signature

<img src="https://raw.githubusercontent.com/nicedreamzapp/parkinsons-vulnerability-predictor/main/figures/validation/cross_dataset_vulnerability_comparison.png" width="300">

`Machine Learning` `Medical` `Research`

</td>
</tr>
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

### [CogVideoX-Mac-Setup](https://github.com/nicedreamzapp/CogVideoX-Mac-Setup)
**AI Video Generation on Apple Silicon**

CogVideoX-5B · M4 Pro · 4-second videos in 18 minutes

https://github.com/user-attachments/assets/f756588c-2bfa-4a37-af1d-1577b85fd01a

`AI Video` `Apple Silicon` `Diffusion`

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

### [MattPaint](https://github.com/nicedreamzapp/MattPaint)
**MS Paint for the Web**

Pixel-perfect clone · Zero dependencies · Pure vanilla JS

<img src="https://raw.githubusercontent.com/nicedreamzapp/MattPaint/main/screenshot.png" width="300">

`JavaScript` `Canvas` `Web App`

</td>
<td width="50%" align="center">

### [SpeakAnywhere](https://github.com/nicedreamzapp/SpeakAnywhere)
**Voice Control for Your Computer**

Whisper-powered · Works anywhere on desktop · Just speak

`Whisper` `Voice` `Accessibility` `Python`

</td>
</tr>
</table>

---

<div align="center">

## TECH STACK

| Category | Technologies |
|:---------|:------------|
| **Languages** | `Python` `Swift` `TypeScript` `JavaScript` `C++` `PHP` |
| **AI / ML** | `Claude (Opus + Haiku)` `MLX` `Mistral 7B` `YOLOv8` `CogVideoX` `Whisper` `CoreML` |
| **APIs** | `WooCommerce` `EasyPost` `Gmail` `Google Search Console` `Coinbase CDP` `Kalshi` `eBay` `Reddit` `LinkedIn` |
| **Infrastructure** | `nginx` `gunicorn` `PM2` `Let's Encrypt` `UFW` `SSH` |
| **Mobile** | `iOS` `Xcode` `Metal` `Apple Silicon` `LiDAR` |
| **Robotics** | `Arduino` `Jetson Nano` `ONVIF` `Tank Drive` `Object Detection` |

---

## THE STORY

```
One problem (protecting chickens from predators)
  → learned robotics and computer vision
    → built iPhone apps with YOLOv8
      → created medical ML for Parkinson's research
        → automated an entire e-commerce business
          → built AI trading agents that learn from their mistakes
            → made Claude Code run 100% local on Apple Silicon (600+ stars)
              → still building
```

Running [Divine Tribe](https://ineedhemp.com) since 2013.
Every task automated or AI-assisted.
120+ scripts. 6 AI agents. 4 stores. 1 robot. 0 investors.

---

[ineedhemp.com](https://ineedhemp.com) · [GitHub](https://github.com/nicedreamzapp) · [LinkedIn](https://www.linkedin.com/company/divine-tribe/)

<sub>Built with code, caffeine, and Claude · Humboldt County, CA</sub>

</div>
