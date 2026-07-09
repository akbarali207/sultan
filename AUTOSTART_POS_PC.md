# POS-PC — avtomatik yonish + internetsiz ishlash sozlamasi

> Maqsad: **kompyuter yonganda** tunnel + backend + baza **o'zi ishga tushsin**, va
> **internet uzilса ham** restoran Wi-Fi'sida kassalar/ofitsantlar ishlayversin.
> Buni POS-PC'da **bir marta** sozlaysiz.

---

## 1-qism. Avtomatik yonish (3 ta komponent)

Ishlashi kerak bo'lgan 3 narsa: **PostgreSQL** (baza), **Backend** (server), **Cloudflare Tunnel** (uzoqdan kirish).

### 1.1. PostgreSQL — odatda tayyor
PostgreSQL o'rnatilganda Windows xizmati sifatida **o'zi avtomatik yonadi**.
Tekshirish: `Win+R` → `services.msc` → `postgresql-x64-…` → **Startup type = Automatic**.

### 1.2. Backend — 2 variant

**A variant (TAVSIYA) — Windows xizmati (login shart emas, crash'da qayta yonadi).**
NSSM (nssm.cc) yuklab oling, keyin `cmd`ni **administrator** sifatida ochib:
```
nssm install SultanBackend "C:\Program Files\nodejs\node.exe" "D:\sultan\backend\src\index.js"
nssm set SultanBackend AppDirectory "D:\sultan\backend"
nssm set SultanBackend Start SERVICE_AUTO_START
nssm start SultanBackend
```
Backend o'z ichida **print-agent**ni ham, **migratsiyalar**ni ham ishga tushiradi.

**B variant (ODDIY) — Startup papkasi (login qilinganda yonadi).**
`Win+R` → `shell:startup` → ochilgan papkaga **`start_sultan.bat`** faylining yorlig'ini (shortcut) tashlang.

### 1.3. Cloudflare Tunnel — xizmat sifatida
Uzoqdan (`sultanpos.net`) kirish uchun. `cmd`ni administrator sifatida:
```
cloudflared service install
```
(agar token bilan o'rnatilgan bo'lsa, u avtomatik yonadi). Bu **faqat internet bor**da kerak — ichki ishlash unga bog'liq emas.

---

## 2-qism. Internetsiz ishlash (lokal Wi-Fi)

Server POS-PC'da turibdi. Internet uzilса ham, boshqa kassalar **shu POS-PC'ga Wi-Fi orqali** ulanadi.

### 2.1. POS-PC'ning lokal IP'sini aniqlang
`cmd` → `ipconfig` → **IPv4 Address** (masalan `192.168.1.10`). Bu manzilni yozib oling.

> Maslahat: routerда shu POS-PC'ga **doimiy IP** (DHCP reservation) qo'ying — IP o'zgarib ketmaydi.

### 2.2. Har bir kassa/ofitsant qurilmasida manzilni kiriting
Ilovaning **login ekrani** → o'ng-yuqoridagi ⚙ (server) tugmasi → **POS-PC manzili** ga `192.168.1.10` yozing → **Saqlash va sinash**.
- Yashil "Lokal (Wi-Fi) ✓" chiqsa — internetsiz ham ishlaydi.
- Ilova o'zi: **avval lokalni**, topolmasa **internetni** sinaydi (avtomatik almashinuv).

### 2.3. Web (brauzer) kassalar uchun MUHIM
Agar kassa **brauzerda** ishlasa, ichkarida sahifани **lokal manzildan** oching:
`http://192.168.1.10:3000` (￼`sultanpos.net`dan emas — u internet talab qiladi).
> **O'rnatilgan ilova (Windows/Android)** bo'lsa bu muammo yo'q — shuni tavsiya qilaman.

---

## 3-qism. Tekshirish
1. Internetni o'chiring (Wi-Fi router yoniq qolsin).
2. Kassada zakaz yarating → ishlashi kerak (lokal orqali).
3. Brauzerdan sinash: `http://192.168.1.10:3000/api/health` → `{"ok":true}` chiqsa server tirik.

## Cheklov (halol)
- POS-PC **o'chsa** yoki Wi-Fi'dan uzilса — hech kim ishlay olmaydi (server o'sha yerda).
- To'liq mustaqil (har kassa o'zi, POS-PC ham o'chsa) ishlash — bu **Daraja 2 (offline-first)**, alohida katta ish.
