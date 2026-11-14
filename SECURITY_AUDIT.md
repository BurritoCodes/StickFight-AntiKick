# AntiKick.dll safety check

the dll is obfuscated so source isnt public, but .net still stores every external library it imports in the header. so you can check what it actually has access to without needing the source.

file: `AntiKick.dll` (43520 bytes)
sha256: `3445BC9466FD3625E70A672E61B39C86C3F5F6A929843B83101DF718CF39B929`

if you have bepinex installed, [verify-safety.ps1](verify-safety.ps1) uses `Mono.Cecil.dll` from your stick fight folder to scan all references and instructions:

    Get-FileHash .\AntiKick.dll -Algorithm SHA256
    powershell -NoProfile -File .\verify-safety.ps1 -DllPath .\AntiKick.dll

output on this build (0 hits on everything):
- no System.IO / file access
- no System.Net / web / sockets
- no Process / shell / environment calls
- no registry / native P-Invoke / Marshal
- no Assembly.Load / dynamic code loading
- no hardcoded SteamID64 backdoors
- no leaked local paths or urls

you can also just check the sha256 on virustotal or open it in ilspy/dnspy to look at the references yourself. only 7 dlls are imported (`0Harmony`, `Assembly-CSharp`, `Assembly-CSharp-firstpass`, `BepInEx`, `mscorlib`, `System`, `UnityEngine`) with 68 types and 94 members total.
