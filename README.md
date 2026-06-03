**Nginx + Let’s Encrypt 一键部署脚本使用指南**

以下是针对 `/opt/scripts/nginx-acme.sh` 脚本的完整使用说明，适合团队成员或后续维护人员参考。

------

### 1. 脚本基本信息

| 项目     | 内容                                                         |
| :------- | :----------------------------------------------------------- |
| 脚本路径 | `/opt/scripts/nginx-acme.sh`                                 |
| 支持系统 | Oracle Linux 8/9、CentOS 8/9、Rocky Linux、AlmaLinux、Debian 10+、Ubuntu 20.04+ |
| 功能     | 自动申请 Let’s Encrypt 证书 + 配置 Nginx HTTPS 反向代理/静态站点 + 设置自动续期 |

------

### 2. 脚本执行命令

#### 基本语法

```bash
# 反代模式
bash /opt/scripts/nginx-acme.sh <域名> <反向代理目标> [邮箱]

# 静态站点模式
bash /opt/scripts/nginx-acme.sh <域名> static [邮箱]
```

#### 参数说明

| 参数             | 是否必须 | 说明                                        | 示例                                 |
| :--------------- | :------- | :------------------------------------------ | :----------------------------------- |
| `<域名>`         | **必须** | 已正确解析到本服务器的域名                  | `web.myapp.com`                      |
| `<反向代理目标>` | **必须** | 后端服务地址，格式为 `IP:端口`              | `127.0.0.1:8888` 或 `localhost:3000` |
| `[邮箱]`         | 可选     | Let’s Encrypt 注册邮箱（默认 `admin@域名`） | `admin@myapp.com`                    |

#### 常用执行示例

```bash
# 最常用写法
bash /opt/scripts/nginx-acme.sh web.myapp.com 127.0.0.1:8888
bash /opt/scripts/nginx-acme.sh web.myapp.com static

# 指定邮箱
bash /opt/scripts/nginx-acme.sh web.myapp.com 127.0.0.1:8888 admin@myapp.com
bash /opt/scripts/nginx-acme.sh web.myapp.com static admin@myapp.com
```

### 3. 执行后生成的文件

脚本执行成功后，会生成以下文件：

| 文件/目录                             | 说明                                    |
| :------------------------------------ | :-------------------------------------- |
| `/etc/nginx/conf.d/<域名>.conf`       | Nginx 站点配置（包含 HTTPS + 反向代理） |
| `/data/ssl/<域名>.crt`                | 证书文件（原始）                        |
| `/data/ssl/<域名>.key`                | 私钥文件（原始）                        |
| `/etc/nginx/ssl/<域名>.crt`           | Nginx 实际使用的证书（脚本自动复制）    |
| `/etc/nginx/ssl/<域名>.key`           | Nginx 实际使用的私钥（脚本自动复制）    |
| `/usr/local/bin/ssl-update-<域名>.sh` | 手动续期脚本                            |

------

### 4. 新增反向代理（推荐流程）

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

# 2. 删除 Nginx 使用的证书（可选，建议保留一段时间）
rm -f /etc/nginx/ssl/<域名>.crt
rm -f /etc/nginx/ssl/<域名>.key

# 3. 删除原始证书和私钥（可选）
rm -f /data/ssl/<域名>.crt
rm -f /data/ssl/<域名>.key

# 4. 删除手动续期脚本
rm -f /usr/local/bin/ssl-update-<域名>.sh

# 5. 重载 Nginx
nginx -t && systemctl reload nginx
```

#### 一键删除脚本示例（谨慎使用）

你可以创建一个辅助删除脚本：

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
rm -f /data/ssl/${DOMAIN}.*
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
- **备份建议**：定期备份 `/data/ssl/` 和 `/etc/nginx/conf.d/` 目录。
