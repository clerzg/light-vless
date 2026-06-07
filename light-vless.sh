#!/bin/sh

XRAY_BIN="/usr/local/bin/xray"
CONFIG_PATH="/etc/xray"
CONFIG_FILE="${CONFIG_PATH}/config.json"
INIT_FILE="/etc/init.d/xray"
MY_RELEASE_URL="https://github.com/clerzg/light-vless/releases/latest/download"

echo "==== 1. 环境分析与数据获取 ===="
INFO=$(wget -qO- --no-cache "https://www.cloudflare.com/cdn-cgi/trace")
IP=$(echo "${INFO}" | awk -F= '/^ip=/ {print $2}')
LOC=$(echo "${INFO}" | awk -F= '/^loc=/ {print $2}')
PORT=$(awk 'BEGIN{srand(); print int(rand()*(60000-10000+1))+10000}')

echo "IP: ${IP} | 区域: ${LOC} | 随机端口: ${PORT}"

echo "==== 2. 下载定制版 Xray 二进制文件 ===="
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) XRAY_ARCH="64" ;;
    aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
    *) XRAY_ARCH="64" ;;
esac

DOWNLOAD_URL="${MY_RELEASE_URL}/xray-linux-${XRAY_ARCH}.tar.gz"
mkdir -p /usr/local/bin
wget -O ${XRAY_BIN} "${DOWNLOAD_URL}" | tar -xz
if [ $? -eq 0 ] && [ -s ${XRAY_BIN} ]; then
    chmod +x ${XRAY_BIN}
    echo "下载成功: ${XRAY_ARCH}"
else
    echo "错误: 无法从下载xray文件"
    exit 1
fi

echo "==== 3. 生成配置与服务注册 ===="
if [ -f /proc/sys/kernel/random/uuid ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
else
    UUID=$(${XRAY_BIN} uuid)
fi

mkdir -p ${CONFIG_PATH}
cat <<EOF > ${CONFIG_FILE}
{"log":{"loglevel":"none"},"policy":{"levels":{"0":{"handshake":4,"connIdle":30,"uplinkOnly":2,"downlinkOnly":2,"bufferSize":2}}},"inbounds":[{"port":${PORT},"protocol":"vless","settings":{"clients":[{"id":"${UUID}"}],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{}}}],"outbounds":[{"protocol":"freedom","settings":{"domainStrategy":"UseIP"}}]}
EOF

cat << 'EOF' > ${INIT_FILE}
#!/sbin/openrc-run
description="Xray Mini Service"
command="/usr/local/bin/xray"
command_args="run -c /etc/xray/config.json"
pidfile="/run/${RC_SVCNAME}.pid"
command_background="yes"
export GOGC=20
export GOMEMLIMIT=32MiB
respawn_delay=1
respawn_max=0
depend() {
    need net
}
EOF

chmod +x ${INIT_FILE}
rc-update add xray default >/dev/null 2>&1
rc-service xray stop >/dev/null 2>&1
rc-service xray start

echo ""
echo "=========================================="
echo "🎉 部署完成！节点链接如下："
echo ""
echo "vless://${UUID}@${IP}:${PORT}?type=ws&encryption=none#${LOC}"
echo ""
echo "=========================================="
echo "💡 常用指令："
echo "查看状态: rc-service xray status"
echo "重启服务: rc-service xray restart"
echo "=========================================="