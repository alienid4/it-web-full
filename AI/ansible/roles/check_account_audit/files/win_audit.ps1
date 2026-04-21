$today = Get-Date
$builtIn = @('Administrator','Guest','DefaultAccount','WDAGUtilityAccount','krbtgt')
$result = @()
foreach($u in (Get-LocalUser)) {
    if ($builtIn -contains $u.Name) { continue }
    $pwAge = 9999
    if ($u.PasswordLastSet) { $pwAge = [math]::Round(($today - $u.PasswordLastSet).TotalDays, 0) }
    $loginAge = 9999
    if ($u.LastLogon) { $loginAge = [math]::Round(($today - $u.LastLogon).TotalDays, 0) }
    $pwExpired = $false
    $pwExpires = 'Never'
    if ($u.PasswordExpires) {
        $pwExpires = $u.PasswordExpires.ToString('yyyy-MM-dd')
        if ($u.PasswordExpires -lt $today) { $pwExpired = $true }
    }
    $result += @{
        user = $u.Name
        uid = $u.SID.Value
        enabled = [bool]$u.Enabled
        pw_last_change = if($u.PasswordLastSet){$u.PasswordLastSet.ToString('yyyy-MM-dd')}else{'Never'}
        pw_expires = $pwExpires
        last_login = if($u.LastLogon){$u.LastLogon.ToString('yyyy-MM-dd HH:mm')}else{'Never'}
        pw_age_days = $pwAge
        login_age_days = $loginAge
        pw_expired = $pwExpired
        locked = if($u.Enabled){''}else{'L'}
    }
}
$result | ConvertTo-Json -Depth 3
