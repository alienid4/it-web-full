#!/usr/bin/env python3
"""Generate Windows Ansible roles using base64 encoded PowerShell to avoid $ escaping issues"""
import os

ROLES_DIR = "/seclog/AI/inspection/ansible/roles"

# Base64 encoded PowerShell commands (generated from gen_b64.py)
B64 = {
    "cpu": "JABjAHAAdQA9ACgARwBlAHQALQBXAG0AaQBPAGIAagBlAGMAdAAgAFcAaQBuADMAMgBfAFAAcgBvAGMAZQBzAHMAbwByAHwATQBlAGEAcwB1AHIAZQAtAE8AYgBqAGUAYwB0ACAALQBQAHIAbwBwAGUAcgB0AHkAIABMAG8AYQBkAFAAZQByAGMAZQBuAHQAYQBnAGUAIAAtAEEAdgBlAHIAYQBnAGUAKQAuAEEAdgBlAHIAYQBnAGUAOwAkAG8AcwA9AEcAZQB0AC0AVwBtAGkATwBiAGoAZQBjAHQAIABXAGkAbgAzADIAXwBPAHAAZQByAGEAdABpAG4AZwBTAHkAcwB0AGUAbQA7ACQAbQB0AD0AWwBtAGEAdABoAF0AOgA6AFIAbwB1AG4AZAAoACQAbwBzAC4AVABvAHQAYQBsAFYAaQBzAGkAYgBsAGUATQBlAG0AbwByAHkAUwBpAHoAZQAvADEASwBCACwAMAApADsAJABtAGYAPQBbAG0AYQB0AGgAXQA6ADoAUgBvAHUAbgBkACgAJABvAHMALgBGAHIAZQBlAFAAaAB5AHMAaQBjAGEAbABNAGUAbQBvAHIAeQAvADEASwBCACwAMAApADsAJABtAHUAPQAkAG0AdAAtACQAbQBmADsAJABtAHAAPQBbAG0AYQB0AGgAXQA6ADoAUgBvAHUAbgBkACgAJABtAHUALwAkAG0AdAAqADEAMAAwACwAMAApADsAQAB7AGMAcAB1AD0AJABjAHAAdQA7AG0AZQBtAF8AcABjAHQAPQAkAG0AcAA7AG0AZQBtAF8AdABvAHQAYQBsAD0AJABtAHQAOwBtAGUAbQBfAHUAcwBlAGQAPQAkAG0AdQB9AHwAQwBvAG4AdgBlAHIAdABUAG8ALQBKAHMAbwBuAA==",
    "system": "JABwAGYAPQBHAGUAdAAtAFcAbQBpAE8AYgBqAGUAYwB0ACAAVwBpAG4AMwAyAF8AUABhAGcAZQBGAGkAbABlAFUAcwBhAGcAZQAgAC0ARQBBACAAUwBpAGwAZQBuAHQAbAB5AEMAbwBuAHQAaQBuAHUAZQA7ACQAcABmAFQAPQAwADsAJABwAGYAVQA9ADAAOwBpAGYAKAAkAHAAZgApAHsAJABwAGYAVAA9ACQAcABmAC4AQQBsAGwAbwBjAGEAdABlAGQAQgBhAHMAZQBTAGkAegBlADsAJABwAGYAVQA9ACQAcABmAC4AQwB1AHIAcgBlAG4AdABVAHMAYQBnAGUAfQA7ACQAcABmAFAAPQAwADsAaQBmACgAJABwAGYAVAAgAC0AZwB0ACAAMAApAHsAJABwAGYAUAA9AFsAbQBhAHQAaABdADoAOgBSAG8AdQBuAGQAKAAkAHAAZgBVAC8AJABwAGYAVAAqADEAMAAwACwAMQApAH0AOwAkAG8AcwA9AEcAZQB0AC0AQwBpAG0ASQBuAHMAdABhAG4AYwBlACAAVwBpAG4AMwAyAF8ATwBwAGUAcgBhAHQAaQBuAGcAUwB5AHMAdABlAG0AOwAkAGIAdAA9ACQAbwBzAC4ATABhAHMAdABCAG8AbwB0AFUAcABUAGkAbQBlAC4AVABvAFMAdAByAGkAbgBnACgAJwB5AHkAeQB5AC0ATQBNAC0AZABkACAASABIADoAbQBtADoAcwBzACcAKQA7ACQAdQBwAD0ATgBlAHcALQBUAGkAbQBlAFMAcABhAG4AIAAtAFMAdABhAHIAdAAgACQAbwBzAC4ATABhAHMAdABCAG8AbwB0AFUAcABUAGkAbQBlACAALQBFAG4AZAAgACgARwBlAHQALQBEAGEAdABlACkAOwAkAGMAYwA9ACgARwBlAHQALQBXAG0AaQBPAGIAagBlAGMAdAAgAFcAaQBuADMAMgBfAFAAcgBvAGMAZQBzAHMAbwByACkALgBOAHUAbQBiAGUAcgBPAGYATABvAGcAaQBjAGEAbABQAHIAbwBjAGUAcwBzAG8AcgBzADsAJAB1AGMAPQAwADsAdAByAHkAewAkAHEAPQBxAHUAZQByAHkAIAB1AHMAZQByACAAMgA+ACQAbgB1AGwAbAA7AGkAZgAoACQAcQApAHsAJAB1AGMAPQAoACQAcQB8AFMAZQBsAGUAYwB0AC0ATwBiAGoAZQBjAHQAIAAtAFMAawBpAHAAIAAxACkALgBDAG8AdQBuAHQAfQB9AGMAYQB0AGMAaAB7AH0AOwBAAHsAcwB3AGEAcABfAHQAbwB0AGEAbAA9ACQAcABmAFQAOwBzAHcAYQBwAF8AdQBzAGUAZAA9ACQAcABmAFUAOwBzAHcAYQBwAF8AcABjAHQAPQAkAHAAZgBQADsAYgBvAG8AdABfAHQAaQBtAGUAPQAkAGIAdAA7AHUAcAB0AGkAbQBlAD0AIgB1AHAAIAAkACgAJAB1AHAALgBEAGEAeQBzACkAIABkAGEAeQBzACwAIAAkACgAJAB1AHAALgBIAG8AdQByAHMAKQAgAGgAbwB1AHIAcwAiADsAdQBzAGUAcgBfAGMAbwB1AG4AdAA9ACQAdQBjADsAYwBwAHUAXwBjAG8AdQBuAHQAPQAkAGMAYwB9AHwAQwBvAG4AdgBlAHIAdABUAG8ALQBKAHMAbwBuAA==",
    "faillogin": "dAByAHkAewAkAGUAdgB0AHMAPQBHAGUAdAAtAFcAaQBuAEUAdgBlAG4AdAAgAC0ARgBpAGwAdABlAHIASABhAHMAaAB0AGEAYgBsAGUAIABAAHsATABvAGcATgBhAG0AZQA9ACcAUwBlAGMAdQByAGkAdAB5ACcAOwBJAGQAPQA0ADYAMgA1AH0AIAAtAE0AYQB4AEUAdgBlAG4AdABzACAAMgAwADAAIAAtAEUAQQAgAFMAdABvAHAAOwAkAGMAPQBAAHsAfQA7ACQAcgBhAHcAPQBAACgAKQA7AGYAbwByAGUAYQBjAGgAKAAkAGUAIABpAG4AIAAkAGUAdgB0AHMAKQB7ACQAdQA9ACQAZQAuAFAAcgBvAHAAZQByAHQAaQBlAHMAWwA1AF0ALgBWAGEAbAB1AGUAOwBpAGYAKAAkAHUAKQB7AGkAZgAoACQAYwAuAEMAbwBuAHQAYQBpAG4AcwBLAGUAeQAoACQAdQApACkAewAkAGMAWwAkAHUAXQArACsAfQBlAGwAcwBlAHsAJABjAFsAJAB1AF0APQAxAH0AOwBpAGYAKAAkAHIAYQB3AC4AQwBvAHUAbgB0ACAALQBsAHQAIAAyADAAKQB7ACQAcgBhAHcAKwA9AEAAewB1AHMAZQByAD0AJAB1ADsAcwBvAHUAcgBjAGUAPQAkAGUALgBQAHIAbwBwAGUAcgB0AGkAZQBzAFsAMQA5AF0ALgBWAGEAbAB1AGUAOwB0AGkAbQBlAD0AJABlAC4AVABpAG0AZQBDAHIAZQBhAHQAZQBkAC4AVABvAFMAdAByAGkAbgBnACgAJwB5AHkAeQB5AC0ATQBNAC0AZABkACAASABIADoAbQBtACcAKQB9AH0AfQB9ADsAJAB0AG8AcAA9AEAAKAApADsAZgBvAHIAZQBhAGMAaAAoACQAawAgAGkAbgAgACgAJABjAC4ARwBlAHQARQBuAHUAbQBlAHIAYQB0AG8AcgAoACkAfABTAG8AcgB0AC0ATwBiAGoAZQBjAHQAIABWAGEAbAB1AGUAIAAtAEQAZQBzAGMAfABTAGUAbABlAGMAdAAgAC0ARgBpAHIAcwB0ACAAMQAwACkAKQB7ACQAdABvAHAAKwA9AEAAewB1AHMAZQByAD0AJABrAC4ASwBlAHkAOwBjAG8AdQBuAHQAPQAkAGsALgBWAGEAbAB1AGUAfQB9ADsAQAB7AHQAbwB0AGEAbAA9ACgAJABjAC4AVgBhAGwAdQBlAHMAfABNAGUAYQBzAHUAcgBlAC0ATwBiAGoAZQBjAHQAIAAtAFMAdQBtACkALgBTAHUAbQA7AHQAbwBwAD0AJAB0AG8AcAA7AHIAYQB3AD0AJAByAGEAdwB9AHwAQwBvAG4AdgBlAHIAdABUAG8ALQBKAHMAbwBuACAALQBEAGUAcAB0AGgAIAAzAH0AYwBhAHQAYwBoAHsAQAB7AHQAbwB0AGEAbAA9ADAAOwB0AG8AcAA9AEAAKAApADsAcgBhAHcAPQBAACgAKQB9AHwAQwBvAG4AdgBlAHIAdABUAG8ALQBKAHMAbwBuACAALQBEAGUAcAB0AGgAIAAzAH0A",
    "errorlog": "dAByAHkAewAkAGUAdgB0AHMAPQBHAGUAdAAtAFcAaQBuAEUAdgBlAG4AdAAgAC0ARgBpAGwAdABlAHIASABhAHMAaAB0AGEAYgBsAGUAIABAAHsATABvAGcATgBhAG0AZQA9ACcAUwB5AHMAdABlAG0AJwA7AEwAZQB2AGUAbAA9ADEALAAyACwAMwA7AFMAdABhAHIAdABUAGkAbQBlAD0AKABHAGUAdAAtAEQAYQB0AGUAKQAuAEEAZABkAEgAbwB1AHIAcwAoAC0AMgA0ACkAfQAgAC0ATQBhAHgARQB2AGUAbgB0AHMAIAA1ADAAIAAtAEUAQQAgAFMAdABvAHAAOwAkAHIAPQBAACgAKQA7AGYAbwByAGUAYQBjAGgAKAAkAGUAIABpAG4AIAAkAGUAdgB0AHMAKQB7ACQAbAB2AD0AcwB3AGkAdABjAGgAKAAkAGUALgBMAGUAdgBlAGwAKQB7ADEAewAnAGMAcgBpAHQAJwB9ADIAewAnAGUAcgByAG8AcgAnAH0AMwB7ACcAdwBhAHIAbgAnAH0AZABlAGYAYQB1AGwAdAB7ACcAaQBuAGYAbwAnAH0AfQA7ACQAbQBzAGcAPQAkAGUALgBNAGUAcwBzAGEAZwBlADsAaQBmACgAJABtAHMAZwAuAEwAZQBuAGcAdABoACAALQBnAHQAIAAxADUAMAApAHsAJABtAHMAZwA9ACQAbQBzAGcALgBTAHUAYgBzAHQAcgBpAG4AZwAoADAALAAxADUAMAApAH0AOwAkAHIAKwA9AEAAewB0AGkAbQBlAD0AJABlAC4AVABpAG0AZQBDAHIAZQBhAHQAZQBkAC4AVABvAFMAdAByAGkAbgBnACgAJwBIAEgAOgBtAG0AOgBzAHMAJwApADsAbABlAHYAZQBsAD0AJABsAHYAOwBtAGUAcwBzAGEAZwBlAD0AJABtAHMAZwB9AH0AOwAkAGUAYwA9ACgAJAByAHwAVwBoAGUAcgBlAC0ATwBiAGoAZQBjAHQAewAkAF8ALgBsAGUAdgBlAGwAIAAtAGkAbgAgAEAAKAAnAGUAcgByAG8AcgAnACwAJwBjAHIAaQB0ACcAKQB9ACkALgBDAG8AdQBuAHQAOwAkAHcAYwA9ACgAJAByAHwAVwBoAGUAcgBlAC0ATwBiAGoAZQBjAHQAewAkAF8ALgBsAGUAdgBlAGwAIAAtAGUAcQAgACcAdwBhAHIAbgAnAH0AKQAuAEMAbwB1AG4AdAA7AEAAewBlAHIAcgBvAHIAXwBjAG8AdQBuAHQAPQAkAGUAYwA7AHcAYQByAG4AXwBjAG8AdQBuAHQAPQAkAHcAYwA7AGUAbgB0AHIAaQBlAHMAPQAkAHIAfQB8AEMAbwBuAHYAZQByAHQAVABvAC0ASgBzAG8AbgAgAC0ARABlAHAAdABoACAAMwB9AGMAYQB0AGMAaAB7AEAAewBlAHIAcgBvAHIAXwBjAG8AdQBuAHQAPQAwADsAdwBhAHIAbgBfAGMAbwB1AG4AdAA9ADAAOwBlAG4AdAByAGkAZQBzAD0AQAAoACkAfQB8AEMAbwBuAHYAZQByAHQAVABvAC0ASgBzAG8AbgB9AA==",
    "updates": "dAByAHkAewAkAHUAPQBHAGUAdAAtAEgAbwB0AEYAaQB4AHwAVwBoAGUAcgBlAC0ATwBiAGoAZQBjAHQAewAkAF8ALgBJAG4AcwB0AGEAbABsAGUAZABPAG4AIAAtAGcAdAAgACgARwBlAHQALQBEAGEAdABlACkALgBBAGQAZABEAGEAeQBzACgALQAzADAAKQB9AHwAUwBvAHIAdAAtAE8AYgBqAGUAYwB0ACAASQBuAHMAdABhAGwAbABlAGQATwBuACAALQBEAGUAcwBjADsAJAByAD0AQAAoACkAOwBmAG8AcgBlAGEAYwBoACgAJABoACAAaQBuACAAKAAkAHUAfABTAGUAbABlAGMAdAAtAE8AYgBqAGUAYwB0ACAALQBGAGkAcgBzAHQAIAAxADAAKQApAHsAJAByACsAPQBAAHsAaQBkAD0AJABoAC4ASABvAHQARgBpAHgASQBEADsAZABlAHMAYwA9ACQAaAAuAEQAZQBzAGMAcgBpAHAAdABpAG8AbgA7AGQAYQB0AGUAPQAkAGgALgBJAG4AcwB0AGEAbABsAGUAZABPAG4ALgBUAG8AUwB0AHIAaQBuAGcAKAAnAHkAeQB5AHkALQBNAE0ALQBkAGQAJwApAH0AfQA7AEAAewBjAG8AdQBuAHQAPQAkAHUALgBDAG8AdQBuAHQAOwB1AHAAZABhAHQAZQBzAD0AJAByAH0AfABDAG8AbgB2AGUAcgB0AFQAbwAtAEoAcwBvAG4AIAAtAEQAZQBwAHQAaAAgADMAfQBjAGEAdABjAGgAewBAAHsAYwBvAHUAbgB0AD0AMAA7AHUAcABkAGEAdABlAHMAPQBAACgAKQB9AHwAQwBvAG4AdgBlAHIAdABUAG8ALQBKAHMAbwBuAH0A",
    "defender": "dAByAHkAewAkAGQAPQBHAGUAdAAtAE0AcABDAG8AbQBwAHUAdABlAHIAUwB0AGEAdAB1AHMAOwBAAHsAZQBuAGEAYgBsAGUAZAA9AFsAYgBvAG8AbABdACQAZAAuAEEAbgB0AGkAdgBpAHIAdQBzAEUAbgBhAGIAbABlAGQAOwByAGUAYQBsAHQAaQBtAGUAPQBbAGIAbwBvAGwAXQAkAGQALgBSAGUAYQBsAFQAaQBtAGUAUAByAG8AdABlAGMAdABpAG8AbgBFAG4AYQBiAGwAZQBkADsAcwBpAGcAXwBkAGEAdABlAD0AJABkAC4AQQBuAHQAaQB2AGkAcgB1AHMAUwBpAGcAbgBhAHQAdQByAGUATABhAHMAdABVAHAAZABhAHQAZQBkAC4AVABvAFMAdAByAGkAbgBnACgAJwB5AHkAeQB5AC0ATQBNAC0AZABkACAASABIADoAbQBtACcAKQA7AHMAaQBnAF8AYQBnAGUAPQBbAG0AYQB0AGgAXQA6ADoAUgBvAHUAbgBkACgAKAAoAEcAZQB0AC0ARABhAHQAZQApAC0AJABkAC4AQQBuAHQAaQB2AGkAcgB1AHMAUwBpAGcAbgBhAHQAdQByAGUATABhAHMAdABVAHAAZABhAHQAZQBkACkALgBUAG8AdABhAGwARABhAHkAcwAsADAAKQA7AHMAYwBhAG4AXwBkAGEAdABlAD0AJABkAC4AUQB1AGkAYwBrAFMAYwBhAG4ARQBuAGQAVABpAG0AZQAuAFQAbwBTAHQAcgBpAG4AZwAoACcAeQB5AHkAeQAtAE0ATQAtAGQAZAAgAEgASAA6AG0AbQAnACkAOwB0AGgAcgBlAGEAdABzAD0AJABkAC4AVABoAHIAZQBhAHQARABlAHQAZQBjAHQAZQBkAH0AfABDAG8AbgB2AGUAcgB0AFQAbwAtAEoAcwBvAG4AfQBjAGEAdABjAGgAewBAAHsAZQBuAGEAYgBsAGUAZAA9ACQAZgBhAGwAcwBlADsAcgBlAGEAbAB0AGkAbQBlAD0AJABmAGEAbABzAGUAOwBzAGkAZwBfAGQAYQB0AGUAPQAnAE4ALwBBACcAOwBzAGkAZwBfAGEAZwBlAD0AOQA5ADkAOwBzAGMAYQBuAF8AZABhAHQAZQA9ACcATgAvAEEAJwA7AHQAaAByAGUAYQB0AHMAPQAwAH0AfABDAG8AbgB2AGUAcgB0AFQAbwAtAEoAcwBvAG4AfQA=",
    "firewall": "JABmAHcAPQBAACgAKQA7AGYAbwByAGUAYQBjAGgAKAAkAHAAIABpAG4AIAAoAEcAZQB0AC0ATgBlAHQARgBpAHIAZQB3AGEAbABsAFAAcgBvAGYAaQBsAGUAKQApAHsAJABmAHcAKwA9AEAAewBuAGEAbQBlAD0AJABwAC4ATgBhAG0AZQA7AGUAbgBhAGIAbABlAGQAPQBbAGIAbwBvAGwAXQAkAHAALgBFAG4AYQBiAGwAZQBkAH0AfQA7ACQAZgB3AHwAQwBvAG4AdgBlAHIAdABUAG8ALQBKAHMAbwBuAA==",
    "iis": "JABpAGkAcwA9AEcAZQB0AC0AUwBlAHIAdgBpAGMAZQAgAFcAMwBTAFYAQwAgAC0ARQBBACAAUwBpAGwAZQBuAHQAbAB5AEMAbwBuAHQAaQBuAHUAZQA7AGkAZgAoACQAaQBpAHMAKQB7AEAAewBpAG4AcwB0AGEAbABsAGUAZAA9ACQAdAByAHUAZQA7AHMAdABhAHQAdQBzAD0AJABpAGkAcwAuAFMAdABhAHQAdQBzAC4AVABvAFMAdAByAGkAbgBnACgAKQA7AHMAaQB0AGUAcwA9AEAAKAApAH0AfABDAG8AbgB2AGUAcgB0AFQAbwAtAEoAcwBvAG4AfQBlAGwAcwBlAHsAQAB7AGkAbgBzAHQAYQBsAGwAZQBkAD0AJABmAGEAbABzAGUAOwBzAHQAYQB0AHUAcwA9ACcATgBvAHQASQBuAHMAdABhAGwAbABlAGQAJwA7AHMAaQB0AGUAcwA9AEAAKAApAH0AfABDAG8AbgB2AGUAcgB0AFQAbwAtAEoAcwBvAG4AfQA=",
}

# Disk uses foreach so no $ issue - keep the existing working version
# CPU
cpu_yml = f'''# check_cpu/tasks/windows.yml - via SSH EncodedCommand
- name: Windows - Get CPU and Memory
  raw: "powershell -EncodedCommand {B64['cpu']}"
  register: win_cpu_raw
  changed_when: false

- name: Windows - Parse
  set_fact:
    _wc: "{{{{ win_cpu_raw.stdout | trim | from_json }}}}"

- name: Windows - Set CPU result
  set_fact:
    cpu_result:
      cpu_percent: "{{{{ _wc.cpu | default(0) }}}}"
      mem_percent: "{{{{ _wc.mem_pct | default(0) }}}}"
      cpu_status: "{{{{ 'error' if (_wc.cpu | default(0) | int) >= (cpu_crit | int) else 'warn' if (_wc.cpu | default(0) | int) >= (cpu_warn | int) else 'ok' }}}}"
      mem_status: "{{{{ 'error' if (_wc.mem_pct | default(0) | int) >= (mem_crit | int) else 'warn' if (_wc.mem_pct | default(0) | int) >= (mem_warn | int) else 'ok' }}}}"
      status: "{{{{ 'error' if ((_wc.cpu | default(0) | int) >= (cpu_crit | int)) or ((_wc.mem_pct | default(0) | int) >= (mem_crit | int)) else 'warn' if ((_wc.cpu | default(0) | int) >= (cpu_warn | int)) or ((_wc.mem_pct | default(0) | int) >= (mem_warn | int)) else 'ok' }}}}"
'''

# Error Log
elog_yml = f'''# check_error_log/tasks/windows.yml - via SSH EncodedCommand
- name: Windows - Get system errors
  raw: "powershell -EncodedCommand {B64['errorlog']}"
  register: win_elog_raw
  changed_when: false
  ignore_errors: yes

- name: Windows - Parse
  set_fact:
    _we: "{{{{ (win_elog_raw.stdout | trim | from_json) if win_elog_raw is succeeded and win_elog_raw.stdout | trim != '' and (win_elog_raw.stdout | trim)[0] == '{{' else {{'error_count':0,'warn_count':0,'entries':[]}} }}}}"

- name: Windows - Set error log result
  set_fact:
    error_log_result:
      status: "{{{{ 'error' if (_we.error_count | default(0) | int) > 0 else 'warn' if (_we.warn_count | default(0) | int) > 0 else 'ok' }}}}"
      error_count: "{{{{ _we.error_count | default(0) }}}}"
      warn_count: "{{{{ _we.warn_count | default(0) }}}}"
      log_file: "Windows Event Log (System)"
      entries: "{{{{ _we.entries | default([]) }}}}"
'''

# System (swap/uptime/users/faillogin)
sys_yml = f'''# check_system/tasks/windows.yml - via SSH EncodedCommand
- name: Windows - Get system info
  raw: "powershell -EncodedCommand {B64['system']}"
  register: win_sys_raw
  changed_when: false

- name: Windows - Parse system
  set_fact:
    _wsys: "{{{{ win_sys_raw.stdout | trim | from_json }}}}"

- name: Windows - Get failed logins
  raw: "powershell -EncodedCommand {B64['faillogin']}"
  register: win_fl_raw
  changed_when: false
  ignore_errors: yes

- name: Windows - Parse faillogin
  set_fact:
    _wfl: "{{{{ (win_fl_raw.stdout | trim | from_json) if win_fl_raw is succeeded and win_fl_raw.stdout | trim != '' and (win_fl_raw.stdout | trim)[0] == '{{' else {{'total':0,'top':[],'raw':[]}} }}}}"

- name: Windows - Set system result
  set_fact:
    system_result:
      swap:
        total_mb: "{{{{ _wsys.swap_total | default(0) }}}}"
        used_mb: "{{{{ _wsys.swap_used | default(0) }}}}"
        percent: "{{{{ _wsys.swap_pct | default(0) }}}}"
        status: "{{{{ 'error' if (_wsys.swap_pct | default(0) | float) >= 80 else 'warn' if (_wsys.swap_pct | default(0) | float) >= 50 else 'ok' }}}}"
      io: {{"devices":[],"max_busy":0,"status":"ok"}}
      load:
        load_1: "0"
        load_5: "0"
        load_15: "0"
        cpu_count: "{{{{ _wsys.cpu_count | default(1) }}}}"
        status: "ok"
      uptime:
        boot_time: "{{{{ _wsys.boot_time | default('unknown') }}}}"
        duration: "{{{{ _wsys.uptime | default('') }}}}"
      users:
        count: "{{{{ _wsys.user_count | default(0) }}}}"
        users: []
      faillogin:
        total_failures: "{{{{ _wfl.total | default(0) }}}}"
        top_offenders: "{{{{ (_wfl.top | default([]) | selectattr('count', 'ge', 5) | list)[:3] }}}}"
        raw_entries: "{{{{ _wfl.raw | default([]) }}}}"
        locked_accounts: []
        status: "{{{{ 'warn' if (_wfl.top | default([]) | selectattr('count', 'ge', 5) | list | length) > 0 else 'ok' }}}}"
      status: "ok"
'''

# Windows specific (update/iis/defender/firewall)
win_yml = f'''# check_windows/tasks/main.yml - via SSH EncodedCommand
- name: Windows checks
  when: ansible_os_family is defined and ansible_os_family == "Windows"
  block:
    - name: Get Windows Updates
      raw: "powershell -EncodedCommand {B64['updates']}"
      register: w_upd_raw
      changed_when: false
      ignore_errors: yes

    - name: Get IIS
      raw: "powershell -EncodedCommand {B64['iis']}"
      register: w_iis_raw
      changed_when: false
      ignore_errors: yes

    - name: Get Firewall
      raw: "powershell -EncodedCommand {B64['firewall']}"
      register: w_fw_raw
      changed_when: false
      ignore_errors: yes

    - name: Get Defender
      raw: "powershell -EncodedCommand {B64['defender']}"
      register: w_def_raw
      changed_when: false
      ignore_errors: yes

    - name: Parse all
      set_fact:
        _wu: "{{{{ (w_upd_raw.stdout | trim | from_json) if w_upd_raw is succeeded and w_upd_raw.stdout | trim != '' and (w_upd_raw.stdout | trim)[0] == '{{' else {{'count':0,'updates':[]}} }}}}"
        _wi: "{{{{ (w_iis_raw.stdout | trim | from_json) if w_iis_raw is succeeded and w_iis_raw.stdout | trim != '' and (w_iis_raw.stdout | trim)[0] == '{{' else {{'installed':false}} }}}}"
        _wf_raw: "{{{{ (w_fw_raw.stdout | trim | from_json) if w_fw_raw is succeeded and w_fw_raw.stdout | trim != '' else [] }}}}"
        _wd: "{{{{ (w_def_raw.stdout | trim | from_json) if w_def_raw is succeeded and w_def_raw.stdout | trim != '' and (w_def_raw.stdout | trim)[0] == '{{' else {{'enabled':false,'realtime':false,'sig_age':999}} }}}}"

    - name: Normalize firewall
      set_fact:
        _wf: "{{{{ [_wf_raw] if _wf_raw is mapping else _wf_raw | default([]) }}}}"

    - name: Set windows_result
      set_fact:
        windows_result:
          updates: {{"count": "{{{{ _wu.count | default(0) }}}}", "recent": "{{{{ _wu.updates | default([]) }}}}"}}
          iis: {{"installed": "{{{{ _wi.installed | default(false) }}}}", "status": "{{{{ _wi.status | default('N/A') }}}}", "sites": "{{{{ _wi.sites | default([]) }}}}"}}
          firewall: "{{{{ _wf }}}}"
          defender:
            enabled: "{{{{ _wd.enabled | default(false) }}}}"
            realtime: "{{{{ _wd.realtime | default(false) }}}}"
            signature_date: "{{{{ _wd.sig_date | default('N/A') }}}}"
            signature_age_days: "{{{{ _wd.sig_age | default(999) }}}}"
            last_scan: "{{{{ _wd.scan_date | default('N/A') }}}}"
            threats_detected: "{{{{ _wd.threats | default(0) }}}}"
          status: "{{{{ 'warn' if ((_wd.sig_age | default(999) | int) > 7) or (not (_wd.realtime | default(false) | bool)) else 'ok' }}}}"

- name: Non-Windows default
  set_fact:
    windows_result: {{"updates":{{"count":0,"recent":[]}},"iis":{{"installed":false}},"firewall":[],"defender":{{"enabled":false}},"status":"ok"}}
  when: ansible_os_family is not defined or ansible_os_family != "Windows"
'''

files = {
    f"{ROLES_DIR}/check_cpu/tasks/windows.yml": cpu_yml,
    f"{ROLES_DIR}/check_error_log/tasks/windows.yml": elog_yml,
    f"{ROLES_DIR}/check_system/tasks/windows.yml": sys_yml,
    f"{ROLES_DIR}/check_windows/tasks/main.yml": win_yml,
}

for path, content in files.items():
    with open(path, "w") as f:
        f.write(content)
    print(f"Written: {path}")

print("\nDone! All Windows roles updated to use EncodedCommand.")
