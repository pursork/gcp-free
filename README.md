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

| Provider   | 格式   | 来源 / Source |
|------------|--------|---------------|
| Cloudflare | 纯文本 | https://www.cloudflare.com/ips-v4 · https://www.cloudflare.com/ips-v6 |
| Fastly     | JSON   | https://api.fastly.com/public-ip-list |
| Akamai     | 纯文本 | https://github.com/platformbuilds/Akamai-ASN-and-IPs-List |

Cloudflare 和 Fastly 的列表由官方维护；Akamai 列表来自社区整理的 ASN IP 聚合。

Cloudflare and Fastly lists are officially maintained. The Akamai list is community-aggregated from Akamai's ASN.

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
