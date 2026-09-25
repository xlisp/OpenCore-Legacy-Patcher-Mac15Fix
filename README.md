# 老 Mac 升级 macOS 15 后“合盖唤醒 CPU 狂转”问题排查与修复记录

> 机型：MacBook Pro (Retina, 15-inch, Mid 2015)，型号标识 `MacBookPro11,4`
> CPU：Intel Core i7-4770HQ @ 2.20GHz（Haswell 第四代，睿频最高 3.4GHz）
> 系统：macOS Sequoia 15.8 (24H23)，通过 OpenCore Legacy Patcher (OCLP) 2.5.1 安装
> 双系统：macOS + Windows (Boot Camp)
> 记录日期：2026-09-25

---

## 目录

1. [问题现象](#1-问题现象)
2. [排查过程](#2-排查过程)
3. [根本原因分析](#3-根本原因分析)
4. [解决方案](#4-解决方案)
5. [修复结果验证](#5-修复结果验证)
6. [常用诊断命令速查](#6-常用诊断命令速查)
7. [附录 A：老 Mac 用 OCLP 升级到 macOS 15 的方法](#附录-a老-mac-用-oclp-升级到-macos-15-的方法)
8. [附录 B：动态壁纸导致 CPU 高占用](#附录-b动态壁纸导致-cpu-高占用)
9. [附录 C：常见问题 FAQ](#附录-c常见问题-faq)

---

## 1. 问题现象

- 用 OCLP 升级到 macOS 15 后，正常用了一年多。
- 之前**动态壁纸**会让 CPU 和风扇一直狂转。换成普通静态图片后就好了（见附录 B）。
- 最近出现新问题：**每次合盖睡眠再打开，CPU 占用飙高，风扇全速狂转**。活动监视器里能看到一些 XPC 进程之类的系统进程占用很高。
- 奇怪的是：
  - **重启 macOS 没用**，重启后照样狂转；
  - **切到 Windows 启动一次，再重启回 macOS，就恢复正常**。

“重启无效、切 Windows 有效”这一点非常关键，说明问题不在 macOS 软件层面，而在**重启时不会重置的硬件/固件状态**上。

---

## 2. 排查过程

### 2.1 查看占用 CPU 的进程

```bash
ps -Ao pid,pcpu,pmem,etime,comm -r | head -15
```

在异常状态下，`syspolicyd`、`WindowServer`、iTerm 等**很多进程**的 CPU 占用都偏高，而不是某一个进程失控。这说明问题可能是**整个 CPU 变慢了**，而不是哪个程序写坏了。

### 2.2 查看 CPU 是否被限速（关键发现一）

```bash
pmset -g therm
```

输出：

```
CPU Power notify
	CPU_Scheduler_Limit 	= 40
	CPU_Available_CPUs 	= 8
	CPU_Speed_Limit 	= 23
```

- `CPU_Speed_Limit = 23`：系统把 CPU 限速到了正常速度的 **23%**。
- `CPU_Scheduler_Limit = 40`：调度器也只允许用 40% 的算力。
- 但同时显示 `No thermal warning level has been recorded`：**macOS 自己并没有记录到过热警告**。

### 2.3 查看 XCPM 硬件频率上限（关键发现二）

Haswell 及更新的 Intel CPU 在 macOS 下由 XCPM（XNU CPU Power Management）管理电源：

```bash
sysctl machdep.xcpm
```

异常时的输出：

```
machdep.xcpm.hard_plimit_max_100mhz_ratio: 8    ← 硬上限 = 8 × 100MHz = 800MHz
machdep.xcpm.hard_plimit_min_100mhz_ratio: 8
machdep.xcpm.soft_plimit_max_100mhz_ratio: 34   ← 软上限 = 3.4GHz（正常值）
```

**CPU 的硬上限被锁在了 800MHz**，这台机器正常应该是 3.4GHz。

`hard_plimit` 是由硬件信号强制施加的上限，最常见的来源是主板/SMC 拉起的 **BD PROCHOT**（Bi-Directional Processor Hot）信号。

### 2.4 查看电池健康（关键发现三）

```bash
ioreg -rn AppleSmartBattery | grep -E '"(Temperature|CycleCount|MaxCapacity|DesignCapacity|PermanentFailureStatus|ExternalConnected|IsCharging)"'
system_profiler SPPowerDataType | grep -E "Condition|Maximum Capacity|Cycle"
```

结果：

| 项目 | 数值 | 说明 |
|---|---|---|
| DesignCapacity（设计容量） | 8755 mAh | 出厂容量 |
| MaxCapacity（当前最大容量） | **2810 mAh** | 只剩约 **32%** |
| CycleCount（循环次数） | 484 | 这块电池是两年多前自己换的第三方电池 |
| Condition（状态） | **Service Recommended** | 系统建议维修 |
| Temperature（电池温度） | 2995（即 29.95°C） | 正常 |
| ExternalConnected | Yes | 当时插着电源 |

### 2.5 查看睡眠/唤醒日志

```bash
pmset -g log | grep -E "Sleep  |Wake  |DarkWake  |Start  " | tail -40
```

发现：

- 整夜**每约 15 分钟**就会出现一次 `DarkWake`（后台暗唤醒，屏幕不亮），原因是 `RTC/Maintenance`（Power Nap、TCP Keep Alive 等维护任务）。
- 每一条记录都写着 `Using AC (Charge:100%)`：**问题发生时一直插着电源**。

### 2.6 读取真实 CPU 温度和风扇转速（确诊）

```bash
sudo powermetrics -n 1 -i 1000 --samplers smc | grep -iE "temp|fan"
```

异常时的输出：

```
Fan: 6153 rpm
CPU die temperature: 45.05 C
```

同时，频率上限仍是 8：

```bash
sysctl machdep.xcpm.hard_plimit_max_100mhz_ratio
# machdep.xcpm.hard_plimit_max_100mhz_ratio: 8
```

**CPU 只有 45°C（很凉），风扇却接近最高转速，CPU 还被锁在 800MHz。** 由此确诊：这是一个**错误的硬件降频信号**，不是真正的过热。

---

## 3. 根本原因分析

### 3.1 因果链

```
电池严重老化（容量只剩 32%，第三方电池）
        │
        ▼
合盖睡眠 → 唤醒时，SMC（系统管理控制器）重新检测电池/供电
        │
        ▼
SMC 误判供电异常 → 拉起 BD PROCHOT 硬件降频信号
        │
        ├──► CPU 被锁在最低频 800MHz（hard_plimit = 8）
        │         │
        │         ▼
        │    原本很轻的任务也变重 → 所有进程 CPU 占用都显得很高
        │    （XPC 进程等只是“受害者”，不是元凶）
        │
        └──► SMC 状态异常 → 风扇全速狂转（CPU 实际只有 45°C）
```

### 3.2 为什么重启 macOS 没用？

SMC 是独立于 CPU 的一块小芯片，**只要不断电，它的状态在 macOS 重启后会保留**。PROCHOT 信号被 SMC“卡住”后，重启并不会清掉它。

### 3.3 为什么切一次 Windows 就好了？

启动 Windows 时，Boot Camp 驱动会用它自己的方式重新初始化 EC/SMC 和电源管理，**正好把卡住的 PROCHOT 状态清掉了**。之后再重启回 macOS，SMC 已经是正常状态。

### 3.4 为什么一直插着电源也不行？

从日志看，每次出问题时都是 `Using AC (Charge:100%)`。触发条件是**睡眠→唤醒这个动作**让 SMC 重新检测电池，跟用不用电池供电无关。只要电池本身老化、上报的数据异常，插不插电都可能触发。

### 3.5 为什么和 OCLP 无关？

这是 SMC/硬件层面的行为。OCLP 本身不会导致这个问题，但 OCLP 恰好提供了一个绕过它的选项（见 4.3）。

---

## 4. 解决方案

按从简单到彻底排列。

### 4.1 临时方案：重置 SMC（每次复发时用）

比“切 Windows 再切回来”快得多。适用于 2015 款 MacBook Pro 这类**电池不可拆卸**的机型：

1. 关机；
2. 保持电源适配器插着；
3. 同时按住**左侧** `Shift + Control + Option` 和**电源键**，保持 10 秒；
4. 全部松开，再按电源键开机。

开机后验证：

```bash
sysctl machdep.xcpm.hard_plimit_max_100mhz_ratio
# 恢复正常应为 34；仍为 8 说明没成功，可再试一次
```

### 4.2 减少睡眠中的暗唤醒（已执行）

关闭 Power Nap、TCP Keep Alive、近距离唤醒，减少夜间反复唤醒，也就减少了触发的机会：

```bash
sudo pmset -a powernap 0 tcpkeepalive 0 proximitywake 0
```

执行时会提示：

```
Warning: This option disables TCP Keep Alive mechanism when sytem is sleeping.
This will result in some critical features like 'Find My Mac' not to function properly.
```

意思是：电脑睡眠时，“查找我的 Mac”可能定位不到，其他功能不受影响。

要恢复默认值：

```bash
sudo pmset -a powernap 1 tcpkeepalive 1 proximitywake 1
```

### 4.3 彻底方案：启用 OCLP 的 “Disable Firmware Throttling”（已执行 ✅）

OCLP 已经内置了这个功能，**不需要手动改 config.plist**。

#### 原理

勾选后，OCLP 构建 OpenCore 时会注入两个 kext（源码在 `opencore_legacy_patcher/efi_builder/firmware.py`）：

- **`SimpleMSR.kext`**（[arter97/SimpleMSR](https://github.com/arter97/SimpleMSR)）：开机和唤醒时清除 CPU 的 `MSR_POWER_CTL` 寄存器中的 **BD PROCHOT** 位，让 CPU **忽略外部（主板/SMC）发来的降频信号**。
- **`ASPP-Override.kext`**：调整电源管理插件的匹配，配合上面的修改。

对应源码：

```python
if self.constants.disable_fw_throttle is True and smbios_data.smbios_dictionary[self.model]["CPU Generation"] >= cpu_data.CPUGen.nehalem.value:
    logging.info("- Disabling Firmware Throttling")
    # Nehalem and newer systems force firmware throttling via MSR_POWER_CTL
    support.BuildSupport(self.model, self.constants, self.config).enable_kext("SimpleMSR.kext", ...)
```

这个选项在 OCLP 设置里的说明是：“禁用因缺失硬件（例如缺失显示器、电池等）导致的固件降频”。电池严重老化正好属于这种情况。

#### 操作步骤

1. 打开 **OpenCore-Patcher.app**（在“应用程序”里）；
2. 点 **Settings**，进入 **Advanced** 标签页，在 **Miscellaneous** 下勾选 **Disable Firmware Throttling**；
3. 返回主界面，点 **Build and Install OpenCore**；
4. 构建完成后点 **Install to disk**，选择内置硬盘（带 EFI 分区的那块磁盘），输入管理员密码；
5. 重启，在 OpenCore 启动菜单里正常选 macOS 进入。

#### 安全性说明

- SimpleMSR 只屏蔽**外部**的 PROCHOT 信号。**CPU 自身的过热保护（温度到 Tjmax 约 100°C 时自动降频）仍然有效**，不会烧坏 CPU。
- 这台机器实际 CPU 温度只有 45°C 左右，所以风险很低。
- **前提是电池没有鼓包**。已检查：触控板正常、底壳平整、没有鼓包。如果以后发现鼓包，必须立刻换电池，这个补丁掩盖不了鼓包的风险。

#### 如何撤销

在 OCLP 设置里取消勾选 **Disable Firmware Throttling**，再执行一次 **Build and Install OpenCore**，然后重启。

如果万一无法进入 macOS：开机时按住 **Option** 键，进入 Windows 或 macOS 安装盘，再重新构建 OpenCore。

### 4.4 长期方案：更换电池 + 限制充电

- **换电池**：电池容量只剩 32%，是根本原因。换新电池后，这种误降频通常就不会再出现。
- **限制充电上限**：在换电池之前，可以安装免费工具 **AlDente**，把充电上限设为 80%，减缓电池继续衰减、降低鼓包风险。
- **定期检查有没有鼓包**：触控板变硬或按不下去、底壳鼓起放在桌上会晃、合盖时屏幕缝隙不均匀，都是鼓包的迹象。

---

## 5. 修复结果验证

启用 Disable Firmware Throttling 并重启后：

```bash
❯ sysctl machdep.xcpm.hard_plimit_max_100mhz_ratio
machdep.xcpm.hard_plimit_max_100mhz_ratio: 34

❯ kextstat | grep -i simplemsr
   60    0 0xffffff8004096000 0x9000     0x9000     com.arter97.SimpleMSR (1) 6D9F78A6-6865-342F-8C87-A58A52B90B52 <6 3>
```

| 指标 | 修复前 | 修复后 |
|---|---|---|
| CPU 硬频率上限 | 8（800MHz） | **34（3.4GHz，满速睿频）** |
| CPU_Speed_Limit | 23% | **无限速记录** |
| 系统负载（load average） | 10 ~ 13 | **约 2.4** |
| SimpleMSR | 未加载 | **已加载** |

**最终验证方法**：合盖几分钟再打开，然后运行：

```bash
sysctl machdep.xcpm.hard_plimit_max_100mhz_ratio
```

如果仍然是 34，风扇也安静，就说明问题已经彻底解决，以后不用再切 Windows 或重置 SMC。

---

## 6. 常用诊断命令速查

### 6.1 CPU 限速 / 降频

| 命令 | 作用 | 正常值 / 异常值 |
|---|---|---|
| `sysctl machdep.xcpm.hard_plimit_max_100mhz_ratio` | CPU 硬频率上限（×100MHz） | 正常 34；异常 8 |
| `sysctl machdep.xcpm` | 查看全部 XCPM 电源管理参数 | — |
| `pmset -g therm` | 系统限速状态 | 正常时没有 `CPU_Speed_Limit` 记录，或为 100；异常时明显低于 100 |
| `sudo powermetrics -n 1 -i 1000 --samplers smc \| grep -iE "temp\|fan"` | CPU 温度、风扇转速 | 空闲时 40~60°C，风扇约 2000rpm |
| `sudo powermetrics -n 1 -i 1000 --samplers cpu_power` | CPU 实时频率和功耗 | — |
| `sysctl -n machdep.cpu.brand_string` | CPU 型号 | — |

### 6.2 进程与负载

| 命令 | 作用 |
|---|---|
| `uptime` | 开机时长和 1/5/15 分钟平均负载 |
| `ps -Ao pid,pcpu,pmem,etime,comm -r \| head -15` | 按 CPU 占用排序，列出前 15 个进程 |
| `top -o cpu -n 15` | 实时查看 CPU 占用最高的进程 |

### 6.3 电池

| 命令 | 作用 |
|---|---|
| `system_profiler SPPowerDataType` | 电池状态、循环次数、电源适配器信息 |
| `ioreg -rn AppleSmartBattery` | 电池原始数据（容量、温度、电压、故障状态） |
| `pmset -g batt` | 当前电量和供电来源 |

### 6.4 睡眠 / 唤醒

| 命令 | 作用 |
|---|---|
| `pmset -g` | 当前电源设置 |
| `pmset -g log \| grep -E "Sleep  \|Wake  \|DarkWake  "` | 睡眠/唤醒历史及唤醒原因 |
| `pmset -g assertions` | 哪些进程正在阻止睡眠 |
| `sudo pmset -a powernap 0 tcpkeepalive 0 proximitywake 0` | 关闭后台暗唤醒 |

### 6.5 OpenCore / OCLP / 内核扩展

| 命令 | 作用 |
|---|---|
| `kextstat \| grep -i simplemsr` | 确认 SimpleMSR 已加载 |
| `kmutil showloaded \| grep -v com.apple` | 列出所有非 Apple 的已加载 kext |
| `nvram -p \| grep -E "boot-args\|csr"` | 查看启动参数和 SIP 配置 |
| `nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version` | 查看 OpenCore 版本 |
| `csrutil status` | 查看 SIP 状态 |
| `sw_vers` | 查看 macOS 版本 |
| `sysctl -n hw.model` | 查看机型标识 |
| `diskutil list` | 查看磁盘和 EFI 分区 |
| `sudo diskutil mount disk0s1` | 挂载 EFI 分区（分区号以 `diskutil list` 的结果为准） |

---

## 附录 A：老 Mac 用 OCLP 升级到 macOS 15 的方法

### A.1 什么是 OCLP

[OpenCore Legacy Patcher](https://github.com/dortania/OpenCore-Legacy-Patcher) 是 Dortania 团队基于 OpenCore 引导器开发的工具。它能让 Apple 官方已经停止支持的老款 Mac 安装和运行新版 macOS。

主要做两件事：

1. **构建 OpenCore 引导**：启动时伪装机型、注入 kext、打补丁，让新版 macOS 能在老机器上启动；
2. **根卷补丁（Root Patch）**：macOS 装好后，把老显卡、Wi-Fi、蓝牙等已被新系统移除的驱动补回系统卷。

`MacBookPro11,4` 官方最高只支持到 **macOS 12 Monterey**。借助 OCLP 可以升到 macOS 15 Sequoia。

### A.2 准备工作

- **完整备份**：用 Time Machine 备份所有数据。
- **一个 16GB 以上的 U 盘**（用来做安装盘）。
- 查看 [OCLP 支持的机型列表](https://dortania.github.io/OpenCore-Legacy-Patcher/MODELS.html)，确认自己的机型能装哪个版本。
- 如果是双系统，确认 Windows 分区不受影响（OCLP 只修改 EFI 分区里的 `EFI/OC` 等文件，不会动 Windows 分区）。

### A.3 安装步骤

1. **下载 OCLP**：从 [GitHub Releases](https://github.com/dortania/OpenCore-Legacy-Patcher/releases) 下载最新版 `OpenCore-Patcher.pkg`，安装后打开 OpenCore-Patcher.app。
2. **制作 macOS 安装盘**：
   - 点 **Create macOS Installer**，选择 **Download macOS Installer**，下载 macOS 15 Sequoia；
   - 下载完后选择写入 U 盘（U 盘会被抹掉）。
3. **把 OpenCore 装到 U 盘**：
   - 回到主界面，点 **Build and Install OpenCore**；
   - 构建完成后，选择安装到 **U 盘**。
4. **从 U 盘启动**：
   - 重启，按住 **Option** 键；
   - 先选带 OpenCore 图标的 **EFI Boot**，再在 OpenCore 菜单里选 **Install macOS Sequoia**。
5. **安装 macOS**：
   - 正常安装，期间会自动重启几次。每次重启都要按住 Option，从 U 盘的 EFI Boot 进入 OpenCore，再选安装中的那个磁盘。
   - 如果是在原系统上直接升级，选原来的系统盘即可，数据会保留。
6. **把 OpenCore 装到内置硬盘**：
   - 进入新系统后打开 OCLP，点 **Build and Install OpenCore**，这次安装到**内置硬盘**；
   - 这样以后就不再需要 U 盘了。
7. **打根卷补丁**：
   - 点 **Post-Install Root Patch**，然后点 **Start Root Patching**；
   - 完成后重启。这一步会补回显卡加速、Wi-Fi、蓝牙等驱动。
8. **（可选）设置默认启动项**：在 OpenCore 启动菜单里选中 macOS，按 `Ctrl + Enter` 设为默认。

### A.4 升级后的注意事项

- **macOS 小版本更新**（如 15.7 → 15.8）：更新后 OCLP 通常会自动弹窗提示重新打根卷补丁。如果没弹，就手动运行一次 **Post-Install Root Patch**。
- **升级 OCLP 本身**：升级后重新执行一次 **Build and Install OpenCore**。**记得检查设置里的 Disable Firmware Throttling 等自定义选项是否还勾着。**
- **SIP 部分关闭是正常的**：OCLP 需要降低 SIP（本机 `csr-active-config` 为 `03080000`），才能加载补丁。不要手动把 SIP 全部打开，否则根卷补丁会失效。
- **启动参数**：本机的 `boot-args` 为 `keepsyms=1 debug=0x100 -lilubetaall ipc_control_port_options=0 -nokcmismatchpanic`，都是 OCLP 自动设置的，不要随意改动。
- **双系统**：开机按住 Option 选 Windows，或在 OpenCore 菜单里选 Windows，都可以进入 Windows。

### A.5 风险提示

- 老机器在新系统上的性能会有所下降，部分功能（如某些动态壁纸、Apple Intelligence 等）不可用或体验差。
- 有些 macOS 大版本更新可能暂时不被 OCLP 支持。**升级大版本前先看 OCLP 的 GitHub Release 说明**。
- 通过 OCLP 运行的系统属于非官方支持，出现问题需要自己排查，Apple 不提供支持。

---

## 附录 B：动态壁纸导致 CPU 高占用

### 现象

macOS 15 自带的**动态壁纸 / 风景（Aerial）壁纸**会让 CPU 和风扇持续高负载。

### 原因

- 动态/Aerial 壁纸本质上是持续播放的高分辨率视频，由 `WallpaperAgent`、`WallpaperVideoExtension`、`idleassetsd` 等进程负责渲染和下载素材。
- 2015 款 MBP 的 Haswell 核显（Iris Pro 5200）以及独显，在新系统里是靠 OCLP 补丁驱动的，**对新版视频解码和 Metal 渲染管线的支持有限**。很多工作会退回到 CPU 上做，导致 CPU 一直高负载。

### 解决

- 在 **系统设置 → 墙纸** 里改用**静态图片**壁纸（已执行，有效）；
- 屏幕保护程序也不要用 Aerial 风景类，改用简单的屏保或者直接关闭。

排查命令：

```bash
ps -Ao pid,pcpu,comm | grep -iE 'wallpaper|idleassets|aerial' | grep -v grep
```

---

## 附录 C：常见问题 FAQ

**Q1：活动监视器里某个 XPC 进程占用很高，要不要把它结束掉？**
A：不用。CPU 被锁在 800MHz 时，所有进程都会显得很“重”，它们只是受害者。先用 `sysctl machdep.xcpm.hard_plimit_max_100mhz_ratio` 看是不是 8。

**Q2：一直插着电源用，能不能避免这个问题？**
A：不能。日志显示出问题时都插着电源。触发条件是睡眠唤醒时 SMC 重新检测老化电池，跟供电来源无关。

**Q3：SimpleMSR 会不会让 CPU 过热烧掉？**
A：不会。它只屏蔽外部的 BD PROCHOT 信号，CPU 内部的温度保护（Tjmax 约 100°C 自动降频）仍然有效。不过要定期用 `powermetrics` 看看温度，并确认电池没有鼓包。

**Q4：换了新电池以后，还要保留 Disable Firmware Throttling 吗？**
A：可以取消。换好电池后，在 OCLP 设置里取消勾选并重新构建 OpenCore，让系统恢复原生的电源保护逻辑。

**Q5：为什么切 Windows 能修好，而 SMC 重置也能修好？**
A：两者本质相同，都是把 SMC/EC 里卡住的降频状态清掉。SMC 重置更直接、更快。

**Q6：以后升级 OCLP 或 macOS，这个修复还在吗？**
A：
- macOS 小版本更新：SimpleMSR 在 EFI 分区里，**不受影响**；
- OCLP 升级后重新构建 OpenCore：**要确认 Disable Firmware Throttling 仍然勾选**，否则 SimpleMSR 不会被打包进去。

---

## 总结

| 项目 | 内容 |
|---|---|
| 症状 | 合盖唤醒后 CPU 占用高、风扇狂转；重启无效，切 Windows 有效 |
| 真实状态 | CPU 被硬件锁在 800MHz，实际温度只有 45°C |
| 根本原因 | 第三方电池老化（容量 32%）→ 唤醒时 SMC 误拉 BD PROCHOT 降频信号 |
| 临时办法 | 重置 SMC（左 Shift + Control + Option + 电源键，按 10 秒） |
| 已采取的措施 | ① 关闭 Power Nap / TCP Keep Alive / 近距离唤醒；② 在 OCLP 中启用 Disable Firmware Throttling（加载 SimpleMSR） |
| 修复结果 | 频率上限恢复为 3.4GHz，负载从 10+ 降到约 2 |
| 后续建议 | 装 AlDente 把充电上限限制在 80%；有时间就换电池；升级 OCLP 后检查设置 |
