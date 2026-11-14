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

<details>
<summary><code><strong>飞行模式说明</strong></summary>

此模式用于 Cloudflare 开启橙云代理的域名。你仍然可以通过原本的 80 端口访问本机（如果 80 端口开放），但证书申请会使用 Cloudflare 的 DNS API 完成 challenge，而不是传统的 HTTP-01。其优势是：源站无需暴露 80 端口给 Let's Encrypt，更适合有防火墙或仅暴露 443 端口的场景。

</details>

#### 5.1 获取 Cloudflare API Token

1. 登录 Cloudflare 控制台：https://dash.cloudflare.com
2. 点击右上角头像 → **My Profile** → **API Tokens**。
3. 点击 **Create Token**，选择模板 **Edit zone DNS**。
4. 确认权限：
   - **Zone → DNS → Edit**
   - 作用域：**Specific** → 选择你的域名（或全部）。
5. 点击 **Continue to summary**，再 **Create Token**。
6. 复制生成的 Token（只显示一次，务必保存）。例如：

   ```bash
   dns_cloudflare_api_token = 0AbCdE...
   ```

> **安全提示**：Token 仅显示一次，不要将其发送到聊天、文档或代码仓库。可在本地创建一个只读文件。

#### 5.2 凭证文件格式

脚本期望从文件中读取 `dns_cloudflare_api_token`（优先）或 `CF_Token` 键。文件可使用 `ini` 格式，也支持注释（以 `#` 或 `;` 开头）。一个典型的 `cf.ini` 内容如下：

```ini
; Cloudflare API 令牌
dns_cloudflare_api_token = 0AbCdE...   # 你的实际 token
; 可选备用键：
; CF_Token = 0AbCdE...
```

建议：

- 权限 `600`（仅 owner 可读）：
  ```bash
  sudo chmod 600 /root/.secrets/cf.ini
  ```
- 使用 `sudo tee` 或 `cat` 写入，避免用纯文本复制粘贴到公共文档。

#### 5.3 执行部署命令

```bash
bash /opt/scripts/nginx-acme.sh yourdomain.com cf_proxy 127.0.0.1:3000 /root/.secrets/cf.ini
```

参数含义：

| 位置 | 含义 | 示例 |
|------|------|------|
| `<domain>` | 已在 Cloudflare 代理的域名 | `hermesweb.shipaiagent.ccwu.cc` |
| `cf_proxy` | 固定字符串，表示 Cloudflare 已代理反代模式 | `cf_proxy` |
| `<proxy_target>` | 后端反向代理服务地址 | `127.0.0.1:3000` |
| `<cf.ini>` | Cloudflare 凭证文件 | `/root/.secrets/cf.ini` |
| `[email]` | 可选，Let’s Encrypt 邮箱 | `admin@hermesweb.shipaiagent.ccwu.cc` |

注意：

- **第 3 个参数必须是反向代理目标，不是邮箱。** 若要指定邮箱，请把邮箱放到第 5 个位置（可选）。
- 如果你第一次运行，脚本会先安装或升级 `acme.sh`，并设置默认 CA 到 Let's Encrypt。

#### 5.4 脚本内部行为（DNS-01 验证）

当进入 `cf_proxy` 分支后，执行流程如下：

1. **解析并检查凭证文件**  
   读取 `${cf_credentials}` 文件，提取 `dns_cloudflare_api_token` 或 `CF_Token`。如果两者都缺失，脚本会退出并提示。

2. **安装/升级 acme.sh**  
   `acme.sh` 会安装到 `~/.acme.sh`，并设置默认 CA（Let's Encrypt）。

3. **准备 DNS-01 验证**  
   - 设置环境变量 `CF_Token`（如果 `cf.ini` 中存在 `CF_Token`）。
   - 执行：
     ```bash
     ~/.acme.sh/acme.sh --issue \
         --dns dns_cf \
         -d <domain> -k ec-256
     ```
   - `dns_cf` 是 acme.sh 的 Cloudflare DNS API 插件，它会根据 `CF_Token` 向 Cloudflare 创建一条 `_acme-challenge.<domain>` 的 TXT 记录。
   - acme.sh 会自动轮询该记录，确认解析后完成 challenge。

4. **签发证书**  
   - 签发 ECC-256 (`-k ec-256`) 证书。
   - 通过 `--install-cert` 将证书安装到：
     - `/etc/nginx/ssl/<domain>.crt`
     - `/etc/nginx/ssl/<domain>.key`

5. **生成 Nginx 配置**  
   - 80 端口监听 ACME challenge（`/.well-known/acme-challenge/`）。
   - 443 端口监听 HTTPS，并设置：
     - `ssl_certificate` 与 `ssl_certificate_key`。
     - `real_ip_header CF-Connecting-IP`，以及若干 Cloudflare 来源 IP 段。
     - WebSocket 路径：`/api/ws`, `/api/pty`, `/api/pub`。
     - 反向代理到 `<proxy_target>`。

6. **设置自动续期**  
   - 安装 cron 任务。
   - 生成 `/usr/local/bin/ssl-update-<domain>.sh` 脚本，命中时间后自动用 DNS-01 续期，并 `systemctl reload nginx`。

#### 5.5 验证部署结果

```bash
# 检查证书时间（应与签发时间一致，过期时间通常 90 天）
openssl x509 -in /etc/nginx/ssl/hermesweb.shipaiagent.ccwu.cc.crt -noout -dates

# 检查 nginx 配置
nginx -t

# 测试网站是否通过 Cloudflare 代理
curl -I https://hermesweb.shipaiagent.ccwu.cc

# 查看 acme.sh cron 日志
tail -f /var/log/acme-cron.log
```

#### 5.6 常见问题

| 问题 | 原因 | 解决 |
|---|---|---|
| `Cloudflare 凭证文件不存在` | `cf.ini` 未创建或路径错误 | 检查路径并创建文件 |
| `dns_cloudflare_api_token 未找到` | 文件格式错误或 Token 键名错 | 确认 `dns_cloudflare_api_token = <token>` 存在 |
| `Cloudflare API 403` | Token 权限不足或过期 | 重新生成 Token，给 Zone - DNS - Edit 权限 |
| `DNS-01 验证失败` | 域名未连接到 Cloudflare 或 DNS 未生效 | 确认域名在 Cloudflare 中，记录橙色云，刷新 DNS 缓存 |
| `nginx 启动失败` | 证书路径错或 `nginx -t` 失败 | 检查 `/etc/nginx/conf.d/` 配置与证书路径 |
| 续期时报 80 端口冲突 | 仍使用旧的 standalone 模式 | 重新运行脚本（新证书存在时会自动切换到 webroot/DNS-01）|

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
