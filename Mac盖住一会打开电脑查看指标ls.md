```

❯ sysctl machdep.xcpm.hard_plimit_max_100mhz_ratio

machdep.xcpm.hard_plimit_max_100mhz_ratio: 34

~
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
machdep.xcpm.ratio_changes_total: 43304478
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
❯ pmset -g therm
Note: No thermal warning level has been recorded
Note: No performance warning level has been recorded
Note: No CPU power status has been recorded

~
❯ sudo powermetrics -n 1 -i 1000 --samplers smc | grep -iE "temp|fan"
Password:
Fan: 6155 rpm
CPU die temperature: 56.51 C

~
❯ sudo powermetrics -n 1 -i 1000 --samplers cpu_power
Machine model: MacBookPro11,4
SMC version: 2.29f24
EFI version: 489.0.0
OS version: 24H23
Boot arguments: keepsyms=1 debug=0x100 -lilubetaall ipc_control_port_options=0 -nokcmismatchpanic
Boot time: Fri Sep 25 09:00:41 2026



*** Sampled system activity (Tue Sep 29 19:44:14 2026 +0800) (1001.02ms elapsed) ***


**** Processor usage ****

Intel energy model derived package power (CPUs+GT+SA): 12.39W

LLC flushed residency: 12.5%

System Average frequency as fraction of nominal: 109.04% (2398.81 Mhz)
Package 0 C-state residency: 15.64% (C2: 15.64% C3: 0.00% C6: 0.00% C7: 0.00% )

Core 0 C-state residency: 69.52% (C3: 0.00% C6: 0.02% C7: 69.50% )

CPU 0 duty cycles/s: active/idle [< 16 us: 360.63/155.84] [< 32 us: 102.90/101.90] [< 64 us: 244.75/186.81] [< 128 us: 231.76/187.81] [< 256 us: 161.84/130.87] [< 512 us: 76.92/148.85] [< 1024 us: 76.92/143.85] [< 2048 us: 14.98/137.86] [< 4096 us: 28.97/103.89] [< 8192 us: 1.00/4.99] [< 16384 us: 2.00/0.00] [< 32768 us: 0.00/0.00]
CPU Average frequency as fraction of nominal: 106.15% (2335.26 Mhz)

CPU 1 duty cycles/s: active/idle [< 16 us: 42.96/8.99] [< 32 us: 34.96/8.99] [< 64 us: 12.99/16.98] [< 128 us: 15.98/12.99] [< 256 us: 4.99/4.99] [< 512 us: 2.00/6.99] [< 1024 us: 2.00/4.99] [< 2048 us: 1.00/8.99] [< 4096 us: 0.00/9.99] [< 8192 us: 0.00/4.99] [< 16384 us: 0.00/11.99] [< 32768 us: 0.00/6.99]
CPU Average frequency as fraction of nominal: 117.69% (2589.17 Mhz)

Core 1 C-state residency: 79.32% (C3: 0.46% C6: 0.01% C7: 78.85% )

CPU 2 duty cycles/s: active/idle [< 16 us: 497.49/161.84] [< 32 us: 117.88/29.97] [< 64 us: 186.81/173.82] [< 128 us: 163.83/185.81] [< 256 us: 84.91/128.87] [< 512 us: 63.93/148.85] [< 1024 us: 55.94/140.86] [< 2048 us: 9.99/83.91] [< 4096 us: 17.98/104.89] [< 8192 us: 2.00/39.96] [< 16384 us: 0.00/1.00] [< 32768 us: 0.00/0.00]
CPU Average frequency as fraction of nominal: 106.79% (2349.37 Mhz)

CPU 3 duty cycles/s: active/idle [< 16 us: 46.95/9.99] [< 32 us: 31.97/9.99] [< 64 us: 10.99/4.99] [< 128 us: 15.98/5.99] [< 256 us: 5.99/12.99] [< 512 us: 3.00/11.99] [< 1024 us: 1.00/6.99] [< 2048 us: 2.00/6.99] [< 4096 us: 0.00/9.99] [< 8192 us: 0.00/6.99] [< 16384 us: 0.00/13.99] [< 32768 us: 0.00/8.99]
CPU Average frequency as fraction of nominal: 120.72% (2655.89 Mhz)

Core 2 C-state residency: 80.01% (C3: 0.01% C6: 0.01% C7: 79.99% )

CPU 4 duty cycles/s: active/idle [< 16 us: 433.56/168.83] [< 32 us: 85.91/31.97] [< 64 us: 141.86/121.88] [< 128 us: 118.88/118.88] [< 256 us: 60.94/97.90] [< 512 us: 45.95/110.89] [< 1024 us: 61.94/93.90] [< 2048 us: 8.99/76.92] [< 4096 us: 11.99/92.91] [< 8192 us: 2.00/55.94] [< 16384 us: 2.00/3.00] [< 32768 us: 0.00/0.00]
CPU Average frequency as fraction of nominal: 111.80% (2459.57 Mhz)

CPU 5 duty cycles/s: active/idle [< 16 us: 35.96/7.99] [< 32 us: 17.98/8.99] [< 64 us: 18.98/6.99] [< 128 us: 16.98/8.99] [< 256 us: 3.00/12.99] [< 512 us: 2.00/3.00] [< 1024 us: 2.00/7.99] [< 2048 us: 0.00/5.99] [< 4096 us: 0.00/4.00] [< 8192 us: 1.00/4.00] [< 16384 us: 0.00/8.99] [< 32768 us: 0.00/6.99]
CPU Average frequency as fraction of nominal: 132.98% (2925.57 Mhz)

Core 3 C-state residency: 87.04% (C3: 0.00% C6: 0.01% C7: 87.03% )

CPU 6 duty cycles/s: active/idle [< 16 us: 350.64/98.90] [< 32 us: 90.91/18.98] [< 64 us: 82.92/86.91] [< 128 us: 103.89/107.89] [< 256 us: 48.95/69.93] [< 512 us: 32.97/78.92] [< 1024 us: 29.97/84.91] [< 2048 us: 4.00/71.93] [< 4096 us: 10.99/63.93] [< 8192 us: 1.00/57.94] [< 16384 us: 1.00/15.98] [< 32768 us: 0.00/0.00]
CPU Average frequency as fraction of nominal: 111.10% (2444.17 Mhz)

CPU 7 duty cycles/s: active/idle [< 16 us: 47.95/4.99] [< 32 us: 25.97/4.99] [< 64 us: 20.98/10.99] [< 128 us: 5.99/4.99] [< 256 us: 2.00/8.99] [< 512 us: 0.00/4.99] [< 1024 us: 1.00/5.99] [< 2048 us: 0.00/9.99] [< 4096 us: 0.00/5.99] [< 8192 us: 0.00/6.99] [< 16384 us: 0.00/11.99] [< 32768 us: 0.00/14.98]
CPU Average frequency as fraction of nominal: 116.65% (2566.20 Mhz)

~
❯ sysctl -n machdep.cpu.brand_string
Intel(R) Core(TM) i7-4770HQ CPU @ 2.20GHz

~
❯ uptime
19:44  up 4 days, 10:44, 2 users, load averages: 2.13 4.87 6.56

~
❯ ps -Ao pid,pcpu,pmem,etime,comm -r | head -15
  PID  %CPU %MEM     ELAPSED COMM
  160  20.5  0.9 04-10:45:25 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
48406  13.9  0.8 01-11:58:57 /Applications/橘子加速.app/Contents/MacOS/橘子加速
64168   7.0  0.8       06:39 /Applications/iTerm.app/Contents/MacOS/iTerm2
  503   1.3  1.1 04-10:44:59 /System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight
62375   0.7  2.2    20:35:43 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
64174   0.6  0.0       06:38 -zsh
  433   0.5  0.1 04-10:45:04 /System/Library/PrivateFrameworks/CoreDuetContext.framework/Resources/ContextStoreAgent
  395   0.5  0.2 04-10:45:05 /System/Library/PrivateFrameworks/BiomeStreams.framework/Support/BiomeAgent
  362   0.3  0.2 04-10:45:07 /System/Library/CoreServices/WindowManager.app/Contents/MacOS/WindowManager
62391   0.3  1.3    20:35:41 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/153.0.8010.53/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper
  504   0.2  0.2 04-10:44:59 /System/Library/PrivateFrameworks/TextInputUIMacHelper.framework/Versions/A/XPCServices/CursorUIViewService.xpc/Contents/MacOS/CursorUIViewService
  466   0.1  0.1 04-10:45:01 /System/Library/PrivateFrameworks/UserActivity.framework/Agents/useractivityd
  451   0.1  0.3 04-10:45:02 /usr/libexec/sharingd
  154   0.1  0.2 04-10:45:27 /usr/sbin/bluetoothd

~
❯ top -o cpu -n 15

~
❯ top -o cpu -n 15 | head -n 15
Processes: 659 total, 3 running, 656 sleeping, 2261 threads
2026/09/29 19:47:00
Load Avg: 2.32, 3.93, 5.95
CPU usage: 5.21% user, 12.35% sys, 82.43% idle
SharedLibs: 700M resident, 159M data, 123M linkedit.
MemRegions: 214213 total, 4607M resident, 324M private, 2413M shared.
PhysMem: 16G used (2810M wired, 384M compressor), 364M unused.
VM: 33T vsize, 5236M framework vsize, 52439(0) swapins, 126874(0) swapouts.
Networks: packets: 6500649/8300M in, 8822619/9977M out.
Disks: 3623967/43G read, 2081332/41G written.

PID    COMMAND          %CPU TIME     #TH #WQ #PORTS MEM   PURG CMPRS PGRP  PPID  STATE    BOOSTS    %CPU_ME %CPU_OTHRS UID FAULTS COW  MSGSENT MSGRECV SYSBSD SYSMACH CSW    PAGEINS IDLEW POWER INSTRS CYCLES JETPRI USER  #MREGS RPRVT VPRVT VSIZE KPRVT KSHRD
64675  head             0.0  00:00.06 1   0   12     1052K 0B   0B    64674 64174 sleeping *0[1]     0.00000 0.00000    501 1493   226  30      15      3712   1381    132    2       0     0.0   0      0      180    xlisp N/A    N/A   N/A   N/A   N/A   N/A
64674  top              0.0  00:00.72 1/1 0   17     4944K 0B   0B    64674 64174 running  *0[1]     0.00000 0.00000    0   4478   328  508225  254112  7045   259738  449    133     0     0.0   0      0      180    root  N/A    N/A   N/A   N/A   N/A   N/A
64616  mdworker_shared  0.0  00:00.29 4   1   49     2480K 0B   0B    64616 1     sleeping *0[1]     0.00000 0.00000    501 19104  567  876     402     10188  4085    338    281     0     0.0   0      0      0      xlisp N/A    N/A   N/A   N/A   N/A   N/A


~
❯

~
❯
```

