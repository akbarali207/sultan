@echo off
REM ============================================
REM  SULTAN POS - server + tunnel ishga tushirish
REM  (komp yonganda avtomatik ishlaydi - Startup papkasi orqali)
REM ============================================

REM 1) Backend (Node) - alohida oynada (chek bosish YONIQ)
cd /d D:\sultan\backend
start "Sultan Backend" /min cmd /k node src\index.js

REM 2) Backend tayyor bo'lishini kutamiz
timeout /t 4 /nobreak >nul

REM 3) Cloudflare Tunnel (sultanpos.net) - alohida oynada
cd /d D:\sultan
start "Sultan Tunnel" /min cmd /k cloudflared.exe --config "C:\Users\OMEN\.cloudflared\config.yml" tunnel run sultan

exit
