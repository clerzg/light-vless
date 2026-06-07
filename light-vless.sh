#!/bin/sh

# ====================================================
# 配置信息定义
# ====================================================
XRAY_BIN="/usr/local/bin/xray"
CONFIG_PATH="/etc/xray"
CONFIG_FILE="${CONFIG_PATH}/config.json"
INIT_FILE="/etc/init.d/xray"

# 🛠️ 填入你通过 GitHub Actions 编译出来的文件下载前缀
MY_RELEASE_URL="https://github.com/clerzg/light-vless/releases/latest/download"

echo "==== 1. 获取 Cloudflare trace 数据 ===="
# 直接使用系统自带的 wget，无任何安装开销
INFO=$(wget -qO-  "https://www.cloudflare.com/cdn-cgi/trace")
IP=$(echo "${INFO}" | awk -F= '/^ip=/ {print $2}')
LOC=$(echo "${INFO}" | awk -F= '/^loc=/ {print $2}')

echo "当前服务器 IP: ${IP}"
echo "当前服务器位置: ${LOC}"

echo "==== 2. 动态生成随机端口 (10000-60000 之间) ===="
PORT=$(awk 'BEGIN{srand(); print int(rand()*(60000-10000+1))+10000}')
echo "分配的随机端口号为: ${PORT}"

echo "==== 3. 识别系统架构并直接下载你编译好的 Xray 单文件 ==== "
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) XRAY_ARCH="64" ;;
    aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
    *) XRAY_ARCH="64" ;;
esac

# 拼接你在 GitHub Action 里定好的纯二进制文件名
DOWNLOAD_URL="${MY_RELEASE_URL}/xray-linux-${XRAY_ARCH}"

mkdir -p /usr/local/bin
echo "正在从你的 GitHub Release 获取定制版 Xray 二进制文件..."

# 使用自带的 wget 直接下载并覆盖到目标目录
wget -O ${XRAY_BIN} --no-cache "${DOWNLOAD_URL}"
if [ $? -eq 0 ] && [ -s ${XRAY_BIN} ]; then
    chmod +x ${XRAY_BIN}
    echo "✅ 下载成功并已赋予执行权限！"
else
    echo "❌ 错误：下载失败，请检查你的 GitHub Release 链接或网络！"
    exit 1
fi

echo "==== 4. 动态生成 UUID ===="
if [ -f /proc/sys/kernel/random/uuid ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
else
    UUID=$(${XRAY_BIN} uuid)
fi
echo "生成的动态 UUID 为: ${UUID}"

echo "==== 5. 生成特制极简配置 ===="
mkdir -p ${CONFIG_PATH}
cat <<EOF > ${CONFIG_FILE}
{"log":{"loglevel":"none"},"policy":{"levels":{"0":{"handshake":4,"connIdle":30,"uplinkOnly":2,"downlinkOnly":2,"bufferSize":2}}},"inbounds":[{"port":${PORT},"protocol":"vless","settings":{"clients":[{"id":"${UUID}"}],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{}}}],"outbounds":[{"protocol":"freedom","settings":{"domainStrategy":"UseIP"}}]}
EOF

echo "==== 6. 自动注册 Alpine OpenRC 系统服务 ===="
cat << 'EOF' > ${INIT_FILE}
#!/sbin/openrc-run

description="Xray Mini Service for Alpine"
command="/usr/local/bin/xray"
command_args="run -c /etc/xray/config.json"
pidfile="/run/${RC_SVCNAME}.pid"
command_background="yes"

# 内存守护：强制约束 Go 运行时内存
export GOGC=20
export GOMEMLIMIT=32MiB

# 崩溃自动重启守护
respawn_delay=1
respawn_max=0

depend() {
    need net
}
EOF

chmod +x ${INIT_FILE}

echo "==== 7. 启动服务并设置开机自启 ===="
rc-update add xray default >/dev/null 2>&1
rc-service xray stop >/dev/null 2>&1
rc-service xray start

# 拼接专属 VLESS 节点链接
VLESS_LINK="vless://${UUID}@${IP}:${PORT}?type=ws&encryption=none#${LOC}"

echo "=========================================="
echo "🎉 部署完成！已经在 Alpine 后台静默运行。"
echo "=========================================="
echo "👇 你的专用 VLESS 节点链接（直接整行复制）："
echo ""
echo "${VLESS_LINK}"
echo ""
echo "=========================================="
echo "💡 实用运维指令："
echo "查看运行状态: rc-service xray status"
echo "重启服务: rc-service xray restart"
echo "停止服务: rc-service xray stop"
echo "=========================================="