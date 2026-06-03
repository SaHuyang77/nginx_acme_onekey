#!/bin/bash

# =============================================
#   Nginx + ACME SSL 一键部署脚本（通用版）
#   支持 Oracle Linux / CentOS / Debian / Ubuntu
#   支持自定义反向代理目标 + 静态站点
# =============================================

Green="\033[32m"
Red="\033[31m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

# 默认值
DEFAULT_SSL_DIR="/data/ssl"
DEFAULT_NGINX_SSL_DIR="/etc/nginx/ssl"
DEFAULT_EMAIL_PREFIX="admin@"

# 检测root
is_root() {
    [ "$(id -u)" -ne 0 ] && echo -e "${Error} 请使用 root 用户执行！" && exit 1
}

# 系统检测
check_system() {
    source /etc/os-release
    if [[ "${ID}" == "ol" || "${ID}" == "centos" || "${ID}" == "rocky" || "${ID}" == "almalinux" ]]; then
        INS="dnf"
        echo -e "${OK} 当前系统：${PRETTY_NAME}"
    elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 10 ]]; then
        INS="apt"
        echo -e "${OK} 当前系统：${PRETTY_NAME}"
    elif [[ "${ID}" == "ubuntu" && $(echo "${VERSION_ID}" | cut -d. -f1) -ge 20 ]]; then
        INS="apt"
        echo -e "${OK} 当前系统：${PRETTY_NAME}"
    else
        echo -e "${Error} 不支持的系统：${PRETTY_NAME}" && exit 1
    fi
}

judge() {
    if [[ $? -eq 0 ]]; then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
    else
        echo -e "${Error} ${RedBG} $1 失败 ${Font}" && exit 1
    fi
}

# 显示使用帮助
show_usage() {
    echo -e "${GreenBG}==================== 使用说明 ====================${Font}"
    echo -e "用法: $0 <域名> <模式> [邮箱]"
    echo -e ""
    echo -e "模式说明:"
    echo -e "  <反代目标>       反代模式：格式 IP:端口 或 localhost:端口"
    echo -e "  static           静态站点模式"
    echo -e ""
    echo -e "示例:"
    echo -e "  $0 hermesweb.shipaiagent.ccwu.cc 127.0.0.1:8648"
    echo -e "  $0 shipaiagent.ccwu.cc static"
    echo -e "${GreenBG}===================================================${Font}"
    exit 1
}

# 参数解析
parse_args() {
    if [[ $# -lt 2 ]]; then
        show_usage
    fi

    domain="$1"
    mode="$2"
    email="${3:-${DEFAULT_EMAIL_PREFIX}${domain}}"

    # 简单校验域名
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${Error} 域名格式不正确: $domain" && exit 1
    fi

    if [[ "$mode" == "static" ]]; then
        deploy_mode="static"
        echo -e "${Info} 域名: ${Green}${domain}${Font}"
        echo -e "${Info} 模式: ${Green}静态站点${Font}"
        echo -e "${Info} 邮箱: ${Green}${email}${Font}"
    else
        deploy_mode="proxy"
        proxy_target="$mode"
        if [[ ! "$proxy_target" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
            echo -e "${Error} 反向代理目标格式不正确（应为 IP:端口 或 localhost:端口）: $proxy_target" && exit 1
        fi
        echo -e "${Info} 域名: ${Green}${domain}${Font}"
        echo -e "${Info} 反向代理目标: ${Green}http://${proxy_target}${Font}"
        echo -e "${Info} 邮箱: ${Green}${email}${Font}"
    fi
}

# 安装依赖
install_dependency() {
    echo -e "${Info} 安装依赖..."
    if [[ "${INS}" == "apt" ]]; then
        apt update -y
        apt install -y curl socat git cron nginx
    else
        dnf install -y epel-release || true
        dnf makecache -y
        dnf install -y curl socat git cronie nginx
        systemctl enable crond --now
    fi
    judge "依赖安装"
}

# 安装 acme.sh
install_acme() {
    echo -e "${Info} 安装 acme.sh..."
    curl -s https://get.acme.sh | sh -s email="${email}"
    judge "acme.sh 安装"
    export PATH="$HOME/.acme.sh:$PATH"
    source "$HOME/.bashrc" 2>/dev/null || true
}

# 申请证书
apply_ssl() {
    echo -e "${Info} 正在申请 Let's Encrypt 证书（${domain}）..."

    systemctl stop nginx >/dev/null 2>&1 || true

    "$HOME/.acme.sh/acme.sh" --set-default-ca --server letsencrypt
    "$HOME/.acme.sh/acme.sh" --issue --standalone -d "${domain}" -k ec-256 --force

    if [ $? -eq 0 ]; then
        echo -e "${OK} SSL 证书申请成功！"
        mkdir -p "${DEFAULT_SSL_DIR}"
        "$HOME/.acme.sh/acme.sh" --installcert -d "${domain}" \
            --fullchainpath "${DEFAULT_SSL_DIR}/${domain}.crt" \
            --keypath "${DEFAULT_SSL_DIR}/${domain}.key" --ecc --force
        judge "证书安装"
    else
        echo -e "${Error} 证书申请失败！请确保域名已解析且 80 端口可访问。" && exit 1
    fi
}

# 配置 Nginx（反代模式）
config_nginx_proxy() {
    echo -e "${Info} 配置 Nginx 反向代理到 ${proxy_target}..."

    mkdir -p "${DEFAULT_NGINX_SSL_DIR}"
    cp "${DEFAULT_SSL_DIR}/${domain}.crt" "${DEFAULT_NGINX_SSL_DIR}/"
    cp "${DEFAULT_SSL_DIR}/${domain}.key" "${DEFAULT_NGINX_SSL_DIR}/"

    cat > /etc/nginx/conf.d/${domain}.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};

    ssl_certificate       ${DEFAULT_NGINX_SSL_DIR}/${domain}.crt;
    ssl_certificate_key   ${DEFAULT_NGINX_SSL_DIR}/${domain}.key;

    ssl_protocols         TLSv1.2 TLSv1.3;
    ssl_ciphers           HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache     shared:SSL:10m;
    ssl_session_timeout   10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    location / {
        proxy_pass http://${proxy_target};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    nginx -t
    judge "Nginx 配置语法检查"

    systemctl enable nginx --now
    systemctl reload nginx || systemctl restart nginx
    judge "Nginx 启动/重载"
}

# 配置 Nginx（静态站点模式）
config_nginx_static() {
    echo -e "${Info} 配置 Nginx 静态站点..."

    mkdir -p "${DEFAULT_NGINX_SSL_DIR}"
    cp "${DEFAULT_SSL_DIR}/${domain}.crt" "${DEFAULT_NGINX_SSL_DIR}/"
    cp "${DEFAULT_SSL_DIR}/${domain}.key" "${DEFAULT_NGINX_SSL_DIR}/"

    # 创建网站目录
    mkdir -p "/var/www/${domain}"

    # 创建默认 index.html
    cat > "/var/www/${domain}/index.html" << HTMLEOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${domain}</title>
    <style>
        body { font-family: system-ui, -apple-system, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #f8fafc; color: #334155; }
        .container { text-align: center; padding: 40px; }
        h1 { font-size: 2rem; margin-bottom: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>${domain}</h1>
        <p>域名已成功通过 Nginx + Let's Encrypt 配置</p>
    </div>
</body>
</html>
HTMLEOF

    chown -R opc:opc "/var/www/${domain}"

    cat > /etc/nginx/conf.d/${domain}.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};

    ssl_certificate       ${DEFAULT_NGINX_SSL_DIR}/${domain}.crt;
    ssl_certificate_key   ${DEFAULT_NGINX_SSL_DIR}/${domain}.key;

    ssl_protocols         TLSv1.2 TLSv1.3;
    ssl_ciphers           HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache     shared:SSL:10m;
    ssl_session_timeout   10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    root /var/www/${domain};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    nginx -t
    judge "Nginx 配置语法检查"

    systemctl enable nginx --now
    systemctl reload nginx || systemctl restart nginx
    judge "Nginx 启动/重载"
}

# 设置自动续期
setup_renew() {
    echo -e "${Info} 设置证书自动续期..."
    "$HOME/.acme.sh/acme.sh" --install-cronjob
    "$HOME/.acme.sh/acme.sh" --upgrade --auto-upgrade

    cat > /usr/local/bin/ssl-update-${domain}.sh << EOF
#!/bin/bash
export PATH="\$HOME/.acme.sh:\$PATH"
/root/.acme.sh/acme.sh --cron --home "/root/.acme.sh" > /var/log/acme-cron.log 2>&1
/root/.acme.sh/acme.sh --installcert -d ${domain} \\
    --fullchainpath ${DEFAULT_SSL_DIR}/${domain}.crt \\
    --keypath ${DEFAULT_SSL_DIR}/${domain}.key --ecc --force
cp ${DEFAULT_SSL_DIR}/${domain}.crt ${DEFAULT_NGINX_SSL_DIR}/
cp ${DEFAULT_SSL_DIR}/${domain}.key ${DEFAULT_NGINX_SSL_DIR}/
systemctl reload nginx
EOF
    chmod +x /usr/local/bin/ssl-update-${domain}.sh

    judge "自动续期设置"
}

main() {
    echo -e "${GreenBG}========== Nginx + ACME SSL 一键部署（通用版） ==========${Font}"
    is_root
    check_system
    parse_args "$@"
    install_dependency
    install_acme
    apply_ssl

    if [[ "$deploy_mode" == "static" ]]; then
        config_nginx_static
    else
        config_nginx_proxy
    fi

    setup_renew

    echo -e "\n${GreenBG}===================== 部署完成 =====================${Font}"
    echo -e "${OK} 域名: ${Green}https://${domain}${Font}"
    if [[ "$deploy_mode" == "static" ]]; then
        echo -e "${OK} 模式: ${Green}静态站点${Font}"
        echo -e "网站目录: ${Green}/var/www/${domain}${Font}"
    else
        echo -e "${OK} 反向代理目标: ${Green}http://${proxy_target}${Font}"
    fi
    echo -e "证书目录: ${Green}${DEFAULT_SSL_DIR}${Font}"
    echo -e "Nginx 配置: ${Green}/etc/nginx/conf.d/${domain}.conf${Font}"
    echo -e "手动续期脚本: ${Green}/usr/local/bin/ssl-update-${domain}.sh${Font}"
    echo -e "\n请访问测试： ${Green}https://${domain}${Font}"
    echo -e "${GreenBG}===================================================${Font}"
}

main "$@"
