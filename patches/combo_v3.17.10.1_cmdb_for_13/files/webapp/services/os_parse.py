"""
os_parse.py - 把雜亂的 OS 字串拆成 (family, version)
v3.17.10.1+: 3 層防禦 (精確 → typo → fuzzy)

策略: 先抽 version (任何數字), 再 normalize family 文字 → 比對 FAMILY_MAP
"""
import re
import difflib

# (key_lower, canonical_proper) — 越特定 (越長) 越先試
FAMILY_MAP = [
    ("rocky linux",   "Rocky Linux"),
    ("oracle linux",  "Oracle Linux"),
    ("windows server", "Windows Server"),
    ("cisco ios",     "Cisco IOS"),
    ("ibm as/400",    "IBM AS/400"),
    ("red hat",       "RHEL"),
    ("redhat",        "RHEL"),
    ("rocky",         "Rocky Linux"),
    ("rhel",          "RHEL"),
    ("centos",        "CentOS"),
    ("debian",        "Debian"),
    ("ubuntu",        "Ubuntu"),
    ("windows",       "Windows"),
    ("alpine",        "Alpine"),
    ("aix",           "AIX"),
    ("sles",          "SLES"),
    ("fortios",       "FortiOS"),
    ("as/400",        "IBM AS/400"),
    ("as400",         "IBM AS/400"),
]

# typo / alias → canonical lowercase
TYPO_ALIASES = {
    "rhle": "rhel", "rhlel": "rhel", "rehl": "rhel",
    "redhta": "red hat", "red hta": "red hat",
    "centosss": "centos", "cetnos": "centos", "cents": "centos", "centsos": "centos",
    "debain": "debian", "debien": "debian", "deban": "debian", "debaian": "debian",
    "ubunto": "ubuntu", "ubunut": "ubuntu", "ubunt": "ubuntu", "ubantu": "ubuntu",
    "rockey": "rocky", "rocy": "rocky",
    "rockey linux": "rocky linux", "rocy linux": "rocky linux",
    "win": "windows server",  # 預設 Win 解 server (帶 4 位年份的話)
    "windowserver": "windows server", "windowsserver": "windows server",
    "windwos": "windows", "wndows": "windows",
    "iax": "aix",
}


def _normalize_text(s_low):
    """剝掉數字 + 整理空白, 得 'pure text' 給比對"""
    t = re.sub(r"[\d.]+", " ", s_low)
    t = re.sub(r"\s+", " ", t).strip()
    return t


def _extract_version(s_low):
    m = re.search(r"(\d+\.?\d*)", s_low)
    return m.group(1) if m else ""


def _is_substring_match(fam_str, key):
    """key 是否以「完整字詞」出現在 fam_str 中
    e.g. fam_str='red hat enterprise', key='red hat' → True
    fam_str='centosss', key='centos' → False (not boundary)
    """
    return (fam_str == key or
            fam_str.startswith(key + " ") or
            fam_str.endswith(" " + key) or
            " " + key + " " in " " + fam_str + " ")


def parse_os(s):
    """解 OS 字串 → (family, version). 3 層防禦.
    都失敗: 保留原字串 family, version=''
    """
    if not s:
        return "", ""
    s_low = str(s).lower().strip()
    version = _extract_version(s_low)
    fam_str = _normalize_text(s_low)

    if not fam_str:
        return s.strip(), version

    # 1. 精確比對 (long-first)
    for key, canonical in FAMILY_MAP:
        if _is_substring_match(fam_str, key):
            # Win + 4 位年份 → Windows Server (不是 Windows)
            if canonical == "Windows" and version and len(version) == 4 and version.isdigit() and int(version) >= 2000:
                canonical = "Windows Server"
            return canonical, version

    # 2. typo alias
    candidates = [fam_str, fam_str.replace(" ", "")]
    for c in candidates:
        if c in TYPO_ALIASES:
            mapped_low = TYPO_ALIASES[c]
            for key, canonical in FAMILY_MAP:
                if key == mapped_low:
                    if canonical == "Windows" and version and len(version) == 4 and version.isdigit() and int(version) >= 2000:
                        canonical = "Windows Server"
                    return canonical, version

    # 3. 模糊比對 (Levenshtein)
    keys = [k for k, _ in FAMILY_MAP]
    matches = difflib.get_close_matches(fam_str, keys, n=1, cutoff=0.65)
    if matches:
        matched_key = matches[0]
        for key, canonical in FAMILY_MAP:
            if key == matched_key:
                return canonical, version

    return s.strip(), version


def normalize_os_field(host):
    """把 host.os 拆成 host.os (family) + host.os_version"""
    cur_os = host.get("os", "") or ""
    cur_ver = host.get("os_version", "") or ""
    if cur_ver:
        family, ver_from_os = parse_os(cur_os)
        return family or cur_os, cur_ver, family != cur_os
    family, ver = parse_os(cur_os)
    return family, ver, (family != cur_os or ver != cur_ver)


def display(host):
    family = host.get("os") or ""
    ver = host.get("os_version") or ""
    if family and ver:
        return f"{family} {ver}"
    return family or ver or "-"
