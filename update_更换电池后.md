
```
~/PyPro/OpenCore-Legacy-Patcher-Mac15Fix main
❯ ioreg -rn AppleSmartBattery | grep -E '"(Temperature|CycleCount|MaxCapacity|DesignCapacity|PermanentFailureStatus|ExternalConnected|IsCharging)"'

      "PermanentFailureStatus" = 0
      "MaxCapacity" = 8800
      "CycleCount" = 3
      "BatteryData" = {"StateOfCharge"=68,"PMUConfigured"=768,"CellVoltage"=(4096,4104,4100),"AdapterPower"=,"LifetimeData"={"UpdateTime"=1791551283},"SystemPower"=3727,"Serial"="C01514309YEF90MA4","DesignCapacity"=8600,"CycleCount"=3,"Voltage"=12289,"Qmax"=(6888,6921,7150)}
      "DesignCapacity" = 8600
      "Temperature" = 3045
      "IsCharging" = Yes
      "ExternalConnected" = Yes

~/PyPro/OpenCore-Legacy-Patcher-Mac15Fix main
❯  sudo powermetrics -n 1 -i 1000 --samplers smc | grep -iE "temp|fan"
Password:
Sorry, try again.
Password:
Fan: 6155 rpm
CPU die temperature: 52.30 C

~/PyPro/OpenCore-Legacy-Patcher-Mac15Fix main 8s

base ❯ brew install --cask macs-fan-control

base ❯  sudo pmset -a powernap 1 tcpkeepalive 1 proximitywake 1

~/PyPro/OpenCore-Legacy-Patcher-Mac15Fix main
base ❯  pmset -g
System-wide power settings:
Currently in use:
 womp                 1
 halfdim              1
 hibernatefile        /var/vm/sleepimage
 gpuswitch            2
 networkoversleep     0
 disksleep            10
 sleep                1 (sleep prevented by useractivityd, sharingd)
 hibernatemode        3
 ttyskeepawake        1
 displaysleep         0
 acwake               0
 lidwake              1

~/PyPro/OpenCore-Legacy-Patcher-Mac15Fix main
base ❯

```

------------

```

❯ 为什么我换了电池，“Disable Firmware Throttling” 去掉了，风扇还会狂转呢？

  Ran 5 shell commands

我查了你这台机器，"Disable Firmware Throttling" 其实还开着，没去掉。

发现的情况

┌───────────────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│                                检查项                                 │                                       结果                                       │
├───────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────┤
│ OCLP 保存的设置                                                       │ "GUI:disable_fw_throttle" = 1，还是勾选状态                                      │
│ /Users/Shared/.com.dortania.opencore-legacy-patcher.plist             │                                                                                  │
├───────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────┤
│ kextstat                                                              │ com.arter97.SimpleMSR 仍然加载着，也就是降频屏蔽补丁还在起作用                   │
├───────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────┤
│ 新电池                                                                │ 状态很好：循环 3 次，容量 8800/8600 mAh，3 个电芯电压一致（4093/4100/4096        │
│                                                                       │ mV），没有故障标志                                                               │
├───────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────┤
│ pmset -g therm                                                        │ 现在没有降频记录                                                                 │
├───────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────┤
│ 当前 CPU 占用                                                         │ Chrome 渲染进程约 38%，WindowServer 约 23%                                       │
└───────────────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────┘

风扇为什么还狂转

1. 取消勾选没有生效。 可能是取消后没有点 Build and Install OpenCore，或者构建完没重启，或者设置根本没存上。不过这一项不会让风扇转。SimpleMSR 只屏蔽 BD PROCHOT 降频信号，不控制风扇，所以它跟现在的风扇问题关系不大。
2. 换完电池后 SMC 很可能没重置。 风扇由 SMC 控制，旧电池造成的异常状态可能还留在 SMC 里。这台 MacBookPro11,4 的电池不可拆，重置方法：关机，接上电源，按住左侧 Shift + Control + Option + 电源键 10 秒，然后松开开机。
3. 也可能是真的有负载。 Chrome 加上 WindowServer 已经占了 60% 左右的 CPU，4770HQ 这颗老 CPU 本来就容易热，风扇转快可能是正常反应。

下一步怎么判断

请在风扇狂转的时候运行这条命令（powermetrics 需要 sudo，我这边跑不了）：
! sudo powermetrics -n 1 -i 1000 --samplers smc,cpu_power | grep -iE "temp|fan|freq"
- CPU 温度高（80°C 以上）：是真负载，去活动监视器里找占 CPU 的进程，比如 Chrome 标签页或动态壁纸。
- CPU 只有 40 多度，风扇却在 6000 rpm 左右：还是 SMC 状态异常。先按上面的方法重置 SMC。如果还不行，再按 README 4.3 节的方法，取消勾选后重新 Build and Install，然后重启，并用 kextstat | grep SimpleMSR 确认它没再加载。

你把命令输出贴给我，我再帮你判断。

✻ Brewed for 46s · done 9:08 pm

❯ 我做了第一步，并且重启了。3: 完全没有负载的。

  Ran 1 shell command

你说的"第一步"我理解成重置 SMC 了。重启后我又查了一遍：

- CPU 负载：刚开机时的 5 分钟平均负载是 13，这是开机后建索引等后台任务造成的，现在已经降到 2.8，确实没什么负载。
- 降频记录：pmset -g therm 里没有任何降频记录。
- 新电池：没有故障标志，温度 30°C，正常。
- SimpleMSR 还在加载，OCLP 设置里仍然是 disable_fw_throttle = 1。所以 Disable Firmware Throttling 实际上没去掉。不过它不控制风扇，跟风扇狂转无关。

最可能的原因：换电池时有温度传感器没插好

这台机器在不忙、也没降频的情况下风扇全速转，在换过电池的 MacBook Pro 上，这种情况多半是这样来的：

- 2015 款换电池要拆触控板排线、电池温度传感器排线等。只要有一个温度传感器松了、没插回去，或者排线被压坏，SMC 就读不到这个传感器。
- SMC 读不到温度时会按"最坏情况"处理，让风扇一直全速转。重置 SMC 和重启都没用。

另外，第三方电池自带的温度传感器如果读数异常，也会出现同样的现象。

怎么确认

1. 看所有传感器的读数：装 Macs Fan Control（免费），打开就能看到所有温度传感器。哪一项显示 0、-、-127 或者一个明显离谱的值，就是没插好的那个。
2. 看 CPU 温度和风扇转速：运行
! sudo powermetrics -n 1 -i 1000 --samplers smc | grep -iE "temp|fan"
   CPU 只有 40 多度、风扇却在 6000 rpm 左右，就能确定是传感器的问题。
3. 跑 Apple Diagnostics：开机按住 D。如果报出 PPF、PPT 开头的代码，说明是传感器或电池方面的问题。

找到是哪个传感器后，需要拆开后盖把那根排线重新插好。如果是第三方电池自带的传感器坏了，就要找换电池的店返修。

还有一件事

如果你想真正去掉 Disable Firmware Throttling：打开 OCLP，进 Settings，再进 Advanced，取消勾选，一定要点 Save；然后执行 Build and Install OpenCore，再重启。最后用 kextstat | grep SimpleMSR 检查，没有输出才算真的去掉了。

你把 Macs Fan Control 的截图或者 powermetrics 的输出贴给我，我帮你看是哪个传感器。

✻ Baked for 22s · done 9:09 pm

❯ ❯  sudo powermetrics -n 1 -i 1000 --samplers smc | grep -iE "temp|fan"
  Password:
  Sorry, try again.
  Password:
  Fan: 6155 rpm
  CPU die temperature: 52.30 C

  ~/PyPro/OpenCore-Legacy-Patcher-Mac15Fix main 8s
  ❯

这个结果可以确诊：CPU 只有 52°C，风扇却在 6155 rpm，这台机器的风扇最高也就 6100 多转。CPU 并不热，所以是 SMC 收到了错误的温度信息。

目前最可能的原因：有一个温度传感器读不到数，最可能是换电池时排线没插好，SMC 读不到就让风扇全速转。

找出是哪个传感器

这两个测试都不用拆机，按顺序做：

1. 看所有传感器读数
! brew install --cask macs-fan-control
打开 Macs Fan Control，看左边的传感器列表。和电池相关的几项最值得看，比如 Battery、TB0T/TB1T/TB2T、Palm rest、Trackpad。哪一项显示 -、0、-127 或者明显离谱的值，就是它出了问题。

2. 看风扇什么时候开始狂转
关机后再开机，注意风扇是在哪个阶段开始狂转的：
- 一按电源键、还在 OpenCore 选择界面或苹果 logo 阶段就狂转：这时 macOS 还没启动，风扇完全由 SMC 硬件控制，所以基本可以确定是传感器排线这类硬件问题。
- 进了桌面一会儿才开始转：这样也是 SMC 在控制风扇，但要连同合盖睡眠的规律一起看。把具体情况告诉我。

找到之后

- 电池温度传感器（TB）异常*：可能是第三方电池自带的传感器坏了，或者排线没插紧，找换电池的店返修。
- 触控板、掌托附近的传感器异常：换电池时要拆触控板排线，需要拆开后盖把排线重新插好。

把 Macs Fan Control 的传感器列表截图贴给我，我帮你看是哪一项。

✻ Crunched for 13s · done 9:10 pm

※ recap: 你在查换电池后风扇为什么还狂转：CPU 只有 52°C，风扇却在 6155 rpm，可以确定是 SMC 收到了错误的温度信息。下一步请安装 Macs Fan Control，把传感器列表截图发给我，看是哪一项读数异常。 (disable recaps in /config)

❯ [Image #2]
[Image #2]

截图里的传感器都正常，温度都在 29 到 53°C 之间，三个电池传感器（Battery Max 和两个 Battery Sensor）也都有读数。可两个风扇都已经顶到最高转速：左边 6151/6156，右边 5710/5700。

这说明 SMC 是主动把风扇开到最大的，不是因为哪里热。 列表里的传感器都正常，问题多半出在列表里没出现的地方。

可疑点：掌托/触控板传感器不在列表里

2015 款 MacBook Pro 通常还有掌托（Palm Rest，SMC 代号 Ts0P/Ts1P）温度传感器，在触控板和键盘那一片。你的列表里没有，这一点我不能百分之百确定，因为软件不一定都会列出来。但换电池正好要拔触控板那根排线，它最可疑：插歪了、没压紧，或者排线被压坏，SMC 就读不到这个传感器，于是一直把风扇开满。

下一步

1. Apple Diagnostics（最直接）：关机后开机，立即按住 D；如果没进去，换成 Option + D 走联网诊断。报出 PPF、PPT、PPM 开头的代码，就说明是传感器或排线的问题，把代码发给我。
2. 看风扇什么时候开始转：开机时风扇一停在 OpenCore 选择界面就已经狂转，说明问题在硬件，和 macOS、OCLP 无关。
3. 拆机检查：重点看触控板排线和电池排线有没有插好，或者直接找换电池的店，让他们重新插一下触控板和键盘区域的排线。

修好之前的临时办法

在 Macs Fan Control 里给两个风扇都点 Custom...，选 Sensor-based value，传感器选 CPU PECI：温度在 50°C 以下按最低转速，到 85°C 开到最高。这样软件会接管风扇，不用再听 SMC 的。CPU 自己的过热保护还在，所以这样设置是安全的。不过这只是临时办法，掩盖了问题，排线最终还是要重新插好。

还有一件事：SimpleMSR 还在加载，Disable Firmware Throttling 实际上仍然开着，跟风扇问题无关。等风扇修好，再按上次说的步骤去掉，记得 Save 后重新 Build and Install。

✻ Brewed for 20s · done 9:14 pm

❯ 那要怎么恢复好之前？ 除了 Disable Firmware Throttling 关闭。

  Ran 2 shell commands

对照你 README 里的记录，除了 Disable Firmware Throttling，你还改过这几样。下面分别说怎么恢复。

1. 恢复睡眠时的暗唤醒设置（README 4.2）

! sudo pmset -a powernap 1 tcpkeepalive 1 proximitywake 1
恢复后，"查找我的 Mac"在睡眠时也能定位。我查了现在的 pmset -g，这三项都没显示出来，应该还是当初关掉的状态。

2. 关闭 Disable Firmware Throttling

打开 OCLP，进 Settings，再进 Advanced，取消勾选 Disable Firmware Throttling，然后点 Save。接着执行 Build and Install OpenCore，再重启。
重启后运行下面两条检查。第一条应该没有输出；第二条应该显示 = 0，或者找不到这一项：
kextstat | grep SimpleMSR
defaults read /Users/Shared/.com.dortania.opencore-legacy-patcher.plist | grep throttle

3. Macs Fan Control

你截图里两个风扇都是 Auto，这个软件没有改动任何东西。要卸载的话，把 /Applications/Macs Fan Control.app 拖进废纸篓就行，也可以先留着用来观察温度。

不需要恢复的

- SMC 重置：只是清掉 SMC 的状态，没有改任何设置，不用恢复。
- 静态壁纸：建议保留。动态壁纸会让 CPU 一直有负载，想换回去随时在系统设置里改。
- AlDente：本机没装，不用管。

另外提醒一下：恢复这些设置并不能解决风扇狂转。 风扇现在是被 SMC 直接开到最大的，所有传感器又都正常，原因多半在硬件：换电池时有排线没插好，或者某个传感器读不到。软件设置怎么改都碰不到这个原因。最好还是按上次说的跑一下 Apple Diagnostics（开机按住 D），或者让换电池的店重新检查排线。

✻ Baked for 24s · done 9:16 pm

───────────────────────────────────────────────────────────────────────── 1 new message ─────────────────────────────────────────────────────────────────────────

※ recap: 我们在查新电池装好后风扇为什么还狂转，同时把之前改过的设置恢复回去。下一步：在 OCLP 里取消勾选 Disable Firmware Throttling，点 Save，然后 Build and Install 并重启，再开机按住 D 跑一下 Apple Diagnostics。 (disable recaps in /config)
                                                                                                                         ✔ Update installed · Restart to update
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
❯ 把这次风扇排查记录到 README 里
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cyc

```

-------

## 算了还是打开“Disable Firmware Throttling” 不然风扇还是狂转！

```
Disable Firmware Throttling

❯ sysctl machdep.xcpm

machdep.xcpm.mode: 1
machdep.xcpm.pcps_mode: 0
machdep.xcpm.hard_plimit_max_100mhz_ratio: 34
machdep.xcpm.hard_plimit_min_100mhz_ratio: 8
machdep.xcpm.soft_plimit_max_100mhz_ratio: 34
machdep.xcpm.soft_plimit_min_100mhz_ratio: 8
machdep.xcpm.tuib_plimit_max_100mhz_ratio: 34
machdep.xcpm.tuib_plimit_min_100mhz_ratio: 8
machdep.xcpm.lpm_plimit_max_100mhz_ratio: 0
machdep.xcpm.tuib_enabled: 0
machdep.xcpm.lpm_enabled: 0
machdep.xcpm.power_source: 0
machdep.xcpm.bootplim: 0
machdep.xcpm.bootpst: 34
machdep.xcpm.tuib_ns: 0
machdep.xcpm.vectors_loaded_count: 0
machdep.xcpm.ratio_change_ratelimit_ns: 500000
machdep.xcpm.ratio_changes_total: 41713
machdep.xcpm.maxbusdelay: 0
machdep.xcpm.maxintdelay: 0
machdep.xcpm.mid_applications: 0
machdep.xcpm.mid_relaxations: 0
machdep.xcpm.mid_mode: 1
machdep.xcpm.mid_cst_control_limit: 0
machdep.xcpm.mid_mode_active: 0
machdep.xcpm.mbd_mode: 1
machdep.xcpm.mbd_applications: 0
machdep.xcpm.mbd_relaxations: 0
machdep.xcpm.forced_idle_ratio: 100
machdep.xcpm.forced_idle_period: 30000000
machdep.xcpm.deep_idle_log: 0
machdep.xcpm.qos_txfr: 1
machdep.xcpm.deep_idle_count: 0
machdep.xcpm.deep_idle_last_stats: n/a
machdep.xcpm.deep_idle_total_stats: n/a
machdep.xcpm.cpu_thermal_level: 0
machdep.xcpm.gpu_thermal_level: 0
machdep.xcpm.io_thermal_level: 0
machdep.xcpm.io_control_engages: 0
machdep.xcpm.io_control_disengages: 0
machdep.xcpm.io_filtered_reads: 0
machdep.xcpm.pcps_rt_override_mode: 0
machdep.xcpm.io_cst_control_enabled: 0
machdep.xcpm.ring_boost_enabled: 0
machdep.xcpm.io_epp_boost_enabled: 0
machdep.xcpm.epp_override: 0
machdep.xcpm.perf_hints: 0
machdep.xcpm.pcps_rt_override_ns: 0

~
❯

```
