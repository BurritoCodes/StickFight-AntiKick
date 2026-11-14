param(
    [string]$DllPath = (Join-Path $PSScriptRoot "AntiKick.dll"),
    [string]$CecilPath = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $DllPath)) {
    throw "Target DLL not found: $DllPath"
}

if ([string]::IsNullOrEmpty($CecilPath)) {
    $candidates = @(
        "C:\Program Files (x86)\Steam\steamapps\common\StickFightTheGame\BepInEx\core\Mono.Cecil.dll",
        "D:\SteamLibrary\steamapps\common\StickFightTheGame\BepInEx\core\Mono.Cecil.dll",
        "E:\SteamLibrary\steamapps\common\StickFightTheGame\BepInEx\core\Mono.Cecil.dll",
        (Join-Path $PSScriptRoot "Mono.Cecil.dll")
    )
    $regSteam = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
    if ($regSteam) {
        $candidates = @((Join-Path ($regSteam -replace '/', '\') "steamapps\common\StickFightTheGame\BepInEx\core\Mono.Cecil.dll")) + $candidates
    }
    $CecilPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $CecilPath -or -not (Test-Path $CecilPath)) {
    throw "Mono.Cecil.dll not found. Pass -CecilPath <path-to-Mono.Cecil.dll>."
}

Add-Type -Path $CecilPath

$resolvedDll = (Resolve-Path $DllPath).Path
$fileInfo = Get-Item $resolvedDll
$sha256 = (Get-FileHash -Path $resolvedDll -Algorithm SHA256).Hash

Write-Output "=== Binary Identity ==="
Write-Output ("File:   {0}" -f $fileInfo.Name)
Write-Output ("Bytes:  {0}" -f $fileInfo.Length)
Write-Output ("SHA256: {0}" -f $sha256)
Write-Output ""

$rp = New-Object Mono.Cecil.ReaderParameters
$rp.ReadWrite = $false
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($resolvedDll, $rp)
$mod = $asm.MainModule

$asmRefs = @($mod.AssemblyReferences | ForEach-Object { $_.FullName } | Sort-Object -Unique)
$typeRefs = @($mod.GetTypeReferences() | ForEach-Object { $_.FullName } | Sort-Object -Unique)
$memberRefs = @($mod.GetMemberReferences() | ForEach-Object { $_.FullName } | Sort-Object -Unique)

Write-Output ("=== Assembly References ({0}) ===" -f $asmRefs.Count)
foreach ($r in $asmRefs) { Write-Output "  $r" }
Write-Output ""

Write-Output ("=== Type References ({0}) ===" -f $typeRefs.Count)
foreach ($t in $typeRefs) { Write-Output "  $t" }
Write-Output ""

Write-Output ("=== Member References ({0}) ===" -f $memberRefs.Count)
foreach ($m in $memberRefs) { Write-Output "  $m" }
Write-Output ""

function Get-AllTypes([Mono.Cecil.ModuleDefinition]$module) {
    $all = New-Object System.Collections.Generic.List[Mono.Cecil.TypeDefinition]
    $queue = New-Object System.Collections.Generic.Queue[Mono.Cecil.TypeDefinition]
    foreach ($t in $module.Types) { $queue.Enqueue($t) }
    while ($queue.Count -gt 0) {
        $cur = $queue.Dequeue()
        $all.Add($cur)
        foreach ($nt in $cur.NestedTypes) { $queue.Enqueue($nt) }
    }
    return $all
}

$allTypes = Get-AllTypes $mod
$pinvokeHits = New-Object System.Collections.Generic.List[string]
$steamIdHits = New-Object System.Collections.Generic.List[string]
$ldstrTexts = New-Object System.Collections.Generic.List[string]

foreach ($t in $allTypes) {
    foreach ($m in $t.Methods) {
        if ($m.HasPInvokeInfo -or $m.IsPInvokeImpl) {
            $pinvokeHits.Add($m.FullName)
        }
        if ($m.HasBody) {
            foreach ($ins in $m.Body.Instructions) {
                if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldc_I8) {
                    $val = [long]$ins.Operand
                    if ($val -ge 76561190000000000L -and $val -le 76561209999999999L) {
                        $steamIdHits.Add(("{0} -> {1}" -f $m.FullName, $val))
                    }
                }
                elseif ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Ldstr) {
                    $ldstrTexts.Add(("{0}: {1}" -f $m.FullName, [string]$ins.Operand))
                }
            }
        }
    }
}

$attrTexts = New-Object System.Collections.Generic.List[string]
function Collect-CustomAttrStrings($provider, [string]$ownerLabel) {
    if (-not $provider.HasCustomAttributes) { return }
    foreach ($ca in $provider.CustomAttributes) {
        foreach ($arg in $ca.ConstructorArguments) {
            if ($arg.Value -is [string]) {
                $attrTexts.Add(("{0} [{1}]: {2}" -f $ownerLabel, $ca.AttributeType.Name, $arg.Value))
            }
        }
        foreach ($f in $ca.Fields) {
            if ($f.Argument.Value -is [string]) {
                $attrTexts.Add(("{0} [{1}.{2}]: {3}" -f $ownerLabel, $ca.AttributeType.Name, $f.Name, $f.Argument.Value))
            }
        }
        foreach ($p in $ca.Properties) {
            if ($p.Argument.Value -is [string]) {
                $attrTexts.Add(("{0} [{1}.{2}]: {3}" -f $ownerLabel, $ca.AttributeType.Name, $p.Name, $p.Argument.Value))
            }
        }
    }
}

Collect-CustomAttrStrings $asm "Assembly"
Collect-CustomAttrStrings $mod "Module"
foreach ($t in $allTypes) {
    Collect-CustomAttrStrings $t ("Type:" + $t.FullName)
    foreach ($f in $t.Fields) { Collect-CustomAttrStrings $f ("Field:" + $f.FullName) }
    foreach ($m in $t.Methods) { Collect-CustomAttrStrings $m ("Method:" + $m.FullName) }
}

$allImports = @($typeRefs + $memberRefs)

$ioHits = @($allImports | Where-Object { $_ -match '(^|[ /:])System\.IO(\.|/|$)' })
$netHits = @($allImports | Where-Object { $_ -match '(^|[ /:])(System\.Net|System\.Web|UnityEngine\.Networking|UnityEngine\.WWW|.*\.HttpClient\b|.*\.WebClient\b|.*\.WebRequest\b|.*\.Sockets\b)' })
$procHits = @($allImports | Where-Object { $_ -match '(^|[ /:])(System\.Diagnostics\.Process|System\.Environment\b)' })
$regMarshalHits = @($allImports | Where-Object { $_ -match '(^|[ /:])(Microsoft\.Win32|System\.Runtime\.InteropServices\.Marshal)' })
$dynCodeHits = @($allImports | Where-Object {
    $_ -match 'System\.Reflection\.Assembly::Load' -or
    $_ -match '(^|[ /:])System\.AppDomain\b' -or
    $_ -match 'System\.Activator::CreateInstance' -or
    $_ -match 'System\.Type::GetType\(' -or
    $_ -match 'System\.Reflection\.MethodBase::Invoke\(' -or
    $_ -match 'System\.Reflection\.MethodInfo::Invoke\(' -or
    $_ -match 'System\.Reflection\.ConstructorInfo::Invoke\(' -or
    $_ -match '(^|[ /:])System\.Reflection\.Emit\b' -or
    $_ -match '(^|[ /:])System\.Security\.Cryptography\b'
})

$leakPattern = '(Users\\|C:\\|https?://|discord|webhook)'
$leakHits = New-Object System.Collections.Generic.List[string]
foreach ($s in $ldstrTexts) {
    if ($s -match $leakPattern) { $leakHits.Add("IL ldstr -> " + $s) }
}
foreach ($s in $attrTexts) {
    if ($s -match $leakPattern) { $leakHits.Add("Attribute -> " + $s) }
}

$asm.Dispose()

$failures = 0
function Report-Check([int]$num, [string]$name, [string[]]$hits) {
    $count = if ($hits) { $hits.Count } else { 0 }
    if ($count -eq 0) {
        Write-Output ("[PASS] {0}. {1} (0 hits)" -f $num, $name)
    }
    else {
        $script:failures++
        Write-Output ("[FAIL] {0}. {1} ({2} hits)" -f $num, $name, $count)
        foreach ($h in $hits) { Write-Output ("       -> {0}" -f $h) }
    }
}

Write-Output "=== Safety Audit Checks ==="
Report-Check 1 "Zero File I/O References (System.IO.*)" $ioHits
Report-Check 2 "Zero Network / Web / Socket References" $netHits
Report-Check 3 "Zero Process / Shell / OS Environment References" $procHits
Report-Check 4 "Zero Registry / Native P-Invoke / Unmanaged Memory" @($regMarshalHits + $pinvokeHits)
Report-Check 5 "Zero Dynamic Code Loading / Arbitrary Reflection Execution" $dynCodeHits
Report-Check 6 "Zero Hardcoded SteamID64 Backdoors (ldc.i8 7656119..7656120)" @($steamIdHits)
Report-Check 7 "Zero Leaked Local Paths or URLs (Users\, C:\, http/https, discord, webhook)" @($leakHits)
Write-Output ""

if ($failures -gt 0) {
    Write-Output ("AUDIT FAILED: {0} check(s) failed." -f $failures)
    exit 1
}

Write-Output "AUDIT PASSED: All 7 safety checks passed with 0 violations."
exit 0
