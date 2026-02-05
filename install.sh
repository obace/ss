#!/bin/bash

# ==========================================
# Xray-core SOCKS5 一键部署脚本
# 端口: 10010 | 用户: web | 密码: 250564560
# ==========================================

# 字体颜色配置
RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
PLAIN="\033[0m"     # Reset to default

# 固定配置信息
PORT=10010
USERNAME="web"
PASSWORD="250564560"

# 检查是否为 Root 用户
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}"
   exit 1
fi

echo -e "${GREEN}正在开始部署 Xray SOCKS5 代理...${PLAIN}"

# 1. 安装必要依赖
echo -e "${YELLOW}1. 安装依赖环境...${PLAIN}"
if [[ -f /etc/redhat-release ]]; then
    yum update -y
    yum install -y curl wget unzip tar
elif cat /etc/issue | grep -q -E -i "debian|ubuntu"; then
    apt-get update -y
    apt-get install -y curl wget unzip tar
else
    echo -e "${RED}不支持的操作系统，请使用 CentOS, Debian 或 Ubuntu${PLAIN}"
    exit 1
fi

# 2. 架构检测与下载 Xray
echo -e "${YELLOW}2. 检测系统架构并下载 Xray-core...${PLAIN}"
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
        ;;
    aarch64)
        DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip"
        ;;
    *)
        echo -e "${RED}不支持的架构: $ARCH${PLAIN}"
        exit 1
        ;;
esac

# 创建临时目录并下载
mkdir -p /tmp/xray_install
cd /tmp/xray_install
wget -O xray.zip "$DOWNLOAD_URL"

if [ $? -ne 0 ]; then
    echo -e "${RED}下载失败，请检查网络连接！${PLAIN}"
    exit 1
fi

# 解压并安装
unzip xray.zip
mkdir -p /usr/local/bin/
mkdir -p /usr/local/share/xray/
mkdir -p /usr/local/etc/xray/

mv xray /usr/local/bin/
mv geoip.dat /usr/local/share/xray/
mv geosite.dat /usr/local/share/xray/
chmod +x /usr/local/bin/xray

# 3. 写入配置文件
echo -e "${YELLOW}3. 生成配置文件 (Port: $PORT)...${PLAIN}"
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "$USERNAME",
            "pass": "$PASSWORD"
          }
        ],
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# 4. 配置 Systemd 服务
echo -e "${YELLOW}4. 配置 Systemd 守护进程...${PLAIN}"
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

# 5. 启动服务
echo -e "${YELLOW}5. 启动服务并设置开机自启...${PLAIN}"
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 6. 放行防火墙端口 (尝试常用防火墙命令)
echo -e "${YELLOW}6. 尝试放行防火墙端口 $PORT...${PLAIN}"
if command -v ufw >/dev/null 2>&1; then
    ufw allow $PORT/tcp
    ufw allow $PORT/udp
    ufw reload
fi
if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --zone=public --add-port=$PORT/tcp --permanent
    firewall-cmd --zone=public --add-port=$PORT/udp --permanent
    firewall-cmd --reload
fi
if command -v iptables >/dev/null 2>&1; then
    iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
    iptables -I INPUT -p udp --dport $PORT -j ACCEPT
fi

# 7. 验证状态并输出结果
STATUS=$(systemctl is-active xray)
IP=$(curl -s4 ipv4.icanhazip.com)

echo "------------------------------------------------"
if [ "$STATUS" == "active" ]; then
    echo -e "${GREEN}安装成功！Xray SOCKS5 服务已启动。${PLAIN}"
    echo -e "地址 (IP): ${GREEN}$IP${PLAIN}"
    echo -e "端口 (Port): ${GREEN}$PORT${PLAIN}"
    echo -e "用户名 (User): ${GREEN}$USERNAME${PLAIN}"
    echo -e "密码 (Pass): ${GREEN}$PASSWORD${PLAIN}"
    echo "------------------------------------------------"
    echo -e "Telegram/其他软件连接格式: ${GREEN}socks5://$USERNAME:$PASSWORD@$IP:$PORT${PLAIN}"
else
    echo -e "${RED}安装可能失败，服务状态: $STATUS${PLAIN}"
    echo -e "请尝试运行命令查看日志: journalctl -u xray --no-pager"
fi
echo "------------------------------------------------"

# 清理临时文件
rm -rf /tmp/xray_install
