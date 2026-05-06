@echo off
chcp 65001 >nul
title 開工 - 拉最新版 + 開 VS Code

REM === 自動偵測 ClaudeHome 位置 (NB=C:\ / PC=F:\) ===
set "TARGET="
if exist "F:\ClaudeHome\CL_webit\.git" set "TARGET=F:\ClaudeHome\CL_webit"
if exist "C:\ClaudeHome\CL_webit\.git" set "TARGET=C:\ClaudeHome\CL_webit"
if not defined TARGET (
    echo [錯誤] 找不到 CL_webit
    echo 已試: F:\ClaudeHome\CL_webit  ^|  C:\ClaudeHome\CL_webit
    pause
    exit /b 1
)
cd /d "%TARGET%"

echo ============================================
echo  開工 SYNC: 拉 GitHub 最新版
echo  目錄: %CD%
echo ============================================
echo.

echo --- 拉之前的本機狀態 ---
git status -sb
echo.

echo --- git pull ---
git pull
if errorlevel 1 (
    echo.
    echo [警告] pull 失敗,本機有未 commit 改動或衝突
    echo 處理方式 ^(在 Git Bash 跑^):
    echo   保留改動再拉:  git stash; git pull; git stash pop
    echo   丟掉改動再拉:  git checkout .; git pull
    pause
    exit /b 1
)
echo.

echo --- 最近 5 個 commit ---
git log --oneline -5
echo.

echo --- 開啟 VS Code ---
where code >nul 2>nul
if errorlevel 1 (
    echo [跳過] VS Code 不在 PATH,改成只開檔總管
    start "" "%CD%"
) else (
    start "" code .
)

echo.
echo === 開工完成 ===
echo (此視窗 5 秒後自動關閉)
timeout /t 5 >nul
