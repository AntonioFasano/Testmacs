;; Build according with (Ahk2Exe should be in path):
;; Ahk2Exe.exe /in testmacs.ahk /icon testmacs.ico /bin "Unicode 32-bit.bin"
;; or
;; Ahk2Exe.exe /in testmacs.ahk /icon testmacs.ico

EnvSet,  HOME,       %A_ScriptDir%\data
Run, bin\runemacs.exe -q --no-splash
