@echo off
setlocal DisableDelayedExpansion
set "project=%~dp0Prototype"
if not exist "%project%\project.godot" (
    echo Projet Godot introuvable dans Prototype.
    pause
    exit /b 1
)

for %%G in (
    "%GODOT_EXE%"
    "%~dp0Godot\Godot_v4.7.2-stable_win64.exe"
    "D:\Outils\Godot\Godot_v4.7.2-stable_win64.exe"
    "%LOCALAPPDATA%\Temp\FluvialStrike-Godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
) do (
    if exist "%%~G" (
        set "godot=%%~G"
        goto launch
    )
)
for /f "delims=" %%G in ('where.exe godot.exe 2^>nul') do (
    set "godot=%%G"
    goto launch
)
echo Godot introuvable. Place Godot 4.7.2 dans le dossier Godot a cote de ce lanceur,
echo ou indique le chemin de son executable avec la variable GODOT_EXE.
pause
exit /b 1

:launch
start "" "%godot%" --path "%project%" %*
exit /b %errorlevel%
