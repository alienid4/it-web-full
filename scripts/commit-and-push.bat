@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title 收工 - 提交 + 推 GitHub

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
echo  收工 SYNC: 提交本機改動 + 推 GitHub
echo  目錄: %CD%
echo ============================================
echo.

echo --- 改動清單 ---
git status -s

git status --porcelain | findstr "." >nul
if errorlevel 1 (
    echo (無改動)
    echo.
    echo --- 確保 origin 是最新 ---
    git push
    echo.
    echo === 沒改動,只 push 確認,結束 ===
    pause
    exit /b 0
)
echo.

echo --- 改動內容摘要 ---
git diff --stat HEAD
echo.

set "MSG="
set /p MSG=輸入 commit 訊息 (空白 = 取消):
if "!MSG!"=="" (
    echo 已取消,不會 commit。
    pause
    exit /b 1
)

echo.
echo --- git add ^& commit ---
git add -A
git commit -m "!MSG!"
if errorlevel 1 (
    echo.
    echo [錯誤] commit 被擋下,常見原因:
    echo   1. version.json 沒 bump (巡檢系統 hook)
    echo   2. 文件類 commit 可在訊息結尾加  [skip-version]
    echo.
    echo 範例: docs: 更新 SOP [skip-version]
    pause
    exit /b 1
)

echo.
echo --- git push ---
git push
if errorlevel 1 (
    echo.
    echo [錯誤] push 失敗,GitHub 上可能有另一台的新 commit
    echo 處理 (Git Bash): git pull --rebase  然後再執行此 BAT
    pause
    exit /b 1
)

echo.
echo --- 最近 3 個 commit ---
git log --oneline -3
echo.
echo === 收工完成,可以安心關機 ===
timeout /t 5 >nul
