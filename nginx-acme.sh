#!/bin/bash

# =============================================
#   Nginx + ACME SSL 一键部署脚本（通用版）
#   支持 Oracle Linux / CentOS / Debian / Ubuntu
#   支持自定义反向代理目标 + 静态站点 + Cloudflare 已代理
#   HTTP-01 使用 webroot，申请/续期均不停 Nginx
# =============================================

VERSION="2.1.0"

Green="\033[32m"
Red="\033[31m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

# 默认值
DEFAULT_SSL_DIR="/etc/nginx/ssl"
DEFAULT_NGINX_SSL_DIR="/etc/nginx/ssl"
DEFAULT_EMAIL_PREFIX="admin@"
ACME_HOME="${HOME}/.acme.sh"
ACME_BIN="${ACME_HOME}/acme.sh"

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
    echo -e "nginx-acme.sh ${VERSION}"
    echo -e "用法: $0 <域名> <模式> [邮箱]"
    echo -e ""
    echo -e "模式说明:"
    echo -e "  <反代目标>       反代模式：格式 IP:端口 或 localhost:端口（HTTP-01 webroot，不停 Nginx）"
    echo -e "  static           静态站点模式（HTTP-01 webroot，不停 Nginx）"
    echo -e "  cf_proxy         Cloudflare 已代理反代（DNS-01 + 真实IP还原）"
    echo -e ""
    echo -e "示例:"
    echo -e "  $0 hermesweb.shipaiagent.ccwu.cc 127.0.0.1:8648"
    echo -e "  $0 shipaiagent.ccwu.cc static"
    echo -e "  $0 yourdomain.com cf_proxy 127.0.0.1:3000 /root/.secrets/cf.ini"
    echo -e "${GreenBG}===================================================${Font}"
    exit 1
}

# Cloudflare 已代理模式：验证 CF 凭证文件存在且模式正确
check_cf_credentials() {
    local cf_ini="$1"
    if [[ -z "$cf_ini" ]]; then
        echo -e "${Error} cf_proxy 模式需要 Cloudflare 凭证文件路径（第 4 个参数）" && exit 1
    fi
    if [[ ! -f "$cf_ini" ]]; then
        echo -e "${Error} Cloudflare 凭证文件不存在: ${cf_ini}" && exit 1
    fi
    if ! grep -qE '^\s*(dns_cloudflare_api_token|CF_Token)\s*=' "$cf_ini" 2>/dev/null; then
        echo -e "${Error} 凭证文件缺少 dns_cloudflare_api_token 或 CF_Token 字段" && exit 1
    fi
    chmod 600 "$cf_ini" || true
}

# 参数解析
parse_args() {
    if [[ $# -lt 1 ]]; then
        show_usage
    fi
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
    fi
    if [[ "$1" == "-V" || "$1" == "--version" ]]; then
        echo "nginx-acme.sh ${VERSION}"
        exit 0
    fi
    if [[ $# -lt 2 ]]; then
        show_usage
    fi

    domain="$1"
    mode="$2"
    email="${3:-${DEFAULT_EMAIL_PREFIX}${domain}}"
    cf_credentials=""
    ACME_WEBROOT="/var/www/${domain}"

    # 简单校验域名
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+[.][a-zA-Z]{2,}$ ]]; then
        echo -e "${Error} 域名格式不正确: $domain" && exit 1
    fi

    if [[ "$mode" == "static" ]]; then
        deploy_mode="static"
        echo -e "${Info} 域名: ${Green}${domain}${Font}"
        echo -e "${Info} 模式: ${Green}静态站点${Font}"
        echo -e "${Info} 邮箱: ${Green}${email}${Font}"
        echo -e "${Info} 验证: ${Green}HTTP-01 webroot（不停 Nginx）${Font}"
    elif [[ "$mode" == "cf_proxy" ]]; then
        deploy_mode="cf_proxy"
        # cf_proxy 固定参数顺序：第3=proxy_target，第4=cf_ini，第5=email（可选）
        # 修正：第 3 个参数不是邮箱，必须还原为默认值
        if [[ -n "${5:-}" ]]; then
            email="$5"
        else
            email="${DEFAULT_EMAIL_PREFIX}${domain}"
        fi

        if [[ -z "${3:-}" ]]; then
            echo -e "${Error} cf_proxy 模式缺少反向代理目标（第 3 个参数）" && exit 1
        fi
        if [[ -z "${4:-}" ]]; then
            echo -e "${Error} cf_proxy 模式缺少 Cloudflare 凭证文件（第 4 个参数）" && exit 1
        fi
        proxy_target="$3"
        cf_credentials="$4"

        if [[ ! "$proxy_target" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
            echo -e "${Error} cf_proxy 反向代理目标格式不正确（应为 IP:端口）: ${proxy_target}" && exit 1
        fi
        echo -e "${Info} 域名: ${Green}${domain}${Font}"
        echo -e "${Info} 模式: ${Green}Cloudflare 已代理反代${Font}"
        echo -e "${Info} 反向代理目标: ${Green}http://${proxy_target}${Font}"
        echo -e "${Info} 邮箱: ${Green}${email}${Font}"
        echo -e "${Info} Cloudflare 凭证: ${Green}${cf_credentials}${Font}"
        echo -e "${Info} 验证: ${Green}DNS-01 dns_cf（不停 Nginx）${Font}"
        check_cf_credentials "$cf_credentials"
    else
        deploy_mode="proxy"
        proxy_target="$mode"
        if [[ ! "$proxy_target" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
            echo -e "${Error} 反向代理目标格式不正确（应为 IP:端口 或 localhost:端口）: $proxy_target" && exit 1
        fi
        echo -e "${Info} 域名: ${Green}${domain}${Font}"
        echo -e "${Info} 反向代理目标: ${Green}http://${proxy_target}${Font}"
        echo -e "${Info} 邮箱: ${Green}${email}${Font}"
        echo -e "${Info} 验证: ${Green}HTTP-01 webroot（不停 Nginx）${Font}"
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
    if [[ -x "${ACME_BIN}" ]]; then
        echo -e "${Info} 检测到已安装 acme.sh，跳过安装"
        return 0
    fi
    echo -e "${Info} 安装 acme.sh..."
    curl -s https://get.acme.sh | sh -s email="${email}"
    judge "acme.sh 安装"
    ACME_BIN="${HOME}/.acme.sh/acme.sh"
}

# Cloudflare 已代理：真实 IP 还原地址段（官方 v2，含 IPv6）
CF_REAL_IP_CIDRS=(
"173.245.48.0/20" "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22"
"141.101.64.0/18" "108.162.192.0/18" "190.93.240.0/20" "188.114.96.0/20"
"197.234.240.0/22" "198.41.128.0/17" "162.158.0.0/15"
"104.16.0.0/13" "104.24.0.0/14" "172.64.0.0/13" "131.0.72.0/22"
"2400:cb00::/36" "2606:4700::/32" "2803:f800::/32" "2405:b500::/32"
"2405:8100::/32" "2a06:98c0::/29" "2c7f:2c00::/29"
)

# 设置 Cloudflare DNS API 凭证（用于 DNS-01）
setup_cf_dns_api() {
    echo -e "${Info} 读取 Cloudflare DNS API 凭证（${cf_credentials}）..."
    "${ACME_BIN}" --set-default-ca --server letsencrypt

    # 支持 certbot 格式（dns_cloudflare_api_token）和 acme.sh 格式（CF_Token）
    local cf_token=""
    if [[ -f "$cf_credentials" ]]; then
        cf_token=$(grep -E '^\s*CF_Token\s*=' "$cf_credentials" 2>/dev/null | head -n1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^["'\'']//;s/["'\'']$//')
        if [[ -z "$cf_token" ]]; then
            cf_token=$(grep -E '^\s*dns_cloudflare_api_token\s*=' "$cf_credentials" 2>/dev/null | head -n1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^["'\'']//;s/["'\'']$//')
        fi
    fi

    if [[ -z "$cf_token" ]]; then
        echo -e "${Error} 无法从凭证文件中提取 Cloudflare API Token" && exit 1
    fi

    export CF_Token="$cf_token"
    echo -e "${OK} Cloudflare DNS API 凭证已配置"
}

# HTTP-01 webroot：准备挑战目录（SELinux 友好）
prepare_webroot() {
    mkdir -p "${ACME_WEBROOT}/.well-known/acme-challenge"
    chmod -R a+rX "${ACME_WEBROOT}"
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -Rv "${ACME_WEBROOT}" >/dev/null 2>&1 || true
    fi
}

# 80 端口 ACME 挑战 location（必须写在 return 301 之前）
http_acme_server_block() {
    cat << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    location ^~ /.well-known/acme-challenge/ {
        root ${ACME_WEBROOT};
        default_type text/plain;
        allow all;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF
}

# 申请证书前写入仅 HTTP 的挑战 vhost，Nginx 保持运行
write_http_challenge_vhost() {
    echo -e "${Info} 写入 HTTP-01 webroot 挑战配置（不停 Nginx）..."
    http_acme_server_block > "/etc/nginx/conf.d/${domain}.conf"
    systemctl enable nginx --now >/dev/null 2>&1 || true
    nginx -t
    judge "Nginx HTTP 挑战配置语法检查"
    systemctl reload nginx || systemctl restart nginx
    judge "Nginx 重载（HTTP 挑战）"
}

# 将旧版 standalone 续期方式切换为 webroot，避免 cron 再抢 80 端口
migrate_standalone_to_webroot() {
    local conf="${HOME}/.acme.sh/${domain}_ecc/${domain}.conf"
    [[ -f "$conf" ]] || return 0
    if grep -q "standalone" "$conf"; then
        echo -e "${Info} 检测到旧版 standalone 验证，已切换为 webroot"
        sed -i "s#Le_Webroot=.*#Le_Webroot='${ACME_WEBROOT}'#g" "$conf"
        # 清掉可能存在的停 Nginx 钩子，避免续期再 stop
        sed -i "s#Le_PreHook=.*#Le_PreHook=''#g" "$conf"
        sed -i "s#Le_PostHook=.*#Le_PostHook=''#g" "$conf"
    fi
}

cert_already_issued() {
    [[ -f "${HOME}/.acme.sh/${domain}_ecc/fullchain.cer" ]]
}

install_cert_to_nginx() {
    mkdir -p "${DEFAULT_SSL_DIR}"
    "${ACME_BIN}" --install-cert -d "${domain}" --ecc \
        --fullchain-file "${DEFAULT_SSL_DIR}/${domain}.crt" \
        --key-file "${DEFAULT_SSL_DIR}/${domain}.key" \
        --reloadcmd "systemctl reload nginx"
    local rc=$?
    chmod 600 "${DEFAULT_SSL_DIR}/${domain}.key" 2>/dev/null || true
    chmod 644 "${DEFAULT_SSL_DIR}/${domain}.crt" 2>/dev/null || true
    return $rc
}

# 申请证书
apply_ssl() {
    echo -e "${Info} 正在申请 Let's Encrypt 证书（${domain}）..."
    local issue_rc=0

    if [[ "$deploy_mode" == "cf_proxy" ]]; then
        echo -e "${Info} 使用 Cloudflare DNS-01 验证申请证书..."
        setup_cf_dns_api
        if cert_already_issued; then
            echo -e "${Info} 证书已存在，跳过重新签发（续期走 acme.sh cron）"
            issue_rc=0
        else
            "${ACME_BIN}" --issue \
                --dns dns_cf \
                -d "${domain}" -k ec-256
            issue_rc=$?
        fi
    else
        prepare_webroot
        write_http_challenge_vhost
        migrate_standalone_to_webroot
        "${ACME_BIN}" --set-default-ca --server letsencrypt
        if cert_already_issued; then
            echo -e "${Info} 证书已存在，跳过重新签发；续期将使用 webroot"
            issue_rc=0
        else
            echo -e "${Info} 使用 HTTP-01 webroot 验证申请证书（Nginx 保持运行）..."
            "${ACME_BIN}" --issue --webroot "${ACME_WEBROOT}" -d "${domain}" -k ec-256
            issue_rc=$?
        fi
    fi

    if [ $issue_rc -eq 0 ]; then
        echo -e "${OK} SSL 证书申请/复用成功！"
        install_cert_to_nginx
        judge "证书安装"
    else
        echo -e "${Error} 证书申请失败！" && exit 1
    fi
}

# 配置 Nginx（反代模式）
config_nginx_proxy() {
    echo -e "${Info} 配置 Nginx 反向代理到 ${proxy_target}..."

    mkdir -p "${DEFAULT_NGINX_SSL_DIR}"
    prepare_webroot

    {
        http_acme_server_block
        cat << EOF

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
    } > "/etc/nginx/conf.d/${domain}.conf"

    nginx -t
    judge "Nginx 配置语法检查"

    if command -v setsebool >/dev/null 2>&1; then
        setsebool -P httpd_can_network_connect 1 >/dev/null 2>&1 || true
    fi

    systemctl enable nginx --now
    systemctl reload nginx || systemctl restart nginx
    judge "Nginx 启动/重载"
}

# 配置 Nginx（Cloudflare 已代理反代模式）
config_nginx_cf_proxy() {
    echo -e "${Info} 配置 Nginx（Cloudflare 已代理反代）..."

    if [[ -z "$proxy_target" ]]; then
        echo -e "${Error} cf_proxy 模式未提供 proxy_target" && exit 1
    fi

    mkdir -p "${DEFAULT_NGINX_SSL_DIR}"

    {
        http_acme_server_block
        cat << EOF

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

    # Cloudflare 真实 IP 还原
EOF
        for cidr in "${CF_REAL_IP_CIDRS[@]}"; do
            echo "    set_real_ip_from ${cidr};"
        done
        cat << EOF
    real_ip_header CF-Connecting-IP;

    location / {
        proxy_pass http://${proxy_target};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    } > "/etc/nginx/conf.d/${domain}.conf"

    nginx -t
    judge "Nginx 配置语法检查（cf_proxy）"

    if command -v setsebool >/dev/null 2>&1; then
        setsebool -P httpd_can_network_connect 1 >/dev/null 2>&1 || true
    fi

    systemctl enable nginx --now
    systemctl reload nginx || systemctl restart nginx
    judge "Nginx 启动/重载（cf_proxy）"
}

# 配置 Nginx（静态站点模式）
config_nginx_static() {
    echo -e "${Info} 配置 Nginx 静态站点..."

    mkdir -p "${DEFAULT_NGINX_SSL_DIR}"
    prepare_webroot

    if [[ ! -f "${ACME_WEBROOT}/index.html" ]]; then
        cat > "${ACME_WEBROOT}/index.html" << HTMLEOF
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
    fi

    if id opc >/dev/null 2>&1; then
        chown -R opc:opc "${ACME_WEBROOT}"
    elif id www-data >/dev/null 2>&1; then
        chown -R www-data:www-data "${ACME_WEBROOT}"
    elif id nginx >/dev/null 2>&1; then
        chown -R nginx:nginx "${ACME_WEBROOT}"
    fi

    {
        http_acme_server_block
        cat << EOF

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

    root ${ACME_WEBROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    } > "/etc/nginx/conf.d/${domain}.conf"

    nginx -t
    judge "Nginx 配置语法检查"

    systemctl enable nginx --now
    systemctl reload nginx || systemctl restart nginx
    judge "Nginx 启动/重载"
}

# 设置自动续期（webroot/dns，cron 不停 Nginx）
setup_renew() {
    echo -e "${Info} 设置证书自动续期..."
    "${ACME_BIN}" --install-cronjob
    "${ACME_BIN}" --upgrade --auto-upgrade

    cat > "/usr/local/bin/ssl-update-${domain}.sh" << EOF
#!/bin/bash
set -euo pipefail
export PATH="/root/.acme.sh:\$PATH"
/root/.acme.sh/acme.sh --cron --home "/root/.acme.sh" >> /var/log/acme-cron.log 2>&1
/root/.acme.sh/acme.sh --install-cert -d ${domain} --ecc \\
    --fullchain-file ${DEFAULT_SSL_DIR}/${domain}.crt \\
    --key-file ${DEFAULT_SSL_DIR}/${domain}.key \\
    --reloadcmd "systemctl reload nginx"
EOF
    chmod +x "/usr/local/bin/ssl-update-${domain}.sh"

    judge "自动续期设置"
}

main() {
    case "${1:-}" in
        -h|--help) show_usage ;;
        -V|--version) echo "nginx-acme.sh ${VERSION}"; exit 0 ;;
    esac
    echo -e "${GreenBG}========== Nginx + ACME SSL 一键部署 v${VERSION} ==========${Font}"
    is_root
    check_system
    parse_args "$@"
    install_dependency
    install_acme
    apply_ssl

    if [[ "$deploy_mode" == "static" ]]; then
        config_nginx_static
    elif [[ "$deploy_mode" == "cf_proxy" ]]; then
        config_nginx_cf_proxy
    else
        config_nginx_proxy
    fi

    setup_renew

    echo -e "\\n${GreenBG}===================== 部署完成 =====================${Font}"
    echo -e "${OK} 域名: ${Green}https://${domain}${Font}"
    if [[ "$deploy_mode" == "static" ]]; then
        echo -e "${OK} 模式: ${Green}静态站点${Font}"
        echo -e "网站目录: ${Green}${ACME_WEBROOT}${Font}"
    elif [[ "$deploy_mode" == "cf_proxy" ]]; then
        echo -e "${OK} 模式: ${Green}Cloudflare 已代理反代${Font}"
        echo -e "反向代理目标: ${Green}http://${proxy_target}${Font}"
        echo -e "Cloudflare 凭证: ${Green}${cf_credentials}${Font}"
    else
        echo -e "${OK} 模式: ${Green}反向代理${Font}"
        echo -e "反向代理目标: ${Green}http://${proxy_target}${Font}"
    fi
    echo -e "证书验证: ${Green}申请/续期均不停 Nginx${Font}"
    echo -e "证书目录: ${Green}${DEFAULT_SSL_DIR}${Font}"
    echo -e "Nginx 配置: ${Green}/etc/nginx/conf.d/${domain}.conf${Font}"
    echo -e "手动续期脚本: ${Green}/usr/local/bin/ssl-update-${domain}.sh${Font}"
    echo -e "\\n请访问测试： ${Green}https://${domain}${Font}"
    echo -e "${GreenBG}===================================================${Font}"
}

main "$@"
