#!/bin/sh
# 开机登录后确保 Wi-Fi 打开并自动加入已知网络（OCLP 老网卡补丁的开机不自动连接问题）
IF=en0
sleep 5
for i in 1 2 3; do
  /usr/sbin/networksetup -setairportpower $IF on
  sleep 15
  if /usr/sbin/ipconfig getifaddr $IF >/dev/null 2>&1; then
    echo "$(date) connected on try $i"; exit 0
  fi
  /usr/sbin/networksetup -setairportpower $IF off
  sleep 3
done
/usr/sbin/networksetup -setairportpower $IF on
echo "$(date) not connected after retries"
