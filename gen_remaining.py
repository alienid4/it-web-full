#!/usr/bin/env python3
"""Generate remaining Windows roles (disk, service, account) with EncodedCommand"""

b64 = {}
with open("/tmp/b64_output2.txt") as f:
    current = None
    for line in f:
        line = line.strip()
        if line.startswith("=== ") and line.endswith(" ==="):
            current = line[4:-4]
        elif line and current:
            b64[current] = line
            current = None

ROLES_DIR = "/seclog/AI/inspection/ansible/roles"
J = "{{"
K = "}}"

disk = f"""# check_disk/tasks/windows.yml - EncodedCommand
- name: Windows - Get disk info
  raw: "powershell -EncodedCommand {b64['disk']}"
  register: win_disk_raw
  changed_when: false
  ignore_errors: yes

- name: Windows - Parse disk
  set_fact:
    _win_disks_parsed: "{J} (win_disk_raw.stdout | trim | from_json) if win_disk_raw is succeeded and win_disk_raw.stdout | trim != '' else [] {K}"

- name: Windows - Normalize to list
  set_fact:
    _win_disks: "{J} [_win_disks_parsed] if _win_disks_parsed is mapping else _win_disks_parsed | default([]) {K}"

- name: Windows - Build partitions
  set_fact:
    parsed_partitions: "{J} parsed_partitions | default([]) + [{{'mount': item.DeviceID, 'size': (item.Size | string) + 'G', 'used': (item.Used | string) + 'G', 'free': (item.Free | string) + 'G', 'percent': item.Percent | int, 'status': 'error' if (item.Percent | int) >= (disk_crit | int) else 'warn' if (item.Percent | int) >= (disk_warn | int) else 'ok'}}] {K}"
  loop: "{J} _win_disks | default([]) {K}"
  loop_control:
    label: "{J} item.DeviceID | default('?') {K}"

- name: Windows - Set disk result
  set_fact:
    disk_result:
      status: >-
        {J} 'error' if parsed_partitions | default([]) | selectattr('status', 'eq', 'error') | list | length > 0
           else 'warn' if parsed_partitions | default([]) | selectattr('status', 'eq', 'warn') | list | length > 0
           else 'ok' {K}
      warn_threshold: "{J} disk_warn {K}"
      crit_threshold: "{J} disk_crit {K}"
      partitions: "{J} parsed_partitions | default([]) {K}"
"""

svc = f"""# check_service/tasks/windows.yml - EncodedCommand
- name: Windows - Get services
  raw: "powershell -EncodedCommand {b64['service']}"
  register: win_svc_raw
  changed_when: false

- name: Windows - Parse
  set_fact:
    _ws_raw: "{J} win_svc_raw.stdout | trim | from_json {K}"

- name: Windows - Normalize
  set_fact:
    _ws: "{J} [_ws_raw] if _ws_raw is mapping else _ws_raw | default([]) {K}"

- name: Windows - Build list
  set_fact:
    _svc_list: "{J} _svc_list | default([]) + [{{'name': item.name, 'status': 'active' if item.status == 'Running' else item.status}}] {K}"
  loop: "{J} _ws {K}"
  loop_control:
    label: "{J} item.name {K}"

- name: Windows - Set service result
  set_fact:
    service_result:
      status: "{J} 'error' if _svc_list | default([]) | selectattr('status', 'ne', 'active') | selectattr('status', 'ne', 'NotFound') | list | length > 0 else 'ok' {K}"
      services: "{J} _svc_list | default([]) {K}"
"""

acct = f"""# check_account/tasks/windows.yml - EncodedCommand
- name: Windows - Get local users
  raw: "powershell -EncodedCommand {b64['account']}"
  register: win_users_raw
  changed_when: false

- name: Windows - Get admin members
  raw: "powershell -EncodedCommand {b64['admins']}"
  register: win_admins_raw
  changed_when: false
  ignore_errors: yes

- name: Windows - Parse users
  set_fact:
    _wu_raw: "{J} win_users_raw.stdout | trim | from_json {K}"

- name: Windows - Normalize
  set_fact:
    _wu: "{J} [_wu_raw] if _wu_raw is mapping else _wu_raw | default([]) {K}"

- name: Windows - Load previous snapshot
  slurp:
    src: "{J} account_snapshot_dir {K}/{J} inventory_hostname {K}_accounts.json"
  register: prev_snap
  delegate_to: localhost
  ignore_errors: yes

- name: Windows - Calc diff
  set_fact:
    _cur_names: "{J} _wu | map(attribute='Name') | list {K}"
    _prev_names: "{J} ((prev_snap.content | b64decode | from_json) | map(attribute='Name') | list) if prev_snap is succeeded else [] {K}"

- name: Windows - Set account result
  set_fact:
    account_result:
      status: "{J} 'warn' if (_cur_names | difference(_prev_names) | length > 0) or (_prev_names | difference(_cur_names) | length > 0) else 'ok' {K}"
      total_accounts: "{J} _wu | length {K}"
      accounts_added: "{J} _cur_names | difference(_prev_names) {K}"
      accounts_removed: "{J} _prev_names | difference(_cur_names) {K}"
      uid0_alert: false
      note: ""

- name: Windows - Save snapshot
  copy:
    content: "{J} _wu | to_nice_json {K}"
    dest: "{J} account_snapshot_dir {K}/{J} inventory_hostname {K}_accounts.json"
  delegate_to: localhost
"""

files = {
    f"{ROLES_DIR}/check_disk/tasks/windows.yml": disk,
    f"{ROLES_DIR}/check_service/tasks/windows.yml": svc,
    f"{ROLES_DIR}/check_account/tasks/windows.yml": acct,
}

for path, content in files.items():
    with open(path, "w") as f:
        f.write(content)
    print(f"Written: {path}")

print("Done!")
