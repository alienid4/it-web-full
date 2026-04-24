"""深度檢查建議動作知識庫 (v3.11.24.0)

每筆 entry 對一個「面向 + 具體問題關鍵字」，UI 會把 commands/risks/verify
渲染在 `建議動作` 下方 3 個子區塊。初版 10 條，後續可增量擴充。

結構:
    face      : 1~9 (對應 mod_troubleshoot.sh 的 [N/9] 面向)
    key       : 短 id, 給 debug / 日後維護
    title     : 顯示在 UI 上的小標題
    keywords  : list[str], 掃 item.impact / item.action 任一命中即匹配
    commands  : list[str], 每行一段, '#' 開頭為註解 (UI 用灰色不給複製)
    risks     : list[str], 條列風險
    verify    : list[str], 驗證指令 (複製 / 貼到終端跑)

匹配規則: 一個 item 可能命中多筆 entry, UI 按順序全部渲染。
"""
from __future__ import annotations
from typing import List, Dict

REMEDY_KB: List[Dict] = [
    # ============= 面向 2: 頻寬 =============
    {
        "face": 2, "key": "conntrack",
        "title": "conntrack 接近滿",
        "keywords": ["conntrack"],
        "commands": [
            "# 暫時生效 (立刻改, 重開機失效)",
            "sudo sysctl -w net.netfilter.nf_conntrack_max=262144",
            "sudo sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=600",
            "# 永久寫入 (重開機仍保留)",
            "sudo tee /etc/sysctl.d/99-conntrack.conf <<EOF",
            "net.netfilter.nf_conntrack_max = 262144",
            "net.netfilter.nf_conntrack_tcp_timeout_established = 600",
            "EOF",
            "sudo sysctl --system",
        ],
        "risks": [
            "記憶體: conntrack_max=262144 ≈ 75MB RAM (每條目 ~300 bytes)",
            "若真的超過新上限仍會 drop 新連線 (提升上限只是緩衝, 治本要找連線為何不斷累積)",
            "timeout 縮短可能讓長閒置連線提前被回收, NAT / 長連線 AP 請評估",
        ],
        "verify": [
            "cat /proc/sys/net/netfilter/nf_conntrack_max",
            "cat /proc/net/netfilter/nf_conntrack | wc -l     # 當前用量",
        ],
    },
    {
        "face": 2, "key": "time_wait",
        "title": "TIME_WAIT 過多",
        "keywords": ["TIME_WAIT", "TIME-WAIT"],
        "commands": [
            "# 暫時生效",
            'sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535"',
            "sudo sysctl -w net.ipv4.tcp_tw_reuse=1",
            "# 永久寫入",
            "sudo tee /etc/sysctl.d/99-tcp-tw.conf <<EOF",
            "net.ipv4.ip_local_port_range = 1024 65535",
            "net.ipv4.tcp_tw_reuse = 1",
            "EOF",
            "sudo sysctl --system",
        ],
        "risks": [
            "tcp_tw_reuse=1 在**純出站**連線安全, 若本機同時是 NAT 閘道可能舊封包錯亂",
            "ip_local_port_range 擴大到 1024 不會影響 <1024 root 保留的系統服務 port",
            "只影響「主動發起」連線 (outbound), 被動 accept 的 server 端不受影響",
        ],
        "verify": [
            "sysctl net.ipv4.tcp_tw_reuse",
            "sysctl net.ipv4.ip_local_port_range",
            "ss -tn state time-wait | wc -l",
        ],
    },
    {
        "face": 2, "key": "syn_drop",
        "title": "SYN / Listen drops",
        "keywords": ["SYN drop", "SYN/listen", "Listen overflows", "listen drops"],
        "commands": [
            "# 調高 kernel backlog 上限",
            "sudo sysctl -w net.core.somaxconn=4096",
            "sudo sysctl -w net.ipv4.tcp_max_syn_backlog=8192",
            "# 永久寫入",
            "sudo tee /etc/sysctl.d/99-backlog.conf <<EOF",
            "net.core.somaxconn = 4096",
            "net.ipv4.tcp_max_syn_backlog = 8192",
            "EOF",
            "sudo sysctl --system",
            "# 應用層 (Tomcat/Nginx/gunicorn) 自己的 backlog 也要配合調大",
        ],
        "risks": [
            "somaxconn 只是 kernel 上限, 應用層 listen(backlog=N) 才真正決定實際值 (兩者取小)",
            "調大僅延緩瞬間爆發流量, 若程式 accept 速度跟不上仍會 drop",
            "記憶體開銷極小, 通常無副作用",
        ],
        "verify": [
            "sysctl net.core.somaxconn",
            "sysctl net.ipv4.tcp_max_syn_backlog",
            "nstat -az | grep -E 'TcpExtListenDrops|TcpExtListenOverflows'",
        ],
    },
    {
        "face": 2, "key": "nic_error",
        "title": "NIC 累積錯誤 / dropped",
        "keywords": ["NIC 累積錯誤", "NIC 錯誤"],
        "commands": [
            "# 看是哪張卡 / 什麼錯誤",
            "ip -s link show",
            "# 找到 <nic> 後看詳細",
            "ethtool -S <nic> | grep -iE 'error|drop|discard'",
            "# 若 rxd (rx dropped) 多, 調大 rx ring",
            "ethtool -g <nic>                       # 先看當前 / max",
            "sudo ethtool -G <nic> rx 4096          # 調大 (上限看 Pre-set Max)",
        ],
        "risks": [
            "錯誤計數是 **uptime 內累積**, 可能是很久以前的問題, 再跑一次看有沒有增量",
            "ring buffer 增大只用一點記憶體, 影響極小",
            "若錯誤持續增加可能是實體問題 (線/光模組/網卡壞), 須找機房確認",
            "ethtool -G 重開機會失效, 要寫入 NetworkManager dispatcher 或 rc.local",
        ],
        "verify": [
            "ethtool -S <nic> | grep -iE 'error|drop|discard'",
            "ip -s link show",
        ],
    },
    # ============= 面向 6: 時間 / 憑證 =============
    {
        "face": 6, "key": "ntp",
        "title": "NTP 未同步",
        "keywords": ["NTP", "時間不同步", "chrony"],
        "commands": [
            "# 啟動 + 開機自啟 chronyd",
            "sudo systemctl enable --now chronyd",
            "# 若已在跑就重啟",
            "sudo systemctl restart chronyd",
            "# 強制立即同步一次 (跑一次)",
            "sudo chronyc -a makestep",
            "# 檢視同步來源",
            "chronyc tracking",
            "chronyc sources -v",
        ],
        "risks": [
            "makestep 會**直接跳時間** (非平滑 slew), 可能影響 cron 排程與 log 時間順序",
            "時間差距 > 1000 秒預設不會自動修, 要手動 makestep",
            "Kerberos / AD 環境時間差 > 5 分鐘會認證失敗, **先修時間再修 Kerberos**",
        ],
        "verify": [
            "chronyc tracking             # Leap status 應為 Normal",
            "timedatectl                  # System clock synchronized: yes",
        ],
    },
    {
        "face": 6, "key": "cert_expire",
        "title": "憑證即將到期",
        "keywords": ["憑證", "keystore", "cert", "30 天內到期", "到期"],
        "commands": [
            "# 掃描常見位置的憑證",
            "find /etc/pki /etc/ssl /opt -name '*.crt' -o -name '*.pem' 2>/dev/null | \\",
            "  xargs -I{} sh -c 'echo \"--- {} ---\"; openssl x509 -enddate -noout -in {} 2>/dev/null'",
            "# Java keystore",
            "keytool -list -v -keystore <path> -storepass <pass> | grep -E 'Alias|until'",
            "# 測 HTTPS 線上憑證到期",
            "echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null | \\",
            "  openssl x509 -noout -dates",
        ],
        "risks": [
            "憑證過期 → HTTPS 失效、Java 應用連不上 LDAP/DB、內部服務互信失效",
            "自簽續期需**同時發給所有信任方**, 否則新舊並存期間會報錯",
            "走內部 CA 的憑證走 CA 流程, 不要自己弄 (signature chain 會斷)",
        ],
        "verify": [
            "# 確認新憑證已被服務載入 (重啟服務後)",
            "echo | openssl s_client -connect <host>:443 2>/dev/null | openssl x509 -noout -dates",
        ],
    },
    # ============= 面向 8: Infra 穩定 =============
    {
        "face": 8, "key": "oom",
        "title": "OOM kill 歷史",
        "keywords": ["OOM", "out of memory"],
        "commands": [
            "# 看最近 OOM 事件",
            "sudo journalctl -k | grep -i 'out of memory' | tail -20",
            "sudo dmesg -T | grep -iE 'killed process|out of memory' | tail -20",
            "# 找出常被殺的 process",
            "sudo journalctl -k | grep 'Killed process' | awk '{print $NF}' | sort | uniq -c | sort -rn",
        ],
        "risks": [
            "**OOM kill 是後果, 不是原因** — 要查為什麼 OOM (memory leak / 設錯 limits / 負載突增)",
            "治標: 加 swap 或調 vm.swappiness; 治本: 找 memory leak 或限 cgroup memory",
            "Java/Tomcat 常見: -Xmx 設超過實體記憶體, 觸發系統級 OOM",
        ],
        "verify": [
            "free -h",
            "ps aux --sort=-%mem | head -10",
            "sudo journalctl -k --since '24 hours ago' | grep -ci 'out of memory'",
        ],
    },
    {
        "face": 8, "key": "failed_unit",
        "title": "systemd failed units",
        "keywords": ["failed units", "systemd failed"],
        "commands": [
            "# 看哪些 unit 失敗",
            "systemctl --failed",
            "# 取代 <name> 看 log",
            "sudo journalctl -u <name> -n 50 --no-pager",
            "# 先看 log 再決定下一步. 若只是暫時, 重試:",
            "sudo systemctl restart <name>",
            "# 確定無用可關:",
            "sudo systemctl disable --now <name>",
        ],
        "risks": [
            "**先看 log 再動作**, 不要無腦 restart — 可能 config 錯或依賴缺失",
            "若是 .timer / .socket 失敗, 影響面比單一 service 大 (例如 cron / 事件觸發)",
            "disable 前確認不是其他服務依賴的前置",
        ],
        "verify": [
            "systemctl --failed           # 應為 0 units",
            "systemctl status <name>",
        ],
    },
    # ============= 面向 1: 效能 =============
    {
        "face": 1, "key": "load_high",
        "title": "Load 過高 / CPU idle 低",
        "keywords": ["Load", "CPU idle"],
        "commands": [
            "# 找吃 CPU 的 process",
            "ps aux --sort=-%cpu | head -10",
            "top -bn1 | head -20",
            "# 系統觀察",
            "vmstat 1 5",
            "mpstat -P ALL 1 3",
            "# 若 D state 多, 查 IO",
            "ps -eo state,pid,cmd | awk '$1==\"D\"'",
        ],
        "risks": [
            "**不要盲目 kill** 高 CPU process, 可能是正常批次工作",
            "高 load 不一定 = 忙, 可能是 D state (IO wait) → 先查 disk",
            "交易系統尖峰調整負載前, 確認是否是業務高峰",
        ],
        "verify": [
            "uptime                                # load 應回到 < cores",
            "top -bn1 | head -5",
        ],
    },
    # ============= 面向 5: Storage =============
    {
        "face": 5, "key": "disk_full",
        "title": "磁碟 / 分區滿",
        "keywords": ["分區滿", "Disk 滿", "分區 滿", "磁碟 滿", "inode"],
        "commands": [
            "# 看各分區",
            "df -h",
            "df -i                                  # inode 用量",
            "# 找大檔",
            "sudo du -sh /* 2>/dev/null | sort -h | tail -10",
            "sudo find / -type f -size +500M 2>/dev/null | head -20",
            "# 清 journald (保留 7 天)",
            "sudo journalctl --vacuum-time=7d",
            "# 清 /tmp 舊檔 (7 天前)",
            "sudo find /tmp -type f -mtime +7 -delete",
        ],
        "risks": [
            "**不要直接刪 log** 先看有無 process 正開著 (lsof | grep deleted), 否則空間不會釋放",
            "清 /var/log 前確認沒 compliance 保留需求 (金融業常要保 1 年)",
            "/ 寫滿時 ssh 也可能進不來, 要先刪 /tmp 或 /var/log 才有空間操作",
        ],
        "verify": [
            "df -h",
            "df -i",
            "sudo du -sh /var/log /tmp /var/lib",
        ],
    },
]


def match_remedies(item: dict) -> List[Dict]:
    """掃 item 的 name/impact/action/actual 找所有命中的 remedy entry。
    單 item 可能命中多筆 (e.g. 頻寬 一次有 conntrack + TIME_WAIT + SYN drop)。
    比對大小寫不敏感 (keywords 和 pool 都轉小寫)。"""
    if not item:
        return []
    face = item.get("idx")
    pool_parts = [str(item.get(k, "") or "") for k in ("name", "impact", "action", "actual", "baseline")]
    pool = " | ".join(pool_parts).lower()

    hits = []
    for entry in REMEDY_KB:
        if entry.get("face") != face:
            continue
        keywords = entry.get("keywords", [])
        if any(kw.lower() in pool for kw in keywords):
            hits.append({
                "key":      entry["key"],
                "title":    entry.get("title", entry["key"]),
                "commands": entry.get("commands", []),
                "risks":    entry.get("risks", []),
                "verify":   entry.get("verify", []),
            })
    return hits
