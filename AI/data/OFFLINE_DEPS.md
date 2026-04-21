# 離線安裝包 — IT 監控系統完整依賴清單

> **情境**：目標主機無網路，必須從有網路的電腦一個一個下載套件，拷貝到目標機離線安裝。
>
> 本清單含 **全部 Python wheel + RPM + 容器映像 + 二進位檔**，點連結即下載。
>
> 對應系統版本: **v3.11.x** (2026-04-20)
> 目標 OS: **Rocky Linux 9.7** (RHEL 9 系)

---

## 一、Python Wheel (pip download) — 共 35 套件

> **推薦做法**：若一台中繼機有網，跑 `pip download -d wheels/ -r requirements.txt`，把 `wheels/` 打包拷貝到目標機，用 `pip install --no-index --find-links=wheels/ <套件>` 裝。
>
> 若真要一個個手動下載，下表每個 PyPI 連結點進去選「Download files」有 `.whl` (cp39-manylinux) 或 `.tar.gz`。

### 1.1 Flask 生態 (Webapp 必要)

| 套件 | 版本 | PyPI 下載頁 |
|---|---|---|
| Flask | 3.1.3 | https://pypi.org/project/Flask/3.1.3/#files |
| Werkzeug | 3.1.8 | https://pypi.org/project/Werkzeug/3.1.8/#files |
| Jinja2 | 3.1.6 | https://pypi.org/project/Jinja2/3.1.6/#files |
| itsdangerous | 2.2.0 | https://pypi.org/project/itsdangerous/2.2.0/#files |
| click | 8.1.8 | https://pypi.org/project/click/8.1.8/#files |
| MarkupSafe | 2.1.1 | https://pypi.org/project/MarkupSafe/2.1.1/#files |
| blinker | 1.9.0 | https://pypi.org/project/blinker/1.9.0/#files |
| gunicorn | 22.0.0 | https://pypi.org/project/gunicorn/22.0.0/#files |
| importlib_metadata | 8.7.1 | https://pypi.org/project/importlib-metadata/8.7.1/#files |
| importlib_resources | 6.5.2 | https://pypi.org/project/importlib-resources/6.5.2/#files |
| zipp | 3.23.0 | https://pypi.org/project/zipp/3.23.0/#files |
| packaging | 26.0 | https://pypi.org/project/packaging/26.0/#files |

### 1.2 DB / 認證 / 網路

| 套件 | 版本 | PyPI 下載頁 |
|---|---|---|
| pymongo | 4.7.3 | https://pypi.org/project/pymongo/4.7.3/#files |
| python-ldap | 3.4.5 | https://pypi.org/project/python-ldap/3.4.5/#files |
| pyasn1 | 0.4.8 | https://pypi.org/project/pyasn1/0.4.8/#files |
| pyasn1_modules | 0.4.2 | https://pypi.org/project/pyasn1-modules/0.4.2/#files |
| cryptography | 38.0.4 | https://pypi.org/project/cryptography/38.0.4/#files |
| requests | 2.32.5 | https://pypi.org/project/requests/2.32.5/#files |
| requests_ntlm | 1.3.0 | https://pypi.org/project/requests-ntlm/1.3.0/#files |
| urllib3 | 2.6.3 | https://pypi.org/project/urllib3/2.6.3/#files |
| certifi | 2026.2.25 | https://pypi.org/project/certifi/2026.2.25/#files |
| charset-normalizer | 3.4.7 | https://pypi.org/project/charset-normalizer/3.4.7/#files |
| idna | 2.10 | https://pypi.org/project/idna/2.10/#files |
| six | 1.15.0 | https://pypi.org/project/six/1.15.0/#files |

### 1.3 效能月報 matplotlib

| 套件 | 版本 | PyPI 下載頁 |
|---|---|---|
| matplotlib | 3.9.4 | https://pypi.org/project/matplotlib/3.9.4/#files |
| numpy | 2.0.2 | https://pypi.org/project/numpy/2.0.2/#files |
| contourpy | 1.3.0 | https://pypi.org/project/contourpy/1.3.0/#files |
| cycler | 0.12.1 | https://pypi.org/project/cycler/0.12.1/#files |
| fonttools | 4.60.2 | https://pypi.org/project/fonttools/4.60.2/#files |
| kiwisolver | 1.4.7 | https://pypi.org/project/kiwisolver/1.4.7/#files |
| pyparsing | 2.4.7 | https://pypi.org/project/pyparsing/2.4.7/#files |
| python-dateutil | 2.9.0.post0 | https://pypi.org/project/python-dateutil/2.9.0.post0/#files |
| pillow | 11.3.0 | https://pypi.org/project/pillow/11.3.0/#files |

### 1.4 PDF / 報告

| 套件 | 版本 | PyPI 下載頁 |
|---|---|---|
| reportlab | 4.4.10 | https://pypi.org/project/reportlab/4.4.10/#files |
| PyYAML | 5.4.1 | https://pypi.org/project/PyYAML/5.4.1/#files |

### 1.5 (選配) 資安掃描工具 — 只有想在目標機跑掃描時才要

| 套件 | 版本 | PyPI 下載頁 |
|---|---|---|
| bandit | 1.8.6 | https://pypi.org/project/bandit/1.8.6/#files |
| pip-audit | 2.9.0 | https://pypi.org/project/pip-audit/2.9.0/#files |
| wapiti3 | 3.1.8 | https://pypi.org/project/wapiti3/3.1.8/#files |

### 1.6 快速複製 requirements.txt

```txt
Flask==3.1.3
Werkzeug==3.1.8
Jinja2==3.1.6
itsdangerous==2.2.0
click==8.1.8
MarkupSafe==2.1.1
blinker==1.9.0
gunicorn==22.0.0
importlib_metadata==8.7.1
importlib_resources==6.5.2
zipp==3.23.0
packaging==26.0
pymongo==4.7.3
python-ldap==3.4.5
pyasn1==0.4.8
pyasn1_modules==0.4.2
cryptography==38.0.4
requests==2.32.5
requests_ntlm==1.3.0
urllib3==2.6.3
certifi==2026.2.25
charset-normalizer==3.4.7
idna==2.10
six==1.15.0
matplotlib==3.9.4
numpy==2.0.2
contourpy==1.3.0
cycler==0.12.1
fonttools==4.60.2
kiwisolver==1.4.7
pyparsing==2.4.7
python-dateutil==2.9.0.post0
pillow==11.3.0
reportlab==4.4.10
PyYAML==5.4.1
```

### 1.7 在有網中繼機的一行指令（推薦）

```bash
# 中繼機(有網): 一次抓齊全部 wheel
mkdir wheels && pip download -d wheels/ -r requirements.txt --python-version 39 --platform manylinux2014_x86_64 --only-binary=:all:

# 打包
tar czf python_wheels_v3.11.tar.gz wheels/

# 目標機(無網): 解壓後安裝
tar xzf python_wheels_v3.11.tar.gz
pip install --no-index --find-links=wheels/ -r requirements.txt
```

---

## 二、RPM 套件 (Rocky Linux 9.7)

> Rocky 官方 repo: http://download.rockylinux.org/pub/rocky/9/
> EPEL (for nmon): https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/
> 或可去 https://pkgs.org/ 搜對應 RPM 下載

### 2.1 核心系統套件

| 套件 | 版本 | 來源 / 說明 |
|---|---|---|
| **podman** | 5.6.0-14.el9_7 | `dnf download podman` 或 http://download.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/Packages/p/ |
| **ansible-core** | 2.14.18-1.el9 | 同上, AppStream |
| **python3-pip** | 21.3.1-1.el9 | 同上 |
| **python3-pip-wheel** | 21.3.1-1.el9 | 同上 |
| **openssh-server** | 8.7p1-47.el9_7 | 同上, BaseOS |
| **openssh-clients** | 8.7p1-47.el9_7 | 同上 |
| **net-snmp-utils** | 5.9.1-17.el9_7.1 | 同上 |

### 2.2 字型 / 工具

| 套件 | 版本 | 來源 |
|---|---|---|
| **google-noto-sans-cjk-ttc-fonts** | 20230817-2.el9 | Rocky AppStream |
| **nmon** | 16p-1.el9 | **EPEL** (不在預設 repo) |

### 2.3 快速 RPM 下載指令（中繼機有網）

```bash
# 一次抓齊 RPM 及所有相依
mkdir rpms && cd rpms
dnf download --resolve --alldeps \
    podman ansible-core python3-pip openssh-server openssh-clients \
    net-snmp-utils google-noto-sans-cjk-ttc-fonts nmon
# 注意: nmon 要先 dnf install epel-release

# 打包
cd .. && tar czf rpms_rocky9_v3.11.tar.gz rpms/

# 目標機(無網):
tar xzf rpms_rocky9_v3.11.tar.gz
dnf install -y rpms/*.rpm
```

---

## 三、容器映像 MongoDB

| 映像 | tag | 大小 |
|---|---|---|
| docker.io/library/mongo | 6 | 778 MB |

### 3.1 下載 / 匯出 / 匯入

```bash
# 中繼機 (有網):
podman pull docker.io/library/mongo:6
podman save -o mongodb_6.tar docker.io/library/mongo:6

# 或 docker 版:
docker pull mongo:6
docker save mongo:6 -o mongodb_6.tar

# 目標機 (無網):
podman load -i mongodb_6.tar
# 或: docker load -i mongodb_6.tar
```

### 3.2 官方直連 (手動)
- 入口: https://hub.docker.com/_/mongo
- Tag 6: https://hub.docker.com/layers/library/mongo/6/images/

---

## 四、獨立二進位檔

### 4.1 cloudflared (Cloudflare Tunnel)

| 平台 | 版本 | 下載連結 |
|---|---|---|
| Linux amd64 (RPM) | 2026.3.0 | https://github.com/cloudflare/cloudflared/releases/tag/2026.3.0 |
| Linux amd64 (binary) | latest | https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 |
| RPM 直連 | latest | https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm |

### 4.2 其他 (可選)

- **Podman 4 手動版** (若 Rocky repo 版本不合): https://github.com/containers/podman/releases
- **Ansible 8.5+** (PyPI ansible 套件, 非 ansible-core): https://pypi.org/project/ansible/8.5.0/#files

---

## 五、一鍵打包腳本 (中繼機用)

```bash
#!/bin/bash
# bundle_offline_deps.sh — 在有網的中繼機上跑，產生離線安裝包
OUT=/tmp/inspection_offline_bundle
mkdir -p $OUT/{wheels,rpms,images,bin}

# Python wheels
cat > $OUT/requirements.txt << 'EOF'
Flask==3.1.3
Werkzeug==3.1.8
Jinja2==3.1.6
itsdangerous==2.2.0
click==8.1.8
MarkupSafe==2.1.1
blinker==1.9.0
gunicorn==22.0.0
importlib_metadata==8.7.1
importlib_resources==6.5.2
zipp==3.23.0
packaging==26.0
pymongo==4.7.3
python-ldap==3.4.5
pyasn1==0.4.8
pyasn1_modules==0.4.2
cryptography==38.0.4
requests==2.32.5
requests_ntlm==1.3.0
urllib3==2.6.3
certifi==2026.2.25
charset-normalizer==3.4.7
idna==2.10
six==1.15.0
matplotlib==3.9.4
numpy==2.0.2
contourpy==1.3.0
cycler==0.12.1
fonttools==4.60.2
kiwisolver==1.4.7
pyparsing==2.4.7
python-dateutil==2.9.0.post0
pillow==11.3.0
reportlab==4.4.10
PyYAML==5.4.1
EOF

pip3 download -d $OUT/wheels/ -r $OUT/requirements.txt \
    --python-version 39 --platform manylinux2014_x86_64 --only-binary=:all: 2>/dev/null

# RPMs
sudo dnf install -y epel-release
cd $OUT/rpms
sudo dnf download --resolve --alldeps \
    podman ansible-core python3-pip openssh-server openssh-clients \
    net-snmp-utils google-noto-sans-cjk-ttc-fonts nmon
cd -

# MongoDB image
podman pull docker.io/library/mongo:6
podman save -o $OUT/images/mongodb_6.tar docker.io/library/mongo:6

# cloudflared
curl -sSL -o $OUT/bin/cloudflared-linux-x86_64.rpm \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm

# Pack
tar czf /tmp/inspection_offline_bundle_v3.11.tar.gz -C /tmp inspection_offline_bundle
echo "Done. /tmp/inspection_offline_bundle_v3.11.tar.gz ($(du -h /tmp/inspection_offline_bundle_v3.11.tar.gz | cut -f1))"
```

**預估總大小**：約 **1.5~2 GB**（MongoDB 映像 778MB + Python wheels ~200MB + RPM ~500MB + cloudflared ~30MB + 中文字型 ~150MB）

---

## 六、目標機離線安裝順序

```bash
# 解包
tar xzf inspection_offline_bundle_v3.11.tar.gz -C /tmp

# 1. RPM (先裝 EPEL 那個先, 然後其他)
sudo dnf install -y /tmp/inspection_offline_bundle/rpms/*.rpm

# 2. Python wheels
sudo pip3 install --no-index --find-links=/tmp/inspection_offline_bundle/wheels/ \
    -r /tmp/inspection_offline_bundle/requirements.txt

# 3. MongoDB image
podman load -i /tmp/inspection_offline_bundle/images/mongodb_6.tar

# 4. cloudflared (若用 rpm 版, 上面 rpms 那步就裝好; 否則)
sudo rpm -i /tmp/inspection_offline_bundle/bin/cloudflared-linux-x86_64.rpm

# 5. 驗證
python3 -c "import flask, pymongo, matplotlib, reportlab; print('OK')"
systemctl --version
ansible --version
podman --version
cloudflared --version
```

---

## 七、日後追加套件流程

當版本升級需要新套件時（例如加 pandas）：

1. **在有網中繼機**：`pip download -d wheels/ pandas`
2. **拷貝** `wheels/*.whl` 到目標機的 `/tmp/new_wheels/`
3. **離線裝**：`pip install --no-index --find-links=/tmp/new_wheels/ pandas`
4. **記錄** 到此文件對應表格

---

**文件版本**: 對應 IT 監控系統 **v3.11.x**
**最後更新**: 2026-04-20
