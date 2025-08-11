# RealTime AI Camera
🚀 **YOLOv8 with all 601 object classes on iPhone — capped at 30 FPS for stability and battery safety**  
Real-time **Object Detection**, **OCR**, **Offline Translation**, and **LiDAR Distance** — built specifically for **iPhone**, works **100% offline**, and designed with privacy at its core.

![Built for iPhone](https://img.shields.io/badge/Built%20for-iPhone-blue?style=for-the-badge&logo=apple)
![Works Offline](https://img.shields.io/badge/Works_Offline-Yes-brightgreen?style=for-the-badge)
![Privacy First](https://img.shields.io/badge/Privacy-Non--Negotiable-red?style=for-the-badge)
![100% Free](https://img.shields.io/badge/100%25_Free-No_Ads-brightgreen?style=for-the-badge&logo=gift)
![Real-Time](https://img.shields.io/badge/Real--Time-30_FPS-success?style=for-the-badge)
![No Internet Required](https://img.shields.io/badge/Internet-Not_Required-success?style=for-the-badge&logo=wifi-off)

![SwiftUI](https://img.shields.io/badge/SwiftUI-5.0-orange?style=for-the-badge&logo=swift)
![CoreML](https://img.shields.io/badge/CoreML-Powered-purple?style=for-the-badge&logo=apple)
![Metal](https://img.shields.io/badge/Metal-Accelerated-silver?style=for-the-badge&logo=apple)
![YOLOv8](https://img.shields.io/badge/YOLOv8-601_Classes-yellow?style=for-the-badge)
![LiDAR](https://img.shields.io/badge/LiDAR-Supported-cyan?style=for-the-badge)

![iOS 15+](https://img.shields.io/badge/iOS-15%2B-000000?style=for-the-badge&logo=ios)
![iPhone 12+](https://img.shields.io/badge/iPhone-12%2B-black?style=for-the-badge&logo=apple)
![Xcode 16](https://img.shields.io/badge/Xcode-16%2B-1575F9?style=for-the-badge&logo=xcode)
![App Size](https://img.shields.io/badge/App_Size-<40MB-success?style=for-the-badge)

![Languages](https://img.shields.io/badge/Languages-EN_|_ES-blue?style=for-the-badge)
![OCR](https://img.shields.io/badge/OCR-On--Device-orange?style=for-the-badge)
![Battery Safe](https://img.shields.io/badge/Battery-Optimized-green?style=for-the-badge&logo=battery-full)
![Airplane Mode](https://img.shields.io/badge/✈️_Airplane_Mode-Compatible-skyblue?style=for-the-badge)
![Neural Engine](https://img.shields.io/badge/Neural_Engine-Optimized-ff69b4?style=for-the-badge)

![Active Development](https://img.shields.io/badge/Status-Active_Development-brightgreen?style=for-the-badge)
![GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue?style=for-the-badge)
![PRs Welcome](https://img.shields.io/badge/PRs-Welcome-brightgreen?style=for-the-badge)

---
## ✨ Features
- 🐶 **Object Detection** — YOLOv8 trained on **Open Images V7** with **601 classes**
- 📝 **English OCR** — On-device printed text recognition
- 🌎 **Spanish → English Translation** — Offline, rule-based + dictionary translation
- 📏 **LiDAR Distance** — Per-object depth measurements on supported iPhones
- 💝 **100% Free** — No ads, no in-app purchases, no subscriptions
- 🔒 **Privacy First** — No tracking, no servers, airplane-mode ready
- ⚡ **Optimized for iPhone** — CoreML + Metal acceleration with a **safe 30 FPS cap** to avoid overheating
---
## 🛡️ Performance & Safety
- **Frame-rate cap**: Fixed at **30 FPS** for device stability
- **Dynamic resolution scaling**: Adjusts input size automatically for heavy workloads
- **Optional frame skipping**: Reduces processing load when device heat rises
- **Neural Engine/GPU balancing**: Automatically chooses the best inference path
---
## 🛠️ Technology Stack
- **YOLOv8** ([Ultralytics](https://github.com/ultralytics/ultralytics))
- **Google Open Images V7** training set
- **CoreML**, **Metal**, and **Apple Neural Engine** for acceleration
- **SwiftUI** for the interface
- **LiDARKit** for depth data (Pro models with LiDAR)
---
## 🚀 Getting Started
### Requirements
- macOS with **Xcode 16+**
- **iOS 15+** device (iPhone 12 or newer recommended; LiDAR on Pro models)
### Build & Run
1. Clone this repository
2. Open `RealTime Ai Cam.xcodeproj` in Xcode
3. Connect your iPhone and select it as the run target
4. Build and run
### Permissions
- **Camera** (required)
- **Microphone** (only for voice-related features)
- **Motion/Depth** (required for LiDAR functionality)
---
## 🔁 Model Replacement
- Replace the YOLOv8 `.mlpackage` in `/Models` with your own CoreML model
- Update input/output handling in `YOLOv8Processor.swift` if your model shape differs
- Use **Git LFS** to manage large model files and avoid bloated repo size
---
## 🔒 Privacy
This app is **100% offline**:
- ✅ No data collection
- ✅ No internet connection required
- ✅ No location tracking
- ✅ All processing is done on-device
Your privacy is **non-negotiable**.
---
## 📸 Screenshots
### Spanish → English Translation
![Spanish → English Translation](./IMG_2169.png)
### Object Detection
![Object Detection](./IMG_2208.png)
### Home Screen
![Home Screen](./IMG_2227.png)
### App Size on iPhone
![App Size on iPhone](./IMG_2224.jpeg)
### LiDAR
![LiDAR](./IMG_2247.png)
---
## 🤝 Contributing
Pull requests are welcome. Please open an Issue for:
- Bug reports
- Feature requests
- Performance improvements
Include:
- Device model + iOS version
- Steps to reproduce
- Logs or crash reports (if applicable)
- Screenshots/video for UI issues
---
## 📄 License
This project is licensed under **GPL-3.0** with **additional App Store/TestFlight restrictions**.  
See [LICENSE](LICENSE) for complete terms.
You may:
- View, study, and modify for personal or educational purposes
You may **not**:
- Distribute this app on the **Apple App Store** or **TestFlight** without **written permission**
---
## 🙌 Credits
- **YOLOv8** — © Ultralytics  
- **Open Images Dataset V7** — © Google  
- **CoreML**, **Metal**, **SwiftUI**, **LiDARKit** — © Apple Inc.
---
## 📬 Contact
Questions about contributing, licensing, or App Store permission?  
📧 info@nicedreamzwholesale.com
