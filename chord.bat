@echo off
rem Chord 服务管理（双击运行 / 命令行: chord.bat start|stop|status|restart|logs [api|web|mysql]）
set BASH=
for %%P in ("C:\Program Files\Git\bin\bash.exe" "C:\Program Files (x86)\Git\bin\bash.exe") do (
  if exist %%~P set BASH=%%~P
)
if "%BASH%"=="" (
  echo 未找到 Git Bash，请安装 Git for Windows 或直接在 Git Bash 中运行: bash chord.sh %*
  pause
  exit /b 1
)
"%BASH%" "%~dp0chord.sh" %*
pause
