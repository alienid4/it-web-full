import base64

scripts = {
    "cpu": """$cpu=(Get-WmiObject Win32_Processor|Measure-Object -Property LoadPercentage -Average).Average;$os=Get-WmiObject Win32_OperatingSystem;$mt=[math]::Round($os.TotalVisibleMemorySize/1KB,0);$mf=[math]::Round($os.FreePhysicalMemory/1KB,0);$mu=$mt-$mf;$mp=[math]::Round($mu/$mt*100,0);@{cpu=$cpu;mem_pct=$mp;mem_total=$mt;mem_used=$mu}|ConvertTo-Json""",

    "system": """$pf=Get-WmiObject Win32_PageFileUsage -EA SilentlyContinue;$pfT=0;$pfU=0;if($pf){$pfT=$pf.AllocatedBaseSize;$pfU=$pf.CurrentUsage};$pfP=0;if($pfT -gt 0){$pfP=[math]::Round($pfU/$pfT*100,1)};$os=Get-CimInstance Win32_OperatingSystem;$bt=$os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss');$up=New-TimeSpan -Start $os.LastBootUpTime -End (Get-Date);$cc=(Get-WmiObject Win32_Processor).NumberOfLogicalProcessors;$uc=0;try{$q=query user 2>$null;if($q){$uc=($q|Select-Object -Skip 1).Count}}catch{};@{swap_total=$pfT;swap_used=$pfU;swap_pct=$pfP;boot_time=$bt;uptime="up $($up.Days) days, $($up.Hours) hours";user_count=$uc;cpu_count=$cc}|ConvertTo-Json""",

    "faillogin": """try{$evts=Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625} -MaxEvents 200 -EA Stop;$c=@{};$raw=@();foreach($e in $evts){$u=$e.Properties[5].Value;if($u){if($c.ContainsKey($u)){$c[$u]++}else{$c[$u]=1};if($raw.Count -lt 20){$raw+=@{user=$u;source=$e.Properties[19].Value;time=$e.TimeCreated.ToString('yyyy-MM-dd HH:mm')}}}};$top=@();foreach($k in ($c.GetEnumerator()|Sort-Object Value -Desc|Select -First 10)){$top+=@{user=$k.Key;count=$k.Value}};@{total=($c.Values|Measure-Object -Sum).Sum;top=$top;raw=$raw}|ConvertTo-Json -Depth 3}catch{@{total=0;top=@();raw=@()}|ConvertTo-Json -Depth 3}""",

    "errorlog": """try{$evts=Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2,3;StartTime=(Get-Date).AddHours(-24)} -MaxEvents 50 -EA Stop;$r=@();foreach($e in $evts){$lv=switch($e.Level){1{'crit'}2{'error'}3{'warn'}default{'info'}};$msg=$e.Message;if($msg.Length -gt 150){$msg=$msg.Substring(0,150)};$r+=@{time=$e.TimeCreated.ToString('HH:mm:ss');level=$lv;message=$msg}};$ec=($r|Where-Object{$_.level -in @('error','crit')}).Count;$wc=($r|Where-Object{$_.level -eq 'warn'}).Count;@{error_count=$ec;warn_count=$wc;entries=$r}|ConvertTo-Json -Depth 3}catch{@{error_count=0;warn_count=0;entries=@()}|ConvertTo-Json}""",

    "updates": """try{$u=Get-HotFix|Where-Object{$_.InstalledOn -gt (Get-Date).AddDays(-30)}|Sort-Object InstalledOn -Desc;$r=@();foreach($h in ($u|Select-Object -First 10)){$r+=@{id=$h.HotFixID;desc=$h.Description;date=$h.InstalledOn.ToString('yyyy-MM-dd')}};@{count=$u.Count;updates=$r}|ConvertTo-Json -Depth 3}catch{@{count=0;updates=@()}|ConvertTo-Json}""",

    "defender": """try{$d=Get-MpComputerStatus;@{enabled=[bool]$d.AntivirusEnabled;realtime=[bool]$d.RealTimeProtectionEnabled;sig_date=$d.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd HH:mm');sig_age=[math]::Round(((Get-Date)-$d.AntivirusSignatureLastUpdated).TotalDays,0);scan_date=$d.QuickScanEndTime.ToString('yyyy-MM-dd HH:mm');threats=$d.ThreatDetected}|ConvertTo-Json}catch{@{enabled=$false;realtime=$false;sig_date='N/A';sig_age=999;scan_date='N/A';threats=0}|ConvertTo-Json}""",

    "firewall": """$fw=@();foreach($p in (Get-NetFirewallProfile)){$fw+=@{name=$p.Name;enabled=[bool]$p.Enabled}};$fw|ConvertTo-Json""",

    "iis": """$iis=Get-Service W3SVC -EA SilentlyContinue;if($iis){@{installed=$true;status=$iis.Status.ToString();sites=@()}|ConvertTo-Json}else{@{installed=$false;status='NotInstalled';sites=@()}|ConvertTo-Json}""",
}

scripts["disk"] = """$disks = Get-WmiObject Win32_LogicalDisk -Filter 'DriveType=3'; $result = @(); foreach($d in $disks){ $pct = [math]::Round(($d.Size - $d.FreeSpace) / $d.Size * 100, 0); $result += @{DeviceID=$d.DeviceID; Size=[math]::Round($d.Size/1GB,1); Used=[math]::Round(($d.Size-$d.FreeSpace)/1GB,1); Free=[math]::Round($d.FreeSpace/1GB,1); Percent=$pct} }; $result | ConvertTo-Json"""

scripts["service"] = """$svcs=@(); foreach($n in @('sshd','W3SVC','wuauserv','WinDefend')){$s=Get-Service -Name $n -EA SilentlyContinue; if($s){$svcs+=@{name=$s.Name;status=$s.Status.ToString()}}else{$svcs+=@{name=$n;status='NotFound'}}}; $svcs|ConvertTo-Json"""

scripts["account"] = """Get-LocalUser | Select-Object Name, Enabled | ConvertTo-Json"""

scripts["admins"] = """try{Get-LocalGroupMember -Group 'Administrators' -EA Stop | Select-Object Name, ObjectClass | ConvertTo-Json}catch{'[]'}"""

for name, ps in scripts.items():
    enc = base64.b64encode(ps.encode('utf-16-le')).decode()
    print(f"=== {name} ===")
    print(enc)
    print()
