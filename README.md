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
10. [附录 D：OCLP 让老 Mac 运行新系统的原理与启动机制](#附录-doclp-让老-mac-运行新系统的原理与启动机制)
11. [附录 E：macOS 内核（XNU）原理、启动过程及与 Linux 的对比](#附录-emacos-内核xnu原理启动过程及与-linux-的对比)

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

## 附录 D：OCLP 让老 Mac 运行新系统的原理与启动机制

### D.1 一句话概括

**OCLP 不改固件，也不改硬件。** 它做两件事：

1. **启动时**：用 OpenCore 引导器在**内存里**“骗过”和“修补”macOS。它会绕过机型检查、注入驱动、修补内核。这部分全都放在 EFI 分区里。
2. **装好系统后**：用根卷补丁（Root Patch）把 Apple 已经删掉的老硬件驱动**补回系统卷**。

这两部分都可以撤销。删掉 EFI 分区里的 OpenCore，并还原系统快照，Mac 就回到原厂状态。

### D.2 Apple 是怎么“拦住”老 Mac 的？

要理解 OCLP，先要知道 Apple 设了哪几道关卡：

| 关卡 | Apple 的做法 | 后果 |
|---|---|---|
| ① 机型白名单 | 安装器和 `boot.efi` 会检查主板 ID（board-id）和机型标识，不在支持列表里就拒绝安装或启动 | 安装器提示“此 Mac 不支持”，或者启动直接失败 |
| ② 软件更新过滤 | 系统更新服务器按机型下发更新 | 在“系统设置”里看不到新系统 |
| ③ 驱动被删除 | 新系统删掉了老显卡（非 Metal 或旧 Metal）、老 Wi-Fi/蓝牙芯片、老摄像头等的驱动 | 就算能启动，也没有显卡加速、没有 Wi-Fi |
| ④ 系统卷签名保护 | 从 Big Sur 开始，系统卷是只读、带加密签名的快照（SSV，签名系统卷）。改了任何文件，签名校验就会失败 | 无法直接往系统里补驱动 |
| ⑤ 安全机制 | SIP（系统完整性保护）、AMFI（Apple 移动文件完整性，负责代码签名强制）、库验证 | 未经 Apple 签名的驱动和补丁无法加载 |
| ⑥ CPU 指令集 | 新系统的部分组件要求 AVX2 等新指令 | 太老的 CPU 运行时会崩溃（Haswell 支持 AVX2，这台机器不受影响） |

OCLP 就是逐一对付这些关卡的工具集合。

### D.3 启动链：从按下电源到进入桌面

```
① 按下电源键
    │
    ▼
② Mac 固件（Apple UEFI）上电自检
    │  固件去 EFI 分区找启动程序：/EFI/BOOT/BOOTx64.efi
    │  （这是 OpenCore，不是 Apple 原生的启动程序）
    ▼
③ OpenCore.efi 启动
    │  ├─ 读取 /EFI/OC/config.plist（OCLP 根据你的机型自动生成）
    │  ├─ 加载 UEFI 驱动（OpenRuntime.efi 等）
    │  ├─ 修补 ACPI 表（例如 XHC1→SHC1 等重命名）
    │  ├─ 写入 NVRAM：boot-args、csr-active-config（放宽 SIP）等
    │  └─ 设置 SMBIOS（机型信息），必要时伪装机型
    ▼
④ OpenCore 启动菜单（OpenCanopy 图形界面）
    │  选择 macOS / Windows / 恢复模式
    ▼
⑤ OpenCore 加载 Apple 原版 boot.efi，并在内存里给它打补丁
    │  └─ “Skip Board ID check”：跳过 boot.efi 的机型白名单检查
    ▼
⑥ boot.efi 从 Preboot 卷加载内核（XNU）和内核集合（Boot Kernel Collection）
    │  OpenCore 在这一步拦截文件读取：
    │  ├─ Kernel → Add：把第三方 kext 注入内核集合（Lilu、SimpleMSR 等）
    │  ├─ Kernel → Patch：在内存里修改内核或 Apple kext 的二进制代码
    │  └─ Kernel → Block：阻止某些不兼容的 Apple kext 加载
    ▼
⑦ XNU 内核启动
    │  Lilu 及其插件（RestrictEvents、FeatureUnlock、CPUFriend 等）
    │  在运行时继续修补内核和系统进程
    ▼
⑧ 挂载系统卷快照
    │  已打过根卷补丁的快照（补回了老显卡、Wi-Fi 等驱动）
    ▼
⑨ 登录界面 → 桌面
```

**要点：**

- **所有启动期补丁都只在内存里生效**，硬盘上的 Apple 文件（boot.efi、内核）并没有被修改。
- OpenCore 放在 EFI 分区的 `/EFI/OC/` 目录下。用 `sudo diskutil mount disk0s1` 挂载后就能看到。
- 开机按住 **Option** 会进入 **Apple 原生的启动菜单**。在这里选 “EFI Boot” 才会走 OpenCore；直接选 Windows 会绕过 OpenCore。
- OCLP 的 **Build and Install OpenCore** 做的事情，就是根据你的机型生成 `config.plist`，挑出需要的 kext 和驱动，然后一起拷进 EFI 分区。

### D.4 第一层：OpenCore 启动期补丁（EFI 分区）

OCLP 源码的 `opencore_legacy_patcher/efi_builder/` 目录，负责按机型生成 OpenCore 配置：

| 源码文件 | 负责内容 |
|---|---|
| `build.py` | 总流程：复制基础配置，调用下面各模块，保存 config.plist |
| `smbios.py` | 机型信息：跳过 Board ID 检查，或者伪装成受支持的机型 |
| `firmware.py` | CPU 与固件：电源管理、**SimpleMSR（本次修复用的）**、CPU 指令集兼容 |
| `graphics_audio.py` | 显卡和声卡的启动期设置 |
| `networking/` | Wi-Fi 和网卡的 kext 注入 |
| `bluetooth.py` | 蓝牙补丁 |
| `storage.py` | 硬盘控制器（SATA、NVMe、RAID） |
| `security.py` | SIP 放宽、AMFI 相关补丁、安全启动模型 |
| `misc.py` | 其他：USB 映射、键盘和触控板、RestrictEvents、FeatureUnlock 等 |

#### 1) 绕过机型检查（对付关卡 ①②）

OCLP 基础配置（`payloads/Config/config.plist`）里有这些关键补丁：

- **`Skip Board ID check`**：Booter 补丁，在内存里修改 `boot.efi`，跳过主板 ID 白名单检查。
  - 对应 `smbios.py` 中的代码：`"- Enabling Board ID exemption patch"`（注释写明：credit to Parrotgeek1 for boot.efi and hv_vmm_present patch sets）
- **`Reroute HW_BID to OC_BID`**：让系统读取 OpenCore 提供的 board-id。
- **`Reroute kern.hv_vmm_present`**：让 macOS 以为自己**运行在虚拟机里**。
  - Apple 对虚拟机不做机型限制，所以系统更新服务会正常推送新系统和更新。这就是用了 OCLP 后，能直接在“系统设置 → 软件更新”里收到更新的原因。
  - 也可以改用 RestrictEvents 的 `sbvmm` 参数，只对软件更新进程伪装成虚拟机（见 `misc.py`）。
- **`-no_compat_check`**：启动参数，跳过内核的兼容性检查（手动伪装成当前机型时会加上）。
- **SMBIOS 伪装（可选）**：`smbios.py` 可以把机型伪装成受支持的型号（Minimal / Moderate / Advanced 三档）。新版 OCLP 在大多数机型上默认**不伪装**，只做 Board ID 豁免，以减少副作用。

#### 2) 注入驱动 kext（对付关卡 ③ 的一部分）

有些驱动只要在启动时塞进内核就能工作，不需要改系统卷：

| kext | 作用 |
|---|---|
| **Lilu** | 内核补丁框架，很多插件都依赖它 |
| **WhateverGreen** | 显卡相关的内核修补 |
| **RestrictEvents** | 阻止或修改某些系统进程，并提供 `sbvmm` 等功能 |
| **FeatureUnlock** | 解锁隔空播放到 Mac、随航、通用控制等被机型限制的功能 |
| **CryptexFixup** | 在不支持 AVX2 的 CPU 上安装兼容版本的 dyld 共享缓存 |
| **AMFIPass** | 让系统在 AMFI 放宽的情况下仍能正常运行 |
| **SimpleMSR** | 清除 BD PROCHOT 降频位（本次修复用的） |
| **ASPP-Override** | 调整 CPU 电源管理插件的匹配 |
| **IO80211FamilyLegacy / IOSkywalkFamily** | 老 Broadcom Wi-Fi 的驱动栈 |
| **USB Map** | USB 端口映射 |

#### 3) 内核和 kext 二进制补丁

`config.plist` 里的 Kernel → Patch 会在内存里直接修改 Apple 代码，例如：

- `Patch AppleSMC`：配合 SMC 伪装；
- `Disable Library Validation Enforcement`：放宽库验证；
- `Disable Root Hash validation`：不校验系统卷的哈希，**这是根卷补丁能生效的前提**；
- `Force FileVault on Broken Seal`：系统卷签名被破坏后，仍然允许使用 FileVault；
- `Allow AppleKeyStore Downgrade` 等：兼容旧版组件。

#### 4) 放宽安全策略（对付关卡 ⑤）

本机实测：

```bash
❯ nvram csr-active-config
csr-active-config	%03%08%00%00          # 即 0x803

❯ csrutil status
System Integrity Protection status: unknown (Custom Configuration).
	Kext Signing: disabled               ← 允许加载非 Apple 签名的 kext
	Filesystem Protections: disabled     ← 允许根卷补丁修改系统文件
	Debugging Restrictions: enabled
	NVRAM Protections: enabled
	...

❯ nvram boot-args
boot-args	keepsyms=1 debug=0x100 -lilubetaall ipc_control_port_options=0 -nokcmismatchpanic
```

| 启动参数 | 含义 |
|---|---|
| `keepsyms=1 debug=0x100` | 内核崩溃时保留符号、不自动重启，方便排查 |
| `-lilubetaall` | 允许 Lilu 及其插件在未经测试的新系统版本上运行 |
| `ipc_control_port_options=0` | 放宽 IPC 端口限制，避免部分补丁后的进程崩溃 |
| `-nokcmismatchpanic` | 内核集合与内核版本不匹配时不崩溃 |

SIP 只是**部分**关闭，调试限制、NVRAM 保护等仍然开着。这是 OCLP 为了兼顾安全和功能做的最小放宽。

### D.5 第二层：根卷补丁（Root Patch，系统卷）

#### 为什么需要它？

有些驱动**不只是一个 kext**，还包括用户空间的框架、着色器编译器、Metal 库等，例如显卡驱动。它们必须实际放进 `/System/Library/` 才能工作，没办法只靠启动时注入。

但 macOS 的系统卷是**只读、带签名的 APFS 快照**，所以 OCLP 的流程是这样的（见 `sys_patch/sys_patch.py` 顶部注释）：

```
1. 挂载真正的系统卷（不是只读快照），挂载到 /System/Volumes/Update/mnt1
2. 把老驱动、框架复制或合并进去（Overwrite / Merge System Volume）
3. 重建内核缓存：
   sudo kmutil install --volume-root /System/Volumes/Update/mnt1/ --update-all
4. 必要时重建 dyld 共享缓存、更新 Preboot 卷里的内核缓存
5. 创建新的 APFS 快照，并设为启动快照：
   sudo bless --folder /System/Volumes/Update/mnt1/System/Library/CoreServices --bootefi --create-snapshot
```

回滚也很简单，把启动快照切回 Apple 原版密封的那个即可：

```bash
sudo bless --mount /System/Volumes/Update/mnt1 --bootefi --last-sealed-snapshot
```

OCLP 界面里的 **Revert Root Patches** 做的就是这件事。

#### 根卷补丁按硬件分类

源码目录 `sys_patch/patchsets/hardware/`：

- `graphics/`：`intel_haswell.py`（本机用这个）、`intel_ivy_bridge.py`、`nvidia_kepler.py`、`amd_polaris.py` 等，每一代显卡一个文件；
- `networking/`：`modern_wireless.py`、`legacy_wireless.py`；
- `misc/`：`pcie_webcam.py`（摄像头）、`display_backlight.py`、`keyboard_backlight.py`、`usb11.py`、`t1_security.py` 等。

`sys_patch/patchsets/detect.py` 会先检测硬件，决定要打哪些补丁。

#### 本机实际打过的补丁

补丁记录保存在 `/System/Library/CoreServices/OpenCore-Legacy-Patcher.plist`，查看方法：

```bash
plutil -p /System/Library/CoreServices/OpenCore-Legacy-Patcher.plist | grep -E '^\s{2}"'
```

本机结果：

| 补丁集 | 作用 |
|---|---|
| **Intel Haswell** | Iris Pro 5200 核显驱动 |
| **Metal 3802 Common / Extended / .metallibs** | 旧版 Metal 3802 图形栈。Haswell 不支持新版 Metal，需要换回旧版 Metal 框架和编译器 |
| **Monterey GVA** | 从 macOS 12 移植过来的视频硬件解码框架 |
| **Monterey OpenCL** | 从 macOS 12 移植过来的 OpenCL |
| **Modern Wireless Common** | Wi-Fi（BCM94360 系列）支持 |
| **PCIe FaceTime Camera** | PCIe 接口的 FaceTime 摄像头 |

补丁信息：OCLP v2.5.1，PatcherSupportPkg v1.9.7，打补丁时间 2026-09-20，系统 24.6 (24H23)，Metal 库来自 `MetallibSupportPkg/15.7.9-24G830`。

> 这也解释了附录 B 的动态壁纸问题：显卡用的是旧版 Metal 3802，视频解码框架是从 Monterey 移植的，**并不是为 macOS 15 的新壁纸渲染管线设计的**，所以动态壁纸的渲染和解码效率很差，最终落到 CPU 上。

#### 为什么 macOS 每次更新后都要重打补丁？

macOS 更新会**用 Apple 的新快照整个替换系统卷**，之前补进去的驱动就没了。所以 OCLP 会装一个后台服务（`sys_patch/auto_patcher/`），检测到系统更新后弹窗提示重新打根卷补丁。

**如果更新后显卡卡顿、Wi-Fi 消失，基本就是根卷补丁没了，重打一次即可。**

### D.6 两层的分工与对比

| 对比项 | OpenCore 启动期补丁 | 根卷补丁 |
|---|---|---|
| 存放位置 | EFI 分区 `/EFI/OC/` | 系统卷 `/System/Library/` |
| 生效方式 | 每次开机时在内存里修补 | 写入磁盘，并创建新的系统快照 |
| 解决什么 | 机型检查、内核补丁、kext 注入、SIP 放宽、CPU 电源管理 | 显卡加速、Metal、视频解码、Wi-Fi、摄像头等需要完整框架的驱动 |
| macOS 更新后 | **不受影响** | **会被冲掉，需要重打** |
| OCLP 升级后 | 需要重新 Build and Install OpenCore | 一般会提示重打 |
| 撤销方法 | 删除或还原 EFI 分区里的 OpenCore | Revert Root Patches（切回原版快照） |
| 本次 SimpleMSR 修复 | ✅ 在这一层 | — |

### D.7 为什么这个方案是安全、可逆的？

- **不刷固件**：Mac 的 BootROM 或固件没有被修改，Apple 原生启动菜单始终能用。
- **启动期补丁都在内存里**：Apple 的 `boot.efi` 和内核文件原封不动。
- **系统卷快照可回滚**：Apple 原版的密封快照一直保留（Monterey 起更可靠）。
- **SIP 只部分放宽**：调试限制、NVRAM 保护等仍然开着。

代价是：

- 放宽了 SIP 和 AMFI，整体安全性比原厂低；
- 系统卷签名被破坏，部分依赖系统完整性的功能可能受限；
- 依赖 OCLP 社区跟进新系统，大版本更新前要先等 OCLP 适配。

### D.8 相关查看命令

```bash
# OpenCore / OCLP 状态
nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version   # OpenCore 版本
nvram boot-args                                              # 启动参数
nvram csr-active-config                                      # SIP 配置值
csrutil status                                               # SIP 各项状态
kmutil showloaded | grep -v com.apple                        # 已加载的第三方 kext

# 根卷补丁记录
plutil -p /System/Library/CoreServices/OpenCore-Legacy-Patcher.plist

# 系统快照
diskutil apfs listSnapshots /                                # 当前系统卷快照

# 查看 EFI 分区里的 OpenCore
diskutil list                                                # 找到 EFI 分区（一般是 disk0s1）
sudo diskutil mount disk0s1
ls /Volumes/EFI/EFI/OC/Kexts                                 # 查看注入的 kext（应能看到 SimpleMSR.kext）
sudo diskutil unmount disk0s1                                # 看完记得卸载

# OCLP 保存的用户设置
defaults read /Users/Shared/.com.dortania.opencore-legacy-patcher.plist
# 本机可以看到 "GUI:disable_fw_throttle" = 1，即本次开启的降频屏蔽
```

---

## 附录 E：macOS 内核（XNU）原理、启动过程及与 Linux 的对比

### E.1 macOS 的整体分层

macOS 的底层叫 **Darwin**，是 Apple 开源的部分：**XNU 内核 + 一套 BSD 风格的用户态基础工具**。Darwin 之上是 Apple 闭源的框架和图形界面。

```
┌──────────────────────────────────────────────────────────────┐
│  应用程序：Finder、Safari、iTerm、Claude Code …               │
├──────────────────────────────────────────────────────────────┤
│  应用框架：AppKit / SwiftUI / Foundation                      │  ← 闭源
│  图形与媒体：Metal、Core Animation、AVFoundation、WindowServer │
│  核心服务：Core Foundation、XPC、Security、Spotlight …         │
├──────────────────────────────────────────────────────────────┤
│  Darwin 用户态：launchd(PID 1)、dyld(动态链接器)、             │  ← 大部分开源
│                 libSystem(libc 等)、zsh、BSD 命令行工具        │
├──────────────────────────────────────────────────────────────┤
│  XNU 内核                                                     │
│   ┌─────────────┬───────────────────┬─────────────────────┐  │
│   │   Mach      │     BSD 层        │     IOKit           │  │  ← 开源
│   │ 任务/线程    │ 进程/POSIX/信号   │ C++ 面向对象驱动框架 │  │
│   │ 虚拟内存     │ VFS/APFS/网络栈   │ 驱动匹配/电源管理    │  │
│   │ IPC(端口)    │ 用户/权限/沙盒    │ IORegistry 设备树    │  │
│   │ 调度器       │ 系统调用          │                     │  │
│   ├─────────────┴───────────────────┴─────────────────────┤  │
│   │  libkern（内核 C++ 运行时）  Platform Expert（平台抽象） │  │
│   └─────────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────┤
│  硬件：Intel CPU / SMC / 显卡 / 存储 / …                       │
└──────────────────────────────────────────────────────────────┘
```

本机内核版本：

```bash
❯ uname -a
Darwin ... 24.6.0 Darwin Kernel Version 24.6.0: Sun Aug 23 20:30:56 PDT 2026;
root:xnu-11417.140.69.712.69~1/RELEASE_X86_64 x86_64
```

- `Darwin 24.6.0` 对应 macOS 15.6 之后的 15.x 系列（Darwin 大版本号 = macOS 大版本号 + 9）；
- `xnu-11417...` 是 XNU 的源码版本号；
- `RELEASE_X86_64` 表示这是 Intel 版的正式发布内核。

### E.2 XNU 是什么？

**XNU = “X is Not Unix”**。它来自 NeXT 公司的 NeXTSTEP 系统（乔布斯离开苹果后创办的公司，1997 年被苹果收购）。它是一个**混合内核**，由三大块组成：

#### 1) Mach：内核最底层

来源于卡内基梅隆大学的 Mach 微内核。负责最基础的几件事：

- **任务（task）和线程（thread）**：task 是资源容器，相当于进程的“骨架”；
- **虚拟内存**：页表、内存对象、写时复制；
- **调度器**：决定哪个线程在哪个 CPU 核上跑，支持 QoS 服务质量等级（用户交互 > 用户发起 > 实用工具 > 后台）；
- **IPC（进程间通信）**：基于**Mach 端口（port）**的消息传递。这是 macOS 最核心的通信机制。

> 🔗 **和本次问题的联系**：你在活动监视器里看到的各种 `xxx.xpc` 进程，就是基于 Mach 端口的 **XPC 服务**。macOS 把大量功能拆成一个个独立的小服务进程，通过 XPC 通信。这就是为什么 `ps` 能列出几百个进程。CPU 被锁在 800MHz 时，这些服务全都会变慢，看起来就像某个 XPC 进程在“狂转”。

#### 2) BSD 层：提供 Unix 的“外表”

主要来自 FreeBSD，建在 Mach 之上：

- **进程模型**：BSD 的 proc 结构包装 Mach 的 task，提供 PID、fork/exec、信号、用户/组权限；
- **POSIX 系统调用**：open、read、write、socket 等；
- **VFS 文件系统层**：APFS、HFS+、exFAT、NFS 等；
- **网络协议栈**：TCP/IP、套接字、防火墙；
- **安全框架**：来自 TrustedBSD 的 MAC 框架。Sandbox（沙盒）、AMFI 等都是它的策略模块。

所以 macOS 是**通过了 UNIX 03 认证的正宗 Unix**，而 Linux 只是“类 Unix”。

#### 3) IOKit：驱动框架

- 用 **C++ 的受限子集**（没有异常、没有多重继承、没有 RTTI）写驱动；
- 驱动是**面向对象**的，一个驱动继承 `IOService` 等基类；
- **驱动匹配（matching）**：内核发现一个硬件后，会按 Info.plist 里的条件和 `IOProbeScore` 分数找出最合适的驱动。
  - 前面讲到的 `ASPP-Override.kext`，就是通过提高 `IOProbeScore` 抢到 CPU 电源管理驱动的匹配权；
- **IORegistry**：内核里的设备对象树。本次排查用的 `ioreg -rn AppleSmartBattery` 就是在读它；
- 驱动的打包形式叫 **kext**（Kernel Extension，内核扩展），例如 `SimpleMSR.kext`、`Lilu.kext`。

#### 4) libkern 和 Platform Expert

- **libkern**：内核里的 C++ 运行时、原子操作、OSObject 基础类等；
- **Platform Expert**：把具体硬件平台（Intel Mac、Apple Silicon、虚拟机）的差异抽象掉。

#### 为什么叫“混合内核”？

纯微内核（如 Mach 3.0 本身）把文件系统、驱动都放在用户态，通过 IPC 通信，很安全但很慢。XNU 把 Mach、BSD、IOKit **都放在同一个内核地址空间里**，互相之间直接函数调用，性能接近宏内核；同时又保留了 Mach 的 IPC 模型和设计。

### E.3 XNU 与 Linux 内核的对比

| 对比项 | macOS（XNU） | Linux |
|---|---|---|
| **内核类型** | 混合内核（Mach + BSD + IOKit，同一地址空间） | 宏内核（单体内核）+ 可加载模块 |
| **起源** | NeXTSTEP → Mach 3.0 + FreeBSD，1989 年起 | Linus Torvalds 1991 年从零编写 |
| **开源情况** | XNU 以 APSL 协议开源，但 macOS 整体大部分闭源 | 内核完全开源（GPLv2），发行版大都开源 |
| **Unix 认证** | ✅ UNIX 03 认证 | ❌ 类 Unix（未认证） |
| **驱动形式** | kext（C++ IOKit）；新方向是 **DriverKit 系统扩展**（驱动跑在用户态） | `.ko` 内核模块（C），`insmod` / `modprobe` 加载 |
| **驱动发现** | IOKit 匹配 + IORegistry | udev + sysfs + 设备树 / ACPI |
| **进程间通信** | Mach 消息 / 端口、XPC（主力），也支持管道、Unix 套接字 | 管道、Unix 套接字、D-Bus、共享内存；Android 用 Binder |
| **可执行文件格式** | **Mach-O**（支持多架构“通用二进制”） | **ELF** |
| **动态链接器** | `dyld`，外加 **dyld 共享缓存**（系统库预先链接好，打成一个大文件） | `ld-linux.so` |
| **C 标准库** | `libSystem`（包含 libc、libm、pthread 等），不允许静态链接 | glibc / musl，可以静态链接 |
| **系统调用** | **不公开稳定的 ABI**，必须通过 libSystem 调用；分 BSD 调用和 Mach trap 两类 | 系统调用 ABI **稳定公开**，可以直接 `syscall` |
| **PID 1（init）** | `launchd`：同时负责 init、cron、inetd、服务管理 | `systemd`（主流）/ SysVinit / OpenRC 等 |
| **服务配置** | `/System/Library/LaunchDaemons/*.plist` | `/etc/systemd/system/*.service` |
| **文件系统** | **APFS**：写时复制、快照、加密、系统卷密封 | ext4 / XFS / Btrfs（Btrfs 也有快照） |
| **系统盘保护** | 签名系统卷（SSV），根目录只读并带加密签名 | 一般可读写；少数发行版有不可变系统（如 Fedora Silverblue） |
| **安全机制** | SIP、AMFI（强制代码签名）、Sandbox、Gatekeeper、TCC（隐私授权） | SELinux / AppArmor、seccomp、namespaces、capabilities |
| **容器支持** | 内核没有 namespaces / cgroups，Docker 要跑在 Linux 虚拟机里 | 原生 namespaces + cgroups，容器的发源地 |
| **调度器** | Mach 调度器 + Clutch（按线程组分层调度）+ QoS 等级 | CFS → EEVDF（6.6 起） |
| **CPU 调频** | XCPM（`sysctl machdep.xcpm`），由内核和 SMC 协同 | cpufreq + intel_pstate / amd-pstate，调速器（governor）可选 |
| **查看内核参数** | `sysctl`、`ioreg`（**没有 /proc 和 /sys**） | `/proc`、`/sys`、`sysctl` |
| **内核日志** | 统一日志系统：`log show` / `log stream` | `dmesg` / `journalctl -k` |
| **列出驱动** | `kmutil showloaded`（旧：`kextstat`） | `lsmod` |
| **引导程序** | Intel：Apple EFI 固件 + `boot.efi`；Apple Silicon：iBoot | GRUB / systemd-boot / 直接 EFI stub |
| **早期启动环境** | **没有 initramfs**，内核直接挂载真正的根卷 | initramfs（常用 BusyBox 或 dracut / systemd） |
| **命令行工具** | BSD 版本（`sed`、`ps`、`date` 等参数和 GNU 不同） | GNU coreutils |

> 💡 **一个实际例子**：前面修改文档时，我用的是 `sed -i '' 's/.../.../' 文件`。macOS 自带的是 BSD 版 `sed`，`-i` 后面**必须**跟一个备份后缀（空字符串 `''` 表示不备份）。在 Linux 的 GNU sed 上，同样的写法会出错。这就是 BSD 工具和 GNU 工具的差异。

### E.4 Linux 是怎么启动的（作为对比）

```
① 固件：BIOS 或 UEFI
    ▼
② 引导程序：GRUB / systemd-boot
    │  读取配置，加载 vmlinuz（压缩内核）和 initramfs（初始内存盘）
    ▼
③ 内核启动：解压、初始化内存/CPU/中断，内置驱动初始化
    ▼
④ 运行 initramfs 里的 /init
    │  initramfs 是一个临时的迷你根文件系统，里面经常用 BusyBox
    │  （BusyBox 把 sh、ls、mount、modprobe 等几百个命令打包成一个小程序）
    │  任务：加载磁盘/RAID/LVM/加密驱动，找到并挂载真正的根分区
    ▼
⑤ switch_root：切换到真正的根文件系统
    ▼
⑥ 启动 /sbin/init（通常是 systemd），成为 PID 1
    ▼
⑦ systemd 按依赖关系启动各种服务（target / unit）
    ▼
⑧ 登录管理器（GDM / SDDM）或文本登录（getty）→ 桌面 / shell
```

**为什么 Linux 需要 initramfs + BusyBox？** 因为 Linux 要支持的硬件和存储组合（各种 RAID、LVM、LUKS 加密、网络根文件系统）太多，不可能把所有驱动都编进内核。所以先用一个临时的小系统，按需加载驱动，找到真正的根分区。BusyBox 体积小、功能全，非常适合做这个临时系统，也广泛用于路由器等嵌入式设备。

### E.5 macOS 是怎么启动的（Intel Mac，以本机为例）

```
① 按下电源 → CPU 从固件 ROM 开始执行
    │  Apple EFI 固件：硬件自检、初始化内存/显卡/存储控制器
    │  读取 NVRAM：启动盘（efi-boot-device）、boot-args、csr-active-config 等
    ▼
②【本机特有】OpenCore（EFI 分区 /EFI/BOOT/BOOTx64.efi）
    │  放宽 SIP、写启动参数、准备好 kext 注入和内核补丁（详见附录 D）
    │  原厂 Mac 没有这一步，固件会直接找 boot.efi
    ▼
③ boot.efi（Apple 的引导程序，相当于 Linux 的 GRUB）
    │  位于 Preboot 卷和 /System/Library/CoreServices/boot.efi
    │  ├─ 显示苹果 Logo 和进度条（按 Cmd+V 或加 -v 参数会改成滚动的文字日志）
    │  ├─ FileVault 开启时：显示解锁界面，解密数据卷
    │  ├─ 从 Preboot 卷加载 Boot Kernel Collection（内核 + 启动必需的 kext）
    │  └─ 把设备树、启动参数、内存布局等信息交给内核
    ▼
④ XNU 内核初始化
    │  ├─ Mach 层：虚拟内存、调度器、IPC、第一个线程
    │  ├─ IOKit：建立 IORegistry，开始驱动匹配
    │  │   （显卡、存储、USB、SMC、电池……一层层匹配上驱动）
    │  ├─ BSD 层：bsd_init()，初始化进程表、VFS、网络
    │  └─ 挂载根文件系统：直接挂载 APFS 系统卷的只读快照
    │     （不需要 initramfs：Mac 硬件型号少，存储驱动都在 Boot KC 里）
    ▼
⑤ 启动 /sbin/launchd，成为 PID 1（相当于 Linux 的 systemd）
    │  ├─ 挂载其余卷：Data、Preboot、VM、Update（firmlinks 把 System 和 Data 合并成一个目录树）
    │  ├─ 读取 /System/Library/LaunchDaemons/*.plist（本机有 412 个系统守护进程配置）
    │  └─ 按需启动：logd（日志）、configd（网络配置）、powerd（电源）、
    │     WindowServer（图形）、kernelmanagerd（kext 管理）…
    │     很多服务是“按需启动”的：有人通过 Mach 端口连接它时才启动
    ▼
⑥ WindowServer 启动图形界面 → loginwindow 显示登录界面
    ▼
⑦ 用户登录 → 用户级 launchd 读取 LaunchAgents（本机系统级有 435 个）
    │  启动 Dock、Finder、SystemUIServer、菜单栏、登录项 …
    ▼
⑧ 桌面就绪
```

#### 本机的启动相关文件和卷

```bash
❯ ps -p 1 -o pid,comm
  PID COMM
    1 /sbin/launchd                 ← PID 1

❯ ls -la /System/Library/KernelCollections/
BootKernelExtensions.kc     66 MB   ← 启动内核集合：内核 + 启动必需的 kext
SystemKernelExtensions.kc  373 MB   ← 系统内核集合：其余的 Apple kext，启动后按需加载

❯ mount | head -6
/dev/disk1s4s1 on / (apfs, sealed, local, read-only, journaled)   ← 系统卷快照（只读）
/dev/disk1s2 on /System/Volumes/Preboot (apfs, ...)                ← 引导文件、内核缓存
/dev/disk1s6 on /System/Volumes/VM (apfs, noexec, ...)             ← 交换文件、睡眠镜像
/dev/disk1s5 on /System/Volumes/Update (apfs, ...)                 ← 系统更新 / OCLP 打补丁时用
/dev/disk1s1 on /System/Volumes/Data (apfs, ..., root data)        ← 用户数据（可读写）
```

APFS 容器 `disk1` 里的各个卷：

| 卷 | 角色 | 作用 |
|---|---|---|
| `disk1s4`（mac） | System | 系统卷，只读；`disk1s4s1` 是它当前启动用的快照 |
| `disk1s1`（mac - Data） | Data | 用户数据、应用、`/Library`、`/Users` |
| `disk1s2` | Preboot | boot.efi、内核集合、FileVault 解锁界面资源 |
| `disk1s3` | Recovery | 恢复模式（一个迷你 macOS） |
| `disk1s6` | VM | 交换文件、休眠镜像（`/var/vm/sleepimage`） |
| `disk1s5` | Update | 系统更新时的临时工作区 |

另外还有 `disk0s1`（EFI 分区，本机放 OpenCore），以及 Windows 的 `BOOTCAMP` 分区（NTFS）。

#### 三种内核集合（Kernel Collection）

从 macOS 11 起，Apple 把内核和 kext 预先链接成“内核集合”：

| 内核集合 | 内容 | 类比 Linux |
|---|---|---|
| **Boot KC**（BootKernelExtensions.kc） | 内核本体 + 启动必需的 kext | vmlinuz + 内置驱动 |
| **System KC**（SystemKernelExtensions.kc） | 其余 Apple kext | `/lib/modules/` 下的模块 |
| **Auxiliary KC** | 第三方 kext（`/Library/Extensions`），需要在“隐私与安全性”里批准 | 第三方的 DKMS 模块 |

OCLP 打根卷补丁时运行 `kmutil install ... --update-all`，就是在**重新生成这些内核集合**。OpenCore 注入 kext，则是在启动时往 Boot KC 里“塞”东西。

### E.6 macOS 有没有 BusyBox？

**没有，也不需要。** 原因如下：

1. **没有 initramfs 阶段**：Mac 硬件型号有限，存储驱动都预先放进了 Boot KC，内核可以直接挂载真正的根卷，不需要临时小系统。
2. **命令行工具是完整的 BSD 工具集**：`/bin`、`/usr/bin` 下的 `ls`、`sed`、`ps` 等都是独立的程序，大多来自 FreeBSD，不是 BusyBox 那种“一个程序扮演所有命令”。

macOS 中**功能上接近“迷你系统”**的东西有这些：

| 环境 | 进入方法 | 说明 |
|---|---|---|
| **恢复模式（Recovery）** | 开机按 `Cmd + R`（OpenCore 菜单里也有恢复项） | 从 Recovery 卷启动一个精简版 macOS，里面有终端、磁盘工具、重装系统、`csrutil` 等。**这是 macOS 里最接近 Linux initramfs / 救援盘的东西** |
| **单用户模式** | 以前开机按 `Cmd + S` | 直接进入 root shell，类似 Linux 的 `init=/bin/sh`。从签名系统卷时代（macOS 11）开始，Intel Mac 上基本已不可用，Apple Silicon 没有 |
| **啰嗦模式（Verbose）** | 开机按 `Cmd + V`，或在 boot-args 里加 `-v` | 不显示苹果 Logo，改为滚动显示内核和启动日志，类似 Linux 启动时的文字输出。**排查启动问题很有用**：OCLP 用户可以在 OpenCore 设置里加 `-v` |
| **OpenShell.efi** | OpenCore 启动菜单里的 UEFI Shell | 固件层面的命令行，可以查看磁盘、执行 EFI 程序，类似 GRUB 的命令行 |
| **安全模式** | 开机按住 `Shift` | 只加载必需的 kext，禁用登录项、清理缓存，类似 Linux 的“恢复模式启动” |

> 如果真的想在 macOS 上用 GNU 工具，可以用 Homebrew 安装 `coreutils`、`gnu-sed` 等，命令名前会带 `g` 前缀（如 `gsed`、`gls`）。

### E.7 Apple Silicon Mac 的启动（补充）

本机是 Intel Mac。Apple Silicon（M1 及以后）的启动流程完全不同：

```
Boot ROM（芯片内固化的 SecureROM）
  → LLB / iBoot（Apple 自研引导程序，取代了 UEFI + boot.efi）
  → 验证签名后加载内核集合
  → XNU → launchd …
```

- 没有 UEFI，也没有 EFI 分区，**所以不能用 OpenCore，也不需要 OCLP**；
- 每个系统卷都有自己的“启动安全策略”（完全安全 / 降低安全性），加载第三方 kext 需要在恢复模式里手动降低安全级别；
- 从 `ls /System/Library/Kernels/` 能看到 `kernel.release.t8103`（M1）、`t6000`（M1 Pro/Max）等内核文件，这是同一个 macOS 安装包为不同芯片准备的内核，本机 Intel 用的是 `kernel`。

### E.8 回到本次问题：同一件事在两个系统里怎么做

以本次的 CPU 降频问题为例，对比一下两个系统的做法：

| 任务 | macOS | Linux |
|---|---|---|
| 查看 CPU 频率上限 | `sysctl machdep.xcpm.hard_plimit_max_100mhz_ratio` | `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq` |
| 查看是否被 PROCHOT 降频 | `pmset -g therm` | `cat /sys/devices/system/cpu/cpu0/thermal_throttle/*`，或 `turbostat` |
| 查看温度和风扇 | `sudo powermetrics --samplers smc` | `sensors`（lm-sensors） |
| 查看电池 | `ioreg -rn AppleSmartBattery` / `system_profiler SPPowerDataType` | `upower -i /org/freedesktop/UPower/devices/battery_BAT0` |
| 关闭 BD PROCHOT | 加载 **SimpleMSR.kext**（通过 OpenCore 注入） | `sudo modprobe msr` 后执行 `sudo wrmsr 0x1FC <清除第 0 位后的值>`（msr-tools） |
| 查看已加载的驱动 | `kmutil showloaded` | `lsmod` |
| 睡眠 / 唤醒日志 | `pmset -g log` | `journalctl -b \| grep -i suspend` |
| 电源设置 | `pmset` | systemd-logind 配置、TLP、powertop |

两个系统的底层原理一样：都是往 CPU 的 **MSR 0x1FC（MSR_POWER_CTL）寄存器**写值，清掉第 0 位（BD PROCHOT 使能位）。区别只在工具：Linux 可以直接用命令写寄存器，而 macOS 必须通过内核扩展（kext）来写。

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
