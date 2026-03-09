# cdn-ip-ban

使用 **ipset + iptables** 封锁主流 CDN（Cloudflare / Fastly / Akamai）的全部 IP，阻断入站和出站流量。

Block all IPs from major CDN providers (Cloudflare / Fastly / Akamai) using **ipset + iptables**, dropping both inbound and outbound traffic.

> 适用系统 / Tested on: Debian 12 · 需要 root 权限 / Requires root

---

## 一键安装 / Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/pursork/gcp-free/main/install.sh | sudo bash
```

默认封锁全部三家 CDN 的 IPv4 + IPv6。
Blocks all three CDN providers (IPv4 + IPv6) by default.

**只封锁 Cloudflare：**
```bash
curl -fsSL https://raw.githubusercontent.com/pursork/gcp-free/main/install.sh | sudo bash -s -- --provider=cloudflare
```

**跳过 IPv6 封锁：**
```bash
curl -fsSL https://raw.githubusercontent.com/pursork/gcp-free/main/install.sh | sudo bash -s -- --no-ipv6
```

---

## 命令 / Commands

```bash
sudo cdn-ip-ban status                           # 查看封锁状态 / Show status
sudo cdn-ip-ban update                           # 更新 IP 列表 / Refresh IP lists
sudo cdn-ip-ban uninstall                        # 卸载全部规则 / Remove all rules
sudo cdn-ip-ban uninstall --provider=fastly      # 只卸载 Fastly
sudo cdn-ip-ban install --provider=cloudflare    # 只封锁 Cloudflare（含 IPv6）
sudo cdn-ip-ban install --no-ipv6                # 只封锁 IPv4
```

---

## IP 列表来源 / IP List Sources

IP 列表由本仓库统一维护（[`lists/`](lists/)），GitHub Actions 每天自动从官方上游同步并提交变更。脚本优先使用仓库列表，不可用时自动回退到官方源。

IP lists are maintained in [`lists/`](lists/) and auto-synced daily from official upstreams via GitHub Actions. The script uses repo lists as primary source and falls back to official CDN URLs if unavailable.

| Provider   | 格式        | 官方上游 / Official Upstream |
|------------|-------------|------------------------------|
| Cloudflare | 纯文本/text | https://www.cloudflare.com/ips-v4 · /ips-v6 |
| Fastly     | JSON        | https://api.fastly.com/public-ip-list |
| Akamai     | 纯文本/text | [platformbuilds/Akamai-ASN-and-IPs-List](https://github.com/platformbuilds/Akamai-ASN-and-IPs-List) |

---

## 如何为本项目做出贡献：添加新 CDN 来源 / Contributing: Add a New CDN Provider

### 第一步：确认 IP 是否属于 CDN / Step 1: Verify an IP belongs to a CDN

**Cloudflare**
```bash
# 访问任意 Cloudflare 站点的 /cdn-cgi/trace，返回结果含 fl=（数据中心）和 ip=（你的 IP）
curl -s https://cloudflare.com/cdn-cgi/trace
# 或直接查询 1.1.1.1
curl -s https://1.1.1.1/cdn-cgi/trace
# 对比 Cloudflare 官方 IP 列表
curl -s https://www.cloudflare.com/ips-v4
```

**Fastly**
```bash
# Fastly 在响应头中注入 X-Served-By 和 X-Cache，可用 -I 检查
curl -sI https://www.fastly.com | grep -i "x-served-by\|x-cache"
# 对比官方 IP 列表（JSON 格式）
curl -s https://api.fastly.com/public-ip-list | jq '.addresses[]'
```

**Akamai**
```bash
# Akamai 响应头通常含 X-Check-Cacheable 或 AkamaiGHost
curl -sI https://www.akamai.com | grep -i "akamai\|x-check"
# 通过反向 DNS 判断（Akamai 节点 PTR 记录通常含 akamai.net / akamaiedge.net）
dig -x <IP>
```

**通用方法 / General Methods**
```bash
# ASN / 组织信息查询（最直接）
curl -s https://ipinfo.io/<IP> | jq '{org, asn}'
# 或用 whois
whois <IP> | grep -iE "org|netname|descr|owner"
# 反向 DNS
dig -x <IP> +short
```

> 常见 ASN 参考：Cloudflare = AS13335，Fastly = AS54113，Akamai = AS20940 / AS16625

### 第二步：提 PR / Step 2: Open a PR

在 [`providers/`](providers/) 目录下新建 `.conf` 文件，格式如下：

```bash
# providers/example.conf
PROVIDER_NAME="Example CDN"
PROVIDER_FORMAT="text"          # text | fastly_json
PROVIDER_IPV4_URL="https://example.com/ips-v4.txt"
PROVIDER_IPV6_URL="https://example.com/ips-v6.txt"
```
请在PR中给出为何要阻断该ip/该ip属于付费cdn的证据。

PR会人工审核并合并，可以参考PR的模板。

PR 提交时会自动加载模板，要求提供 IP 归属证明并确认无重复。合并后 GitHub Actions 自动更新 `lists/`，无需手动操作。

When opening a PR, a template will guide you to provide ownership evidence and confirm no duplicates. After merge, GitHub Actions updates `lists/` automatically.

---

## 工作原理 / How It Works

1. 从上述来源下载各 CDN 最新 IP 列表（IPv4 + IPv6）
2. 写入 ipset（`hash:net`）
3. 在 iptables / ip6tables 的 `INPUT` 和 `OUTPUT` 链添加 DROP 规则
4. 规则持久化到 `/etc/iptables/rules.v4`，重启后自动恢复

---

1. Downloads latest IP lists from the sources above (IPv4 + IPv6)
2. Loads them into ipsets (`hash:net`)
3. Adds DROP rules to iptables/ip6tables `INPUT` and `OUTPUT` chains
4. Persists rules to `/etc/iptables/rules.v4` for automatic restore on reboot

---

## 注意 / Note

封锁后，这些 CDN 所承载的网站（Cloudflare Pages、npm CDN、GitHub Assets 等）将无法访问。如需访问，请自行配置代理工具（如 Xray、sing-box）进行流量分流，再卸载或调整封锁规则。

After blocking, websites hosted on these CDNs will be unreachable. Configure your own proxy tool (e.g. Xray, sing-box) to route around the blocks if needed.

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=pursork/gcp-free&type=Date)](https://star-history.com/#pursork/gcp-free&Date)
