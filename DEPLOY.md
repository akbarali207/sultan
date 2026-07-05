# Sultan — Bulutga joylash qo'llanmasi (Hetzner CPX31)

Arxitektura: **gibrid** — bulutda backend + PostgreSQL; restoranda lokal "ko'prik"
(Face ID qurilma 192.0.0.64 + printer) bulutga ulanadi.

---

## 1-QADAM — Hetzner server ochish (SIZ qilasiz, karta kerak)

1. https://www.hetzner.com/cloud → **Sign Up** (xalqaro karta bilan).
2. **New Project** → nom: `sultan`.
3. **Add Server**:
   - **Location:** Helsinki (Finlandiya) yoki Nuremberg — Bishkekka eng yaqin sifatlilari.
   - **Image:** Ubuntu **24.04**.
   - **Type:** **CPX31** (4 vCPU / 8 GB / 160 GB NVMe).
   - **SSH Key:** kompyuteringizdagi kalitni qo'shing
     (`ssh-keygen -t ed25519` → `~/.ssh/id_ed25519.pub` ichini nusxa qiling). Parol o'rniga shu — xavfsizroq.
   - **Backups:** ✅ yoqing (+20%, kunlik avtomatik zaxira).
   - **Create & Buy now**.
4. Server **IP manzili**ni oling (masalan `91.x.x.x`).

## 2-QADAM — Domen (ixtiyoriy, lekin tavsiya)

- Namecheap/GoDaddy'dan `.com` oling (~$12/yil), masalan `sultanpos.com`.
- DNS → **A record**: `@` va `api` → server IP.
- Domen bo'lmasa: Hetzner IP bilan ham ishlaydi (HTTPS uchun domen yaxshiroq).

## 3-QADAM — Serverni sozlash (MEN tayyorlab beraman / siz ishga tushirasiz)

Server ochilgach menga **IP** va **domen**ni yuboring. Quyidagilarni sozlaymiz:

```bash
# Serverga ulanish
ssh root@<SERVER_IP>

# Tizim + Node 20 + PostgreSQL 16 + nginx + certbot + pm2
apt update && apt upgrade -y
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs
apt install -y postgresql nginx certbot python3-certbot-nginx ufw git

# PostgreSQL: baza + KUCHLI parol
sudo -u postgres psql -c "CREATE DATABASE sultan;"
sudo -u postgres psql -c "CREATE USER sultan WITH PASSWORD '<KUCHLI_PAROL>';"
sudo -u postgres psql -c "GRANT ALL ON DATABASE sultan TO sultan;"

# Firewall
ufw allow OpenSSH && ufw allow 'Nginx Full' && ufw --force enable
```

- **App kodi serverga:** git remote ochamiz (GitHub private) yoki zip bilan yuboramiz.
- **Baza ko'chirish:** lokal bazadan `pg_dump` → serverga import (menyu, xodimlar, stollar saqlanadi; test ma'lumotlar allaqachon toza).
- **`.env` (production):** kuchli `DB parol`, `JWT_SECRET`, `HIK_EVENT_TOKEN`, `PRINT_AGENT_TOKEN`.
- **nginx + HTTPS:** `certbot --nginx -d api.sultanpos.com` → bepul SSL.
- **pm2:** `pm2 start src/index.js --name sultan-api && pm2 startup && pm2 save` (server qayta yonsa avtomatik ishga tushadi).
- **Backup:** kunlik `pg_dump` cron + Hetzner snapshot.

## 4-QADAM — Lokal ko'prik (restoran PC'sida)

- **Print-agent** shu yerda ishlaydi (USB/IP printerga chek yuboradi) — bulut API'dan `pending` cheklarni oladi.
- **Face ID ko'prik** — qurilma (192.0.0.64) hodisalarini o'qib bulut `/api/hikvision/event` ga POST qiladi (`HIK_EVENT_TOKEN` bilan).
- Restoran PC'sida Windows xizmati (auto-start) qilamiz.

## 5-QADAM — Ilovani bulutga ulash

- `lib/core/constants.dart` → `baseUrl = 'https://api.sultanpos.com/api'` (hozir `127.0.0.1`).
- `flutter build windows` → restoran PC'lariga `.exe` tarqatish.
- Egasi/ofitsantlar telefondan ham (kelajakda mobil build) yoki PC'dan kiradi.

---

## Xavfsizlik holati (bulutdan oldin TAYYOR ✅)
- Rollar (admin/kassir/ofitsant) backend'da cheklangan; ofitsant faqat o'zinikini ko'radi.
- Kuchli JWT_SECRET, HIK/PRINT tokenlar.
- Kassa parol bilan himoyalangan.
- **Bulutda:** yangi kuchli DB parol qo'yiladi (lokal dev parol ishlatilmaydi).

## Taxminiy oylik xarajat
- Hetzner CPX31 + backup: **~€19/oy**
- Domen: ~$12/yil (~$1/oy)
- **Jami: ~$22/oy** — bitta restoran uchun arzon, katta zaxira quvvat bilan.
