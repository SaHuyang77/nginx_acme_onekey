**Nginx + Let’s Encrypt 一键部署脚本使用指南**

以下是针对 `nginx-acme.sh` 脚本的完整使用说明，适合团队成员或后续维护人员参考。

------

### 1. 脚本基本信息

| 项目     | 内容                                                         |
| :------- | :----------------------------------------------------------- |
| 脚本路径 | `nginx-acme.sh`                                 |
| 支持系统 | Oracle Linux 8/9、CentOS 8/9、Rocky Linux、AlmaLinux、Debian 10+、Ubuntu 20.04+ |
| 功能     | 自动申请 Let’s Encrypt 证书 + 配置 Nginx HTTPS 反代/静态站点/Cloudflare 已代理反代 + 设置自动续期 |

------

### 2. 脚本执行命令

#### 基本语法

```bash
# 反代模式
bash /opt/scripts/nginx-acme.sh <域名> <反向代理目标> [邮箱]

# 静态站点模式
bash /opt/scripts/nginx-acme.sh <域名> static [邮箱]

# Cloudflare 已代理反代模式（DNS-01 + 真实 IP 还原）
bash /opt/scripts/nginx-acme.sh <域名> cf_proxy <反向代理目标> <Cloudflare 凭证 ini 路径> [邮箱]
```

#### 参数说明

| 参数                  | 是否必须 | 说明                                           | 示例                                      |
| :-------------------- | :------- | :--------------------------------------------- | :---------------------------------------- |
| `<域名>`              | **必须** | 已托管到 Cloudflare 且开启代理（橙色云）的域名  | `www.example.com`                         |
| `<反向代理目标>`      | **必须** | 后端服务地址，格式为 `IP:端口`                  | `127.0.0.1:8888` 或 `localhost:3000`      |
| `<Cloudflare 凭证 ini 路径>` | **必须** | dns-cloudflare-api-token 凭证文件路径     | `/root/.secrets/cf.ini`                   |
| `[邮箱]`              | 可选     | Let’s Encrypt 注册邮箱（默认 `admin@域名`）     | `admin@myapp.com`                         |

#### 常用执行示例

```bash
# 反带模式
bash /opt/scripts/nginx-acme.sh web.myapp.com 127.0.0.1:8888
bash /opt/scripts/nginx-acme.sh web.myapp.com static

# Cloudflare 已代理模式（cf_proxy）
bash /opt/scripts/nginx-acme.sh web.myapp.com cf_proxy 127.0.0.1:8080 /root/.secrets/cf.ini

# 指定邮箱
bash /opt/scripts/nginx-acme.sh web.myapp.com cf_proxy 127.0.0.1:8080 /root/.secrets/cf.ini admin@myapp.com
```

### 3. 执行后生成的文件

脚本执行成功后，会生成以下文件：

| 文件/目录                             | 说明                                    |
| :------------------------------------ | :-------------------------------------- |
| `/etc/nginx/conf.d/<域名>.conf`       | Nginx 站点配置（包含 HTTPS + 反代）     |
| `/etc/nginx/ssl/<域名>.crt`           | 证书文件                                |
| `/etc/nginx/ssl/<域名>.key`           | 私钥文件                                |
| `/usr/local/bin/ssl-update-<域名>.sh` | 手动续期脚本                            |

---

### 4. 反向代理（推荐流程）

当需要为一个新域名配置 HTTPS 反代时，按以下步骤操作：

1. **确保域名已解析**到服务器 IP

2. **执行部署命令**：

   ```bash
   bash /opt/scripts/nginx-acme.sh 新域名 反代目标
   ```

   示例：

   ```bash
   bash /opt/scripts/nginx-acme.sh web.myapp.com 127.0.0.1:8080
   ```

3. **验证访问**：

   ```bash
   curl -I https://web.myapp.com
   ```

------

### 4.5. Cloudflare 已代理模式（cf_proxy）

当域名使用 **Cloudflare 已代理**（橙色云）时，HTTP 流量经过 Cloudflare 网络，源站 80 端口无需对外暴露。此模式使用 **DNS-01 验证**申请证书，并自动还原客户端真实 IP。

#### 前置条件

1. **域名 DNS 托管到 Cloudflare**，且在 Cloudflare Dashboard 开启代理（DNS 记录状态为橙色云图标）
2. **创建 Cloudflare API Token**：
   - Dashboard → 右上角头像 → My Profile → API Tokens → Create Token
   - 权限选择 **Zone - DNS - Edit**，作用域选你的域名
3. **本地创建凭证文件**（示例路径 `/root/.secrets/cf.ini`）：

   ```ini
   dns_cloudflare_api_token = 你的_API_Token
   ```

   ```bash
   chmod 600 /root/.secrets/cf.ini
   ```

#### 部署步骤

1. **确认域名已在 Cloudflare 开启代理**（橙色云）
2. **执行部署命令**：

   ```bash
   bash /opt/scripts/nginx-acme.sh yourdomain.com cf_proxy 127.0.0.1:3000 /root/.secrets/cf.ini
   ```

   - 第 1 个参数：Cloudflare 已代理的域名
   - 第 2 个参数：`cf_proxy`
   - 第 3 个参数：反向代理目标（如 `127.0.0.1:3000`）
   - 第 4 个参数：Cloudflare 凭证文件路径（如 `/root/.secrets/cf.ini`）
   - 第 5 个参数（可选）：邮箱，默认 `admin@域名`

3. **验证访问**：

   ```bash
   curl -I https://yourdomain.com
   ```

#### 与普通反代模式的区别

| 项目           | 普通反代模式                | Cloudflare 已代理模式              |
| :------------- | :-------------------------- | :--------------------------------- |
| 证书验证方式   | HTTP-01（需开放 80 端口）   | DNS-01（无需开放 80 端口）         |
| 客户端真实 IP  | 丢失（被 Cloudflare IP 替换） | 自动还原（通过 `CF-Connecting-IP`） |
| 协议头传递     | `X-Forwarded-Proto $scheme` | `X-Forwarded-Proto $http_x_forwarded_proto` |

#### 查看真实 IP

Nginx 配置中已启用 Cloudflare real_ip 还原：

```nginx
set_real_ip_from 173.245.48.0/20;
# ... 其他官方 CIDR
real_ip_header CF-Connecting-IP;
```

后端应用可直接读取 `X-Real-IP` 获取用户真实地址。

------

### 5. 手动续期证书

当需要立即续期某个域名的证书时，执行对应的手动续期脚本：

```bash
bash /usr/local/bin/ssl-update-<域名>.sh
```

示例：

```bash
bash /usr/local/bin/ssl-update-web.myapp.com.sh
```

该脚本会完成以下操作：

- 执行证书续期
- 更新 Nginx 使用的证书
- 重载 Nginx 配置

------

### 6. 查看与排查

#### 查看已部署的域名配置

```bash
ls /etc/nginx/conf.d/*.conf
```

#### 查看证书有效期

```bash
openssl x509 -in /etc/nginx/ssl/<域名>.crt -noout -dates
```

#### 查看 Nginx 配置是否正确

```bash
nginx -t
```

#### 查看 Nginx 错误日志

```bash
tail -f /var/log/nginx/error.log
```

#### 查看 [acme.sh](http://acme.sh/) 续期日志

```bash
tail -f /var/log/acme-cron.log
```

------

### 7. 常见问题处理

| 问题现象        | 可能原因                 | 解决方法                                        |
| :-------------- | :----------------------- | :---------------------------------------------- |
| 证书申请失败    | 域名未解析或 80 端口不通 | 检查 DNS 解析 + 开放 80 端口                    |
| Nginx 启动失败  | 证书路径或权限问题       | 检查 `/etc/nginx/ssl/` 目录权限                 |
| 502 Bad Gateway | SELinux 拦截             | 执行 `setsebool -P httpd_can_network_connect 1` |
| 反代不生效      | Nginx 配置未重载         | 执行 `systemctl reload nginx`                   |

------

### 8. 删除某个域名配置

当某个域名不再需要时，建议按以下步骤**干净删除**，避免残留配置导致问题。

#### 删除步骤

```bash
# 1. 删除 Nginx 配置文件
rm -f /etc/nginx/conf.d/<域名>.conf

# 2. 删除证书和私钥
rm -f /etc/nginx/ssl/<域名>.crt
rm -f /etc/nginx/ssl/<域名>.key

# 3. 删除手动续期脚本
rm -f /usr/local/bin/ssl-update-<域名>.sh

# 4. 重载 Nginx
nginx -t && systemctl reload nginx
```

#### 一键删除脚本

```bash
cat > /usr/local/bin/remove-domain.sh << 'EOF'
#!/bin/bash
DOMAIN=$1
if [ -z "$DOMAIN" ]; then
    echo "用法: $0 <域名>"
    exit 1
fi

echo "正在删除域名: $DOMAIN"
rm -f /etc/nginx/conf.d/${DOMAIN}.conf
rm -f /etc/nginx/ssl/${DOMAIN}.*
rm -f /usr/local/bin/ssl-update-${DOMAIN}.sh
nginx -t && systemctl reload nginx
echo "域名 $DOMAIN 已删除"
EOF

chmod +x /usr/local/bin/remove-domain.sh
```

使用方法：

```bash
bash /usr/local/bin/remove-domain.sh web.myapp.com
```

> **注意**：删除操作不可逆，建议先备份相关文件。

### 9. 日常维护建议

- **自动续期**：脚本已通过 `acme.sh` 设置 cron 任务，通常无需手动干预。
- **新增域名**：直接使用脚本命令即可完成全流程。
- **证书到期前**：可提前执行手动续期脚本进行验证。
- **备份建议**：定期备份 `/etc/nginx/ssl/` 和 `/etc/nginx/conf.d/` 目录。
