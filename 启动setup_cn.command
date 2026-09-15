#!/bin/bash
cd "$(dirname "$0")"
LOG="/tmp/setup_cn_$(date +%Y%m%d_%H%M%S).log"
echo "日志: $LOG"
/usr/bin/script -q "$LOG" ./setup_cn.sh
echo ""
echo "脚本已结束，按回车关闭窗口"
read -r
