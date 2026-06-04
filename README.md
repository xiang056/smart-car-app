# Smart Car App — Flutter BLE 遙控介面

STM32F407 智能小車的配套 Flutter App，透過 BLE 與車載 HM-10 模組進行雙向通訊。

> 配套韌體：[Smart-Car](https://github.com/xiang056/Smart-Car)

---

## 功能

- **BLE 掃描與連線** — 自動列出附近 BLE 裝置，依訊號強度排序
- **方向控制** — 長按方向鍵持續送出指令，放開自動停止
- **即時狀態顯示** — 接收 STM32 telemetry，顯示當前行駛狀態（9 態）
- **連線管理** — 斷線自動偵測，狀態列即時更新

---

## 畫面

| 元件 | 說明 |
|------|------|
| 狀態列 | 連線狀態 / 裝置名稱 |
| 狀態卡片 | 顯示 STOP / FORWARD / BACKWARD / LEFT / RIGHT / FWD LEFT … 共 9 種 |
| 方向鍵 | F（前）、B（後）、L（左）、R（右）、STOP（中央） |

---

## BLE 通訊協議

### 指令（App → STM32，單 ASCII 字元）

| 字元 | 動作 |
|------|------|
| `F` | 前進 |
| `B` | 後退 |
| `L` | 左轉 |
| `R` | 右轉 |
| `S` | 停止 |

### Telemetry（STM32 → App，每 300ms）

```
S,<speed%>,<state>\n
```

| state 值 | 顯示 |
|---------|------|
| 0 | STOP |
| 1 | FORWARD |
| 2 | BACKWARD |
| 3 | LEFT |
| 4 | RIGHT |
| 5 | FWD LEFT |
| 6 | FWD RIGHT |
| 7 | BWD LEFT |
| 8 | BWD RIGHT |

---

## 開發環境

| 項目 | 版本 |
|------|------|
| Flutter | 3.x |
| Dart | 3.x |
| 主要套件 | `flutter_blue_plus`、`permission_handler` |
| 測試平台 | Android |

---

## 快速開始

```bash
flutter pub get
flutter run
```

Android 需開啟藍牙與位置權限（App 啟動時自動請求）。

---

## HM-10 連線說明

1. 點擊右上角藍牙圖示開始掃描
2. 選擇名稱含 **HM-10** 或 **MLT-BT05** 的裝置
3. 連線成功後狀態列顯示裝置名稱，方向鍵啟用
