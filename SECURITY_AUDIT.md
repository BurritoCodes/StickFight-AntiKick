# AntiKick.dll safety check

the dll is obfuscated so source isnt public, but .net still stores every external library it imports in the header. so you can check what it actually has access to without needing the source.

file: `AntiKick.dll` (42496 bytes)
sha256: `D858C40413F00B157F7932429AC5079A196CB39B622319103E6443119B843999`

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

you can also just check the sha256 on virustotal or open it in ilspy/dnspy to look at the references yourself. only 7 dlls are imported (`0Harmony`, `Assembly-CSharp`, `Assembly-CSharp-firstpass`, `BepInEx`, `mscorlib`, `System`, `UnityEngine`) with 64 types and 85 members total.
