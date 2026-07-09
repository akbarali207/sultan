@echo off
REM ============================================================
REM  SULTAN POS - ishga tushirish skripti (POS-PC uchun)
REM  Bu skript backendni ishga tushiradi. Backend o'z ichida:
REM    - migratsiyalarni qo'llaydi
REM    - print-agent'ni ishga tushiradi
REM    - Hikvision davomat pollerini yoqadi
REM  PostgreSQL Windows xizmati sifatida avtomatik ishlashi kerak.
REM  Cloudflare Tunnel alohida xizmat (pastdagi qatorни oching, kerak bo'lsa).
REM ============================================================
cd /d D:\sultan\backend

REM Backendni alohida oynada ishga tushiramiz (yopilmasin):
start "Sultan Backend" cmd /k node src\index.js

REM --- Cloudflare Tunnel XIZMAT sifatida o'rnatilmagan bo'lsa, quyini oching: ---
REM start "Cloudflare Tunnel" cloudflared tunnel run sultan

echo Sultan POS ishga tushdi. Bu oynani yopsangiz bo'ladi.
timeout /t 4 >nul
