"""
os_parse.py - 把雜亂的 OS 字串拆成 (family, version)
v3.17.10.0+
"""
import re

# (regex, family_canonical) — 順序: 越特定越前面
PATTERNS = [
    (r"rocky\s*linux\s*([\d.]+)?", "Rocky Linux"),
    (r"rocky\s*([\d.]+)?",          "Rocky Linux"),
    (r"red\s*hat\s*([\d.]+)?",      "RHEL"),
    (r"redhat\s*([\d.]+)?",         "RHEL"),
    (r"rhel\s*([\d.]+)?",           "RHEL"),
    (r"centos\s*([\d.]+)?",         "CentOS"),
    (r"debian\s*([\d.]+)?",         "Debian"),
    (r"ubuntu\s*([\d.]+)?",         "Ubuntu"),
    (r"windows\s*server\s*(\d{4})", "Windows Server"),
    (r"windows\s*(\d+)",            "Windows"),
    (r"aix\s*([\d.]+)?",            "AIX"),
    (r"sles\s*([\d.]+)?",           "SLES"),
    (r"oracle\s*linux\s*([\d.]+)?", "Oracle Linux"),
    (r"alpine\s*([\d.]+)?",         "Alpine"),
    (r"as[/-]?400\s*([\d.]+)?",     "IBM AS/400"),
    (r"fortios\s*([\d.]+)?",        "FortiOS"),
    (r"cisco\s*ios\s*([\d.]+)?",    "Cisco IOS"),
]


def parse_os(s):
    """解 OS 字串 → (family, version).
    解不出來: family 保留原字串, version=''
    """
    if not s:
        return "", ""
    s_low = str(s).lower().strip()
    for pat, family in PATTERNS:
        m = re.search(pat, s_low)
        if m:
            ver = (m.group(1) or "").strip() if m.lastindex else ""
            return family, ver
    return s.strip(), ""


def normalize_os_field(host):
    """把 host.os 拆成 host.os (family) + host.os_version.
    若已有 os_version 不動.
    Returns: (os_family, os_version, changed_bool)
    """
    cur_os = host.get("os", "") or ""
    cur_ver = host.get("os_version", "") or ""
    if cur_ver:
        # 已經有獨立 version 欄, family 也可能就是 family-only
        family, ver_from_os = parse_os(cur_os)
        if ver_from_os and not cur_ver:
            return family, ver_from_os, True
        return family or cur_os, cur_ver, False
    # 沒 version 欄 → 從 os 字串拆
    family, ver = parse_os(cur_os)
    if family != cur_os or ver != cur_ver:
        return family, ver, True
    return family, ver, False


def display(host):
    """組合 family + version 給 UI 顯示."""
    family = host.get("os") or ""
    ver = host.get("os_version") or ""
    if family and ver:
        return f"{family} {ver}"
    return family or ver or "-"
