**Nginx + Let’s Encrypt 一键部署脚本使用指南**

`nginx-acme.sh` **v2.1.0**：自动申请 Let’s Encrypt 证书、配置 Nginx HTTPS（反代 / 静态站点 / Cloudflare 已代理反代）、设置自动续期。

**v2.1.0 起，HTTP-01 改用 webroot，申请与续期都不再停止 Nginx。** 旧版 `--standalone` 会占用 80 端口，续期必须停站，这是证书续期失败的根因。

------

### 1. 脚本基本信息

| 项目     | 内容                                                         |
| :------- | :----------------------------------------------------------- |
| 版本     | `2.1.0`                                                      |
| 脚本路径 | `nginx-acme.sh`（部署后建议放到 `/opt/scripts/nginx-acme.sh`） |
| 支持系统 | Oracle Linux 8/9、CentOS 8/9、Rocky Linux、AlmaLinux、Debian 10+、Ubuntu 20.04+ |
| 功能     | 自动申请 Let’s Encrypt 证书 + 配置 Nginx HTTPS 反代/静态站点/Cloudflare 已代理反代 + 设置自动续期（不停 Nginx） |

------

### 2. 脚本执行命令

#### 基本语法

```bash
# 反代模式（HTTP-01 webroot，不停 Nginx）
bash /opt/scripts/nginx-acme.sh <域名> <反向代理目标> [邮箱]

# 静态站点模式（HTTP-01 webroot，不停 Nginx）
bash /opt/scripts/nginx-acme.sh <域名> static [邮箱]

# Cloudflare 已代理反代模式（DNS-01 + 真实 IP 还原）
bash /opt/scripts/nginx-acme.sh <域名> cf_proxy <反向代理目标> <Cloudflare 凭证 ini 路径> [邮箱]
```

#### 参数说明

| 参数                  | 是否必须 | 说明                                           | 示例                                      |
| :-------------------- | :------- | :--------------------------------------------- | :---------------------------------------- |
| `<域名>`              | **必须** | 已解析到本机的域名。仅 `cf_proxy` 要求 Cloudflare 橙色云 | `www.example.com`                         |
| `<反向代理目标>`      | 反代/`cf_proxy` 必须 | 后端服务地址，格式为 `IP:端口`                  | `127.0.0.1:8888` 或 `localhost:3000`      |
| `<Cloudflare 凭证 ini 路径>` | 仅 `cf_proxy` 必须 | `dns_cloudflare_api_token` 或 `CF_Token` 凭证文件 | `/root/.secrets/cf.ini`                   |
| `[邮箱]`              | 可选     | Let’s Encrypt 注册邮箱（默认 `admin@域名`）     | `admin@myapp.com`                         |

#### 常用执行示例

```bash
# 反代模式
bash /opt/scripts/nginx-acme.sh web.myapp.com 127.0.0.1:8888

# 静态站点
bash /opt/scripts/nginx-acme.sh web.myapp.com static

# Cloudflare 已代理模式（cf_proxy）
bash /opt/scripts/nginx-acme.sh web.myapp.com cf_proxy 127.0.0.1:8080 /root/.secrets/cf.ini

# 指定邮箱
bash /opt/scripts/nginx-acme.sh web.myapp.com cf_proxy 127.0.0.1:8080 /root/.secrets/cf.ini admin@myapp.com
```

### 3. 执行后生成的文件

| 文件/目录                             | 说明                                    |
| :------------------------------------ | :-------------------------------------- |
| `/etc/nginx/conf.d/<域名>.conf`       | Nginx 站点配置（80 端口含 ACME webroot location） |
| `/etc/nginx/ssl/<域名>.crt`           | 证书文件                                |
| `/etc/nginx/ssl/<域名>.key`           | 私钥文件                                |
| `/var/www/<域名>/.well-known/acme-challenge/` | HTTP-01 挑战目录（proxy/static） |
| `/usr/local/bin/ssl-update-<域名>.sh` | 手动续期脚本（**不停 Nginx**）          |

---

### 4. 反向代理（推荐流程）

1. **确保域名 A/AAAA 已解析**到服务器公网 IP，且 80 端口对 Let’s Encrypt 可达。

2. **执行部署命令**：

   ```bash
   bash /opt/scripts/nginx-acme.sh web.myapp.com 127.0.0.1:8080
   ```

3. **验证访问**：

   ```bash
   curl -I https://web.myapp.com
   ```

脚本会先写入仅 HTTP 的 ACME 挑战 vhost（Nginx 保持运行）→ `acme.sh --issue --webroot` → 安装证书并写出完整 HTTPS 配置。

------

### 5. Cloudflare 已代理模式（cf_proxy）

当域名使用 **Cloudflare 已代理**（橙色云）时，HTTP 流量经过 Cloudflare 网络，源站 80 端口无需对外暴露。此模式使用 **DNS-01 验证**申请证书，并自动还原客户端真实 IP。

#### 前置条件

1. **域名 DNS 托管到 Cloudflare**，且在 Cloudflare Dashboard 开启代理（DNS 记录状态为橙色云图标）
2. **创建 Cloudflare API Token**：
   - Dashboard → 右上角头像 → My Profile → API Tokens → Create Token
   - 选择模板：Edit zone DNS（或自定义）
   - 权限选择 **Zone - DNS - Edit**，作用域选你的域名
   - 复制 Token（只会显示一次）
3. **本地创建凭证文件**（示例路径 `/root/.secrets/cf.ini`。部署成功后，确认续期正常即可删除此文件）：

   ```bash
   sudo mkdir -p /root/.secrets
   sudo tee /root/.secrets/cf.ini << 'EOF'
   dns_cloudflare_api_token = 你复制的Token
   EOF
   sudo chmod 600 /root/.secrets/cf.ini
   ```

   也支持 acme.sh 格式：`CF_Token=你复制的Token`

#### 部署步骤

```bash
bash /opt/scripts/nginx-acme.sh yourdomain.com cf_proxy 127.0.0.1:3000 /root/.secrets/cf.ini
```

- 第 1 个参数：Cloudflare 已代理的域名
- 第 2 个参数：`cf_proxy`
- 第 3 个参数：反向代理目标（如 `127.0.0.1:3000`）
- 第 4 个参数：Cloudflare 凭证文件路径
- 第 5 个参数（可选）：邮箱，默认 `admin@域名`

**参数顺序固定，不要对调。** 第 3 个参数是反代目标，不是邮箱。

#### 与普通反代模式的区别

| 项目           | 普通反代 / 静态站点         | Cloudflare 已代理模式              |
| :------------- | :-------------------------- | :--------------------------------- |
| 证书验证方式   | HTTP-01 webroot（需 80 端口可达，**不停 Nginx**） | DNS-01（无需开放 80 端口）         |
| 客户端真实 IP  | 直连为真实 IP               | 自动还原（通过 `CF-Connecting-IP`） |
| 协议头传递     | `X-Forwarded-Proto $scheme` | `X-Forwarded-Proto $http_x_forwarded_proto` |

------

### 6. 证书续期（不停 Nginx）

acme.sh 会安装 cron。到期前会用 **webroot 或 DNS-01** 续期，然后 `--reloadcmd "systemctl reload nginx"`。

手动立即续期：

```bash
bash /usr/local/bin/ssl-update-<域名>.sh
```

该脚本**不会** `systemctl stop nginx`。

#### 把旧版 standalone 证书迁到 webroot

若域名当初用旧脚本（`--standalone`）签发，cron 仍会尝试独占 80 端口。任选其一：

1. **重新跑一遍新脚本**（证书已存在时不会重复签发，只会改验证方式并重写 Nginx 80 端口 ACME location）：

   ```bash
   bash /opt/scripts/nginx-acme.sh <域名> <原模式参数...>
   ```

2. **手工迁移**（不重写业务 vhost 时）：

   ```bash
   # 1. 80 端口 server 里、return 301 之前加入：
   # location ^~ /.well-known/acme-challenge/ { root /var/www/<域名>; }
   mkdir -p /var/www/<域名>/.well-known/acme-challenge
   nginx -t && systemctl reload nginx

   # 2. 把 acme.sh 配置从 standalone 改成 webroot
   sed -i "s#Le_Webroot=.*#Le_Webroot='/var/www/<域名>'#g" \
     /root/.acme.sh/<域名>_ecc/<域名>.conf
   ```

------

### 7. 查看与排查

```bash
ls /etc/nginx/conf.d/*.conf
openssl x509 -in /etc/nginx/ssl/<域名>.crt -noout -dates
nginx -t
tail -f /var/log/nginx/error.log
tail -f /var/log/acme-cron.log
```

------

### 8. 常见问题处理

| 问题现象        | 可能原因                 | 解决方法                                        |
| :-------------- | :----------------------- | :---------------------------------------------- |
| 证书申请失败    | 域名未解析或 80 端口不通 | 检查 DNS 解析 + 开放 80 端口；`cf_proxy` 则检查 CF Token |
| 续期失败 / 需要停 Nginx | 仍在使用旧版 standalone | 按第 6 节迁到 webroot；确认 80 端口有 ACME location |
| ACME 403        | SELinux 拦截 webroot     | `restorecon -Rv /var/www/<域名>`                |
| Nginx 启动失败  | 证书路径或权限问题       | 检查 `/etc/nginx/ssl/` 目录权限                 |
| 502 Bad Gateway | SELinux 拦截             | 执行 `setsebool -P httpd_can_network_connect 1` |
| 反代不生效      | Nginx 配置未重载         | 执行 `systemctl reload nginx`                   |
| `proxy_set_header` 参数数量不对 | heredoc 把 `$host` 吃空 | 脚本内必须用 `\$host`（单反斜杠）               |

------

### 9. 删除某个域名配置

```bash
rm -f /etc/nginx/conf.d/<域名>.conf
rm -f /etc/nginx/ssl/<域名>.crt /etc/nginx/ssl/<域名>.key
rm -f /usr/local/bin/ssl-update-<域名>.sh
nginx -t && systemctl reload nginx
```

如需同时吊销 acme.sh 侧记录：

```bash
/root/.acme.sh/acme.sh --remove -d <域名> --ecc
```

> **注意**：删除操作不可逆，建议先备份相关文件。

### 10. 日常维护建议

- **自动续期**：脚本已通过 `acme.sh` 设置 cron，申请/续期均不停 Nginx。
- **新增域名**：直接使用脚本命令即可完成全流程。
- **证书到期前**：可提前执行手动续期脚本进行验证。
- **备份建议**：定期备份 `/etc/nginx/ssl/` 和 `/etc/nginx/conf.d/` 目录。
