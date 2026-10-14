@echo off
rem Lance deux fenetres du jeu sur ce PC : un hote et un ami connecte en local.
rem Adapter GODOT si Godot est ailleurs.
set GODOT=%USERPROFILE%\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe
set PROJET=%~dp0..
start "Nervous - hote" "%GODOT%" --path "%PROJET%" --position 0,40 --resolution 960x540 -- --host --players=4 --humans=2
timeout /t 3 /nobreak > nul
start "Nervous - ami" "%GODOT%" --path "%PROJET%" --position 960,40 --resolution 960x540 -- --join=127.0.0.1
