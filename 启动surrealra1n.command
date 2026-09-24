#!/bin/bash
cd "$(dirname "$0")"

echo "=================================================="
echo "surrealra1n 需要管理员权限（sudo）。"
echo "接下来请输入你的 Mac 登录密码。"
echo ""
echo "注意：输入密码时屏幕上不会显示任何字符，这是正常的。"
echo "输完密码直接按回车即可。"
echo "=================================================="
echo ""

while ! sudo -v -p "请输入 Mac 登录密码（输入时不显示）："; do
    echo ""
    echo "密码错误或已取消。"
    read -r -p "按回车重试，输入 q 退出：" retry
    retry="${retry//[$'\r']/}"
    if [[ "$retry" == "q" || "$retry" == "Q" ]]; then
        echo "已取消，按回车关闭窗口"
        read -r
        exit 1
    fi
done

# 长时间恢复期间保持 sudo 授权，避免中途再次弹出密码提示
( while sudo -n -v 2>/dev/null; do sleep 60; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

LOG="/tmp/surrealra1n_$(date +%Y%m%d_%H%M%S).log"
echo "日志: $LOG"
/usr/bin/script -q "$LOG" ./surrealra1n.sh
echo ""
echo "脚本已结束，按回车关闭窗口"
read -r
