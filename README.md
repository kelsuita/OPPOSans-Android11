# OPPO Sans 系统字体 Magisk 模块（Android 11）

把 OPPO Sans 4.0 作为系统默认字体，适用于 AOSP / 类原生 Android 11（SDK 30，`system-as-root`）与 Magisk 20.4+。

配套的 MiSans 版本见另一个仓库；两者共用同一份 AOSP 11 `fonts.xml` 骨架，只替换字体族里的条目，因此结构完全一致。

## 为什么需要「实例化」

OPPO Sans 4.0 官方包只提供一个**可变字体**（`OPPO Sans 4.0.ttf`，22.7 MB，内部 `wght` 轴 100–700）。Android 11 的 Minikin 对 `fonts.xml` 里的可变轴支持很有限，直接塞进去只会永远得到默认字重，400/500/700 全部失效。

所以构建前先用 fontTools 把它**实例化成静态 TTF**：

```
fontTools.varLib.instancer.instantiateVariableFont(TTFont(src), {"wght": w})
```

| 字重 | 文件 | 内部 usWeightClass |
|------|------|--------------------|
| 300 | `OPPOSans-Light.ttf` | 300 |
| 400 | `OPPOSans-Regular.ttf` | 400 |
| 500 | `OPPOSans-Medium.ttf` | 500 |
| 600 | `OPPOSans-SemiBold.ttf` | 600 |
| 700 | `OPPOSans-Bold.ttf` | 700 |

## 两个版本

| 版本 | 正文（400） | 附带文件 | 适用 |
|------|-------------|----------|------|
| Regular（默认） | `OPPOSans-Regular.ttf` | 5 个 | 想保持官方正文字重 |
| Medium | `OPPOSans-Medium.ttf` | 4 个（不含 Regular） | 觉得常规字重偏细 |

Medium 版本把 500 槽位一并上移到 SemiBold，避免 400/500 出现两个一模一样的字重阶梯。

## 改了哪些字体族

与 MiSans 模块一致，只动三个 family：

- `sans-serif`（默认字体）→ OPPO Sans 300/400/500/600/700
- `sans-serif-condensed` → 同一组
- `zh-Hans` → OPPO Sans 段插到 Noto Sans CJK **之前**

`zh-Hant` / `ja` / `ko`、serif、monospace、Emoji 与符号全部保持 ROM 原样：OPPO Sans 只有简体字库（约 29,400 字形），强行顶替繁体/日文会出现错误字形。

Noto Sans CJK 仍留在 fallback 链上，生僻字、韩文、少数民族文字不会掉字。

## 安装

1. 下载 [Releases](https://github.com/kelsuita/OPPOSans-Android11/releases) 里的 `OPPOSans-Android11-v1.0.0.zip`（Regular）或 `-Medium.zip`
2. Magisk App → 底部「模块」→ 左上角 `+` → 从本地安装 → 选择 zip
3. 重启

安装脚本会自己做校验：从包内 `fonts.xml` 反推需要的 ttf 列表，逐个核对，并打印本包实际生效的正文（400）字重。

卸载：Magisk 里移除模块并重启（`/system` 分区本身没有被真的改动）。Magisk 连续启动失败会自动停用模块；急救也可以在 recovery 里删掉 `/data/adb/modules/opposans_font`。

## 构建

```powershell
.\build.ps1                  # Regular 版 -> dist\OPPOSans-Android11-<version>.zip
.\build.ps1 -Profile medium  # Medium 版  -> dist\OPPOSans-Android11-<version>-Medium.zip
.\build.ps1 -All             # 两个都出
```

`system/etc/fonts.xml` 是唯一的字体表来源；Medium 版本由它派生，只重写 400 / 500 两个槽位，两张表因此不会走形。

## 许可

`OPPO-Sans-LICENSE.txt` 是随官方字体分发的原始许可。要点：

- 允许**原样**复制、嵌入、随软件再分发（需注明使用 OPPO Sans 并保留许可）
- **禁止修改字体文件**
- 禁止以字体本身作为独立商品再分发

本模块为了适配 Android 11 必须把可变字体实例化成静态 TTF，属于许可所禁止的「修改」。因此：**仅供本机自用，不要公开发布带字体文件的 zip。** 如果只是自己刷，构建产物留在 `dist/` 即可（该目录不进版本库）。
