#!/bin/sh

SB_BIN="/usr/local/bin/sing-box"
CONFIG_PATH="/etc/sing-box"
CONFIG_FILE="${CONFIG_PATH}/config.json"
INIT_FILE="/etc/init.d/sing-box"
MY_RELEASE_URL="https://github.com/clerzg/light-vless/releases/latest/download"

echo "==== 1. 环境分析与数据获取 ===="
INFO=$(wget -qO- --no-cache "https://www.cloudflare.com/cdn-cgi/trace")
IP=$(echo "${INFO}" | awk -F= '/^ip=/ {print $2}')
LOC=$(echo "${INFO}" | awk -F= '/^loc=/ {print $2}')
PORT=$(awk 'BEGIN{srand(); print int(rand()*(60000-10000+1))+10000}')

echo "IP: ${IP} | 区域: ${LOC} | 随机端口: ${PORT}"

echo "==== 2. 下载微型 sing-box 二进制文件 ===="
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) SB_ARCH="64" ;;
    aarch64|arm64) SB_ARCH="arm64-v8a" ;;
    *) SB_ARCH="64" ;;
esac

DOWNLOAD_URL="${MY_RELEASE_URL}/sing-box-linux-${SB_ARCH}"
mkdir -p /usr/local/bin
wget -O ${SB_BIN} --no-cache "${DOWNLOAD_URL}"
if [ $? -eq 0 ] && [ -s ${SB_BIN} ]; then
    chmod +x ${SB_BIN}
    echo "下载成功: sing-box-${SB_ARCH}"
else
    echo "错误: 无法下载文件"
    exit 1
fi

echo "==== 3. 生成配置与服务注册 ===="
if [ -f /proc/sys/kernel/random/uuid ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
else
    UUID="00000000-0000-0000-0000-000000000000"
fi

mkdir -p ${CONFIG_PATH}
# 生成 sing-box 专属极简 vless+ws 配置
cat <<EOF > ${CONFIG_FILE}
{"log":{"level":"panic"},"inbounds":[{"type":"vless","tag":"vless-in","listen":"::","listen_port":${PORT},"users":[{"uuid":"${UUID}"}],"transport":{"type":"ws"}}],"outbounds":[{"type":"direct","tag":"direct-out"}]}
EOF

cat << 'EOF' > ${INIT_FILE}
#!/sbin/openrc-run
description="Sing-Box Micro Service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
pidfile="/run/${RC_SVCNAME}.pid"
command_background="yes"
export GOGC=20
export GOMEMLIMIT=24MiB
respawn_delay=1
respawn_max=0
depend() {
    need net
}
EOF

chmod +x ${INIT_FILE}
rc-update add sing-box default >/dev/null 2>&1
rc-service sing-box stop >/dev/null 2>&1
rc-service sing-box start

echo ""
echo "=========================================="
echo "🎉 sing-box 极简部署完成！"
echo ""
echo "vless://${UUID}@${IP}:${PORT}?type=ws&encryption=none#${LOC}"
echo ""
echo "=========================================="
echo "💡 常用指令："
echo "查看状态: rc-service sing-box status"
echo "重启服务: rc-service sing-box restart"
echo "=========================================="