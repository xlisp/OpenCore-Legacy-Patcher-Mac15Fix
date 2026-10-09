
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
