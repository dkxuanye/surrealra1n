#!/bin/bash
cd "$(dirname "$0")"
LOG="/tmp/surrealra1n_$(date +%Y%m%d_%H%M%S).log"
echo "日志: $LOG"
/usr/bin/script -q "$LOG" ./surrealra1n.sh
echo ""
echo "脚本已结束，按回车关闭窗口"
read -r
