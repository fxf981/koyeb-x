#!/bin/bash
WORK_DIR=/app
# 修复：x_run 应该只包含可执行文件路径，不包含参数
x_exec="$WORK_DIR/webapp" 
TEMP_DIR=/tmp # 临时目录，用于下载和解压，之后会清理


echo "开始部署。。。"

# 1. 下载并解压 Caddy 到 WORK_DIR
CADDY_LATEST=$(wget -qO- "${GH_PROXY}https://api.github.com/repos/caddyserver/caddy/releases/latest" | awk -F [v\"] '/"tag_name"/{print $5}' || echo '2.7.6')
# 修复：将caddy解压到 $WORK_DIR
wget -c ${GH_PROXY}https://github.com/caddyserver/caddy/releases/download/v${CADDY_LATEST}/caddy_${CADDY_LATEST}_linux_amd64.tar.gz -qO- | tar xz -C $WORK_DIR caddy >/dev/null 2>&1

# 2. 下载并解压新的主站内容
SITE_ZIP_URL="https://github.com/fxf981/mikutap/archive/refs/tags/0.110.zip"
SITE_DIR_NAME="mikutap-0.110" # 假设解压后的文件夹名称
SITE_PATH="$WORK_DIR/$SITE_DIR_NAME"

echo "Downloading and unzipping site content from $SITE_ZIP_URL..."
wget -c -O "$TEMP_DIR/site.zip" "$SITE_ZIP_URL"
# 确保目标目录存在
mkdir -p "$WORK_DIR"
unzip -o "$TEMP_DIR/site.zip" -d "$WORK_DIR"
rm "$TEMP_DIR/site.zip" # 清理临时文件

# 3. 生成 Caddyfile
cat > $WORK_DIR/Caddyfile  << EOF
{
    http_port 2052
}
:8000 {
    @vl path /TG@bing990118
    reverse_proxy @vl unix//etc/caddy/TG@bing990118

    # 提供静态文件作为主页
    file_server
    root * $SITE_PATH
}
EOF

# 4. 下载 geoip.dat, geosite.dat, webapp
wget -c -O $WORK_DIR/geoip.dat ${GH_PROXY}https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
wget -c -O $WORK_DIR/geosite.dat ${GH_PROXY}https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
wget -c -O $WORK_DIR/webapp.zip ${GH_PROXY}https://github.com/fxf981/koyeb-x/archive/refs/tags/1.0.zip

unzip $WORK_DIR/webapp.zip
mv $WORK_DIR/koyeb-x-1.0/webapp $WORK_DIR/webapp
rm -rf $WORK_DIR/koyeb-x-1.0/
rm $WORK_DIR/webapp.zip

# 函数：生成 UUID
generate_uuid() {
    local uuid
    uuid=$(printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x\n' \
        $((RANDOM%65536)) $((RANDOM%65536)) \
        $((RANDOM%65536)) \
        $((RANDOM%4096+16384)) \
        $((RANDOM%16384+32768)) \
        $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)))
    echo "$uuid"
}
if [[ -n "$UUID" ]]; then
    UUID=$UUID
else
    # 调用函数并输出 UUID
    UUID=$(generate_uuid)
    echo "Generated UUID: $UUID"
fi

generate_config() {
    echo "生成config.json"
  if [ -n "$ssurl" ]; then
    url_without_protocol=${ssurl#socks5://}
    user_pass=$(echo "$url_without_protocol" | awk -F'@' '{print $1}')
    ip_port=$(echo "$url_without_protocol" | awk -F'@' '{print $2}')

    ssuser=$(echo "$user_pass" | awk -F':' '{print $1}')
    sspass=$(echo "$user_pass" | awk -F':' '{print $2}')
    ssip=$(echo "$ip_port" | awk -F':' '{print $1}')
    ssport=$(echo "$ip_port" | awk -F':' '{print $2}')

    outbounds='
      "outbounds": [
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "blackhole", "settings": {}, "tag": "blocked"},
        {
          "protocol": "socks",
          "settings": {
            "servers": [{
              "address": "'"$ssip"'",
              "port": '"$ssport"',
              "users": [{"pass": "'"$sspass"'", "user": "'"$ssuser"'"}]
            }]
          },
          "tag": "ss"
        }
      ]'

    routingset='{"network": "tcp,udp","outboundTag": "ss","type": "field"}'
  else
    outbounds='
      "outbounds": [
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "blackhole", "settings": {}, "tag": "blocked"}
      ]'

    routingset='{"network": "tcp,udp","outboundTag": "direct","type": "field"}'
  fi

  mkdir -p /etc/caddy
  cat > $WORK_DIR/xconfig.json << EOF
{
  "log": {
    "access": "/dev/null",
    "error": "/dev/null",
    "loglevel": "none"
  },
  "dns": {
    "queryStrategy": "UseIP",
    "servers": ["https://8.8.8.8/dns-query"],
    "tag": "dns_inbound"
  },
  "inbounds": [{
    "listen": "/etc/caddy/TG@bing990118",
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$UUID"}],
      "decryption": "none"
    },
    "streamSettings": {"network": "ws","wsSettings": {"path": "/TG@bing990118"}}
  }],
  $outbounds,
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {"ip":["geoip:private"], "outboundTag":"blocked", "type":"field"},
      {"protocol":["bittorrent"], "outboundTag":"blocked", "type":"field"},
      {
        "type": "field",
        "domain": [
          "domain:fast.com",
          "domain:www.fast.com",
          "domain:speedtest.net",
          "domain:www.speedtest.net",
          "domain:ookla.com",
          "domain:www.ookla.com",
          "domain:ooklaserver.net",
          "domain:speedtest.cn",
          "domain:measurementlab.net",
          "domain:ndt.measurementlab.net",
          "domain:wehe.measurementlab.net",
          "domain:speed.cloudflare.com",
          "domain:fiber.google.com"
        ],
        "outboundTag": "blocked"
      },
      $routingset
    ]
  }
}
EOF
}

generate_config

# 判断这四个变量是否都存在且不为空
if [[ -n "$nzSERVER" && -n "$nzPORT" && -n "$nzTLS" && -n "$nzCLIENT_SECRET" && -n "$UUID" ]]; then
    echo "哪吒所有变量都已设置，开始安装哪吒。"
    curl -L https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh -o agent.sh && chmod +x agent.sh && env NZ_SERVER=$nzSERVER:$nzPORT NZ_TLS=$nzTLS NZ_CLIENT_SECRET=$nzCLIENT_SECRET NZ_UUID=$UUID ./agent.sh
else
    echo "哪吒部分或所有变量未设置，跳过安装哪吒。"
fi


# 检查环境变量是否为空
if [[ -n "$keepaliveDomain" ]]; then

    # 1. 定义脚本的完整路径
    # 如果没有指定 WORK_DIR，则使用当前目录
    WORK_DIR=${WORK_DIR:-$(pwd)}
    scriptPath="$WORK_DIR/run_curl_11_times.sh"

    # 2. 创建执行11次curl的脚本
    cat > "$scriptPath" << 'EOF'
#!/bin/bash

# 定义要访问的域名
keepaliveDomain="$keepaliveDomain"

# 设置循环次数
count=22

# 执行循环
for i in $(seq 1 $count)
do
    /usr/bin/curl "$keepaliveDomain" >/dev/null 2>&1
done
EOF

    # 给新脚本添加可执行权限
    chmod +x "$scriptPath"

    # 3. 检查 crontab 中是否已经有这个脚本的定时任务
    if ! sudo grep -q "$scriptPath" /etc/crontab; then
        # 如果不存在，则写入新的 cron 任务
        echo "正在添加新的 cron 任务到 /etc/crontab..."
        sudo echo "* * * * * root $scriptPath" >> /etc/crontab
        echo "任务已添加：每分钟运行一次 $scriptPath"
    else
        echo "cron 任务已存在于 /etc/crontab，无需重复添加。"
    fi

else
    echo "keepaliveDomain 变量为空，未修改 /etc/crontab。"
fi


# 生成 supervisor 进程守护配置文件
  cat > /etc/supervisor/conf.d/damon.conf << EOF
[supervisord]
nodaemon=true
logfile=/dev/null
pidfile=/run/supervisord.pid

[program:caddy]
command=$WORK_DIR/caddy run --config $WORK_DIR/Caddyfile --watch # 修复：直接使用完整的caddy命令
autostart=true
autorestart=true
stderr_logfile=/dev/null
stdout_logfile=/dev/null

[program:webapp]
command=$x_exec run -c $WORK_DIR/xconfig.json # 修复：使用x_exec变量，并传递参数
autostart=true
autorestart=true
stderr_logfile=/dev/null
stdout_logfile=/dev/null

EOF

# 赋执行权给所有应用 (注意：必须在文件下载并存在之后执行 chmod)
# 这些文件都是下载到 $WORK_DIR 的，所以在这里统一赋权
chmod +x $WORK_DIR/caddy $WORK_DIR/webapp

# 运行 supervisor 进程守护
supervisord -c /etc/supervisor/supervisord.conf

