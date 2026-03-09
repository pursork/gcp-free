## PR 类型 / PR Type

- [ ] 新增 CDN 来源 / New CDN provider
- [ ] 更新已有来源 URL / Update existing provider URL
- [ ] 其他 / Other (bug fix, doc, etc.)

---

## 新增 CDN 来源 / New CDN Provider（如适用 / if applicable）

### 1. 提供者名称与官方 IP 列表地址 / Provider name and official IP list URL

- **名称 / Name:**
- **IPv4 列表 URL / IPv4 list URL:**
- **IPv6 列表 URL / IPv6 list URL:**（如无填 N/A）

### 2. 证明该 IP 段属于该 CDN / Evidence that these IPs belong to this CDN

> 请至少提供以下一种证明，粘贴命令输出或截图。
> Provide at least one of the following. Paste command output or screenshot.

**ASN 查询 / ASN lookup**（推荐 / recommended）
```
# curl -s https://ipinfo.io/<sample_IP> 的输出
# Output of: curl -s https://ipinfo.io/<sample_IP>
```

**Whois / 反向 DNS / Reverse DNS**
```
# whois <sample_IP> 或 dig -x <sample_IP> 的输出
```

**CDN 自身的 trace / 探针端点 / CDN trace endpoint**（如有 / if available）
```
# 例如 Cloudflare: curl https://cloudflare.com/cdn-cgi/trace
```

**官方文档链接 / Official documentation link**（如有 / if available）

### 3. 去重确认 / Duplicate check

- [ ] 我已检查 [`lists/`](../lists/)，该 CDN 的 IP 段尚未被收录
      I have checked [`lists/`](../lists/) — this CDN's IP ranges are not already included
- [ ] 新增的 `providers/*.conf` 文件名与现有文件不重复
      The new `providers/*.conf` filename does not conflict with existing files

### 4. 格式检查 / Format checklist

- [ ] `.conf` 文件已放在 `providers/` 目录
- [ ] 包含 `PROVIDER_NAME`、`PROVIDER_FORMAT`、`PROVIDER_IPV4_URL` 字段
- [ ] `PROVIDER_FORMAT` 值为 `text` 或 `fastly_json`
- [ ] 已在本地运行 `bash scripts/update-lists.sh <slug>` 验证可正常抓取（可选但推荐）
      Optionally ran `bash scripts/update-lists.sh <slug>` locally to verify it fetches correctly

---

## 其他说明 / Additional Notes

<!-- 其他需要说明的内容 / Anything else reviewers should know -->