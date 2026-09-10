# SynthBox (FFS)

<p align="center">
  <strong>基於 Flutter 與 FluidSynth 的跨平台 MIDI 播放器與 SoundFont 合成工具</strong>
  <br />
  <em>A cross-platform MIDI player and real-time synthesizer built with Flutter & FluidSynth</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/FluidSynth-v2.6+-E64A19" alt="FluidSynth" />
  <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-success" alt="Platforms" />
  <img src="https://img.shields.io/badge/License-MPL--2.0-blue.svg" alt="License" />
</p>

---

## 目錄 (Table of Contents)

- [簡介 (Introduction)](#-簡介-introduction)
- [功能特點 (Features)](#-功能特點-features)
- [系統架構 (Architecture)](#-系統架構-architecture)
- [支援格式 (Supported Formats)](#-支援格式-supported-formats)
- [平台支援與動態庫配置 (Platform & Dynamic Library Setup)](#-平台支援與動態庫配置-platform--dynamic-library-setup)
  - [Windows](#windows)
  - [macOS](#macos)
  - [Android](#android)
  - [iOS](#ios)
  - [Linux](#linux)
- [快速開始與建置 (Getting Started & Building)](#-快速開始與建置-getting-started--building)
- [實作細節與問題處理 (Implementation Details)](#-實作細節與問題處理-implementation-details)
- [本地化與多語言 (Localization & i18n)](#-本地化與多語言-localization--i18n)
- [授權協議 (License)](#-授權協議-license)

---

## 簡介 (Introduction)

**SynthBox**（專案名稱 **FFS** / *Flutter FluidSynth Music Box*）是一款基於 Flutter 與 FluidSynth 打造的開源跨平台 MIDI 音樂播放器。

不同於一般直接調用系統陽春音效（如 Windows 內建軟體波表）的播放器，SynthBox 透過 **Dart FFI** 調用成熟的 **FluidSynth C-API**，讓使用者可以自由載入喜愛的 SoundFont 音色庫（`.sf2`、`.sf3`、`.dls`）來合成與播放 MIDI 音樂。

---

## 功能特點 (Features)

### 音訊合成與動態庫支援
- **FluidSynth 核心**：透過 FFI 直接調用原生 C 函式庫進行即時音訊合成。
- **音訊驅動切換**：
  - **Windows**：WASAPI、DirectSound、WaveOut、PortAudio
  - **macOS / iOS**：CoreAudio、PortAudio
  - **Android**：Oboe、OpenSL ES
  - **Linux**：PulseAudio、ALSA、JACK、PortAudio
- **動態庫旁加載 (Sideloading)**：在設定頁面中支援直接選取本機的 `.dll`、`.dylib` 或 `.so`，方便測試不同版本編譯的 FluidSynth 庫。

### SoundFont 音色庫管理
- 支援標準 `.sf2`、OGG 壓縮格式 `.sf3` 以及 `.dls` 音色庫。
- **歷史清單**：自動記錄曾載入過的 SoundFont，方便隨時切換。
- **即時切換音色**：播放中更換 SoundFont 會自動先靜音當前發聲、載入新音色庫並自動定位回當前進度繼續播放。

### 時間軸與 MIDI 解析
- **輕量 SMF 解析模組 (`midi_parser.dart`)**：針對 Standard MIDI File (Format 0 & Format 1) 進行基本結構解析。
- **Tempo 映射計算**：讀取 MIDI 中的變速事件（Set Tempo Meta-Events）與 PPQ Division 建立對照表，使變速曲目的進度條拖動與播放秒數換算更準確。
- **獨立進度通知 (`progressNotifier`)**：將每 100ms 的進度條更新抽離出全域狀態，避免播放時觸發整頁無謂的重新構建（Rebuild）。

### 系統媒體控制整合
- **Windows SMTC**：適配 Windows 系統媒體控制列，支援鍵盤媒體播放/暫停/切歌快捷鍵。
- **Android 前台服務 & MediaSession**：支援通知欄 MediaStyle 控制、鎖定螢幕媒體介面與後台背景播放。
- **iOS / macOS Now Playing**：支援系統控制中心與選單列的媒體資訊顯示與控制。
- **播放列表模式**：支援單曲循環、列表循環、順序播放、隨機播放、下一首播放以及清單拖曳排序。

### 檔案瀏覽與儲存路徑
- **格式自動過濾**：瀏覽目錄時僅列出資料夾、MIDI 檔案及 SoundFont 檔案，簡化尋找流程。
- **各平台路徑適配**：
  - Windows：提供「本機 (This PC)」磁碟機列表（C:\、D:\ 等分區）。
  - macOS：支援快速進入 `/Volumes` 查看外接硬碟或隨身碟。
  - Linux：支援 `/media` 與 `/mnt` 常見掛載路徑。
  - Android：適配 `/storage/emulated/0` 與外接記憶卡存取。

### Material 3 介面
- **動態取色 (Dynamic Color)**：支援 Android 12+ 與桌面系統的動態配色（Material You）。
- **響應式排版**：針對手機直式螢幕與桌面寬螢幕提供適當的佈局切換。
- **背景初始化**：啟動時將音訊核心與檔案掃描交由背景非同步載入，減少啟動等待時間。

---

## 系統架構 (Architecture)

```mermaid
flowchart TB
    subgraph UI_Layer [UI 介面層 (Flutter)]
        MainPage[主介面]
        FileBrowser[檔案瀏覽]
        PlayerWidget[播放控制器]
        PlaylistSheet[播放列表]
        SettingsPage[設定與庫管理]
    end

    subgraph Service_Layer [業務與狀態層 (Services)]
        FileService[檔案瀏覽服務]
        SoundFontService[音色庫管理服務]
        FluidService[FluidSynth 播放服務]
        MidiParser[MIDI 檔案解析]
        AudioHandler[系統媒體整合]
        I18nService[多語言服務]
    end

    subgraph Native_Layer [原生核心層 (C / FFI)]
        FFIBindings[Dart FFI 綁定]
        FFILoader[動態庫載入器]
        FluidLib[(libfluidsynth 動態庫)]
    end

    subgraph Audio_Drivers [系統音訊輸出]
        WASAPI[Windows WASAPI / DSound]
        CoreAudio[macOS / iOS CoreAudio]
        Oboe[Android Oboe / OpenSL ES]
        ALSA[Linux ALSA / PulseAudio]
    end

    UI_Layer --> Service_Layer
    FluidService --> FFIBindings
    FFILoader --> FluidLib
    FFIBindings --> FluidLib
    AudioHandler --> FluidService
    FluidLib --> Audio_Drivers
```

---

## 支援格式 (Supported Formats)

| 類型 | 副檔名 | 說明 |
| :--- | :--- | :--- |
| **MIDI 音樂檔** | `.mid`, `.midi`, `.kar` | 支援 Standard MIDI File Format 0 與 Format 1，包含卡拉 OK MIDI 格式。 |
| **SoundFont 音色庫** | `.sf2`, `.sf3`, `.dls` | 支援 SoundFont 2、OGG 壓縮格式 SoundFont 3 以及 DLS 音色庫。 |

---

## 平台支援與動態庫配置 (Platform & Dynamic Library Setup)

本專案底層依賴原生 FluidSynth 動態庫，各平台配置情況如下：

### Windows
- **內建打包**：專案在 `windows/CMakeLists.txt` 已配置打包 `libfluidsynth-3.dll`、`SDL3.dll` 與 `sndfile.dll`，編譯後會自動複製到執行檔旁。
- **環境搜尋**：若未找到，會依序尋找常見路徑（MSYS2、vcpkg、`C:\Program Files\FluidSynth\bin` 等）。
- **手動載入**：也可以在「設定」中手動指定任意資料夾中的 `libfluidsynth-3.dll`。

### macOS
- **建議透過 Homebrew 安裝**：
  ```bash
  brew install fluidsynth
  ```
  程式會自動尋找 `/opt/homebrew/lib/libfluidsynth.dylib` 或 `/usr/local/lib/libfluidsynth.dylib`。
- **手動指定**：如有自行編譯的庫，可在設定頁面中手動選取 `.dylib`。

### Android
- **內建各架構庫**：`android/app/src/main/jniLibs` 已附帶 **arm64-v8a**、**armeabi-v7a**、**x86**、**x86_64** 的預編譯庫（包含 `libfluidsynth.so`、`liboboe.so` 等）。
- **權限需求**：需要檔案存取權限以讀取儲存空間內的 MIDI/SF2 檔案，以及通知權限以維持背景播放與鎖定螢幕控制。

### iOS
- **Framework 整合**：專案目錄包含 `FluidSynth.xcframework`，可透過 `DynamicLibrary.process()` 調用。

### Linux
- **安裝系統庫**：
  - Ubuntu / Debian:
    ```bash
    sudo apt update
    sudo apt install libfluidsynth3 libfluidsynth-dev
    ```
  - Arch Linux:
    ```bash
    sudo pacman -S fluidsynth
    ```
  - Fedora:
    ```bash
    sudo dnf install fluidsynth fluidsynth-devel
    ```

---

## 快速開始與建置 (Getting Started & Building)

### 前置環境
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (`^3.x`，Dart `^3.11+`)
- 目標平台的編譯工具（Visual Studio C++ / Xcode / Android Studio / Clang 等）

### 下載專案與依賴
```bash
git clone https://github.com/your-username/ffs.git
cd ffs
flutter pub get
```

### 執行與偵錯
```bash
# 桌面端 (Windows / macOS / Linux)
flutter run -d windows
flutter run -d macos
flutter run -d linux

# 行動端 (Android / iOS)
flutter run -d <device_id>
```

### 打包編譯 (Release)
```bash
# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Android (APK 或 App Bundle)
flutter build apk --release
flutter build appbundle --release

# iOS
flutter build ipa --release
```

---

## 實作細節與問題處理 (Implementation Details)

在開發跨平台 MIDI 合成播放器的過程中，針對底層交互做了幾項特定處理：

1. **Windows 中文 / Unicode 路徑相容**
   - 原生 C 語言標準函式庫的 `fopen(path, "rb")` 在 Windows 下容易受 ANSI 編碼限制，導致讀取中文或日語路徑下的檔案時失敗。
   - 專案在調用 C 函式庫載入檔案前，先透過 Win32 `GetShortPathNameW` API 轉換為 8.3 短路徑，避開編碼衝突。
2. **音訊設備隨選啟動 (On-Demand)**
   - 為了避免背景待機時持續佔用系統音訊驅動導致耗電或搶佔音訊通道，僅在實際播放或發聲測試時才建立 `fluid_audio_driver`，停止與暫停時即時釋放。
3. **音量增益縮放保護**
   - 多軌道密集音符在全音量輸出時容易在軟體合成階段產生破音（Clipping）。
   - 專案將內部 Synth Gain 限制在安全倍率（`maxGainFactor = 0.5`），並對音量滑桿進行映射，盡量兼顧音量與音質平衡。
4. **生命週期與 Hot Reload 保護**
   - 當開發環境觸發 Flutter Hot Reload，或桌面端接收到關閉視窗 / `SIGINT` / `SIGTERM` 時，主動中斷當前音訊執行緒，避免背景遺留未關閉的聲音或雜音。

---

## 🌐 本地化與多語言 (Localization & i18n)

目前支援以下語言：
- **繁體中文** (`zh_TW`)
- **簡體中文** (`zh_CN`)
- **English** (`en`)
- **日本語** (`ja`)

所有文字集中在 `assets/i18n/strings.csv` 管理。設定頁中提供**「本地化適配模式」**，開啟後可在畫面上直接顯示 CSV 的 `control_name` 鍵值，方便除錯與翻譯校對。

---

## 授權協議 (License)

本專案採用 [Mozilla Public License 2.0 (MPL-2.0)](LICENSE) 授權。

- 依賴的底層合成核心 [FluidSynth](https://www.fluidsynth.org/) 採用 LGPL 2.1 授權。
- 歡迎提出 Issue、建議或 Pull Request。
