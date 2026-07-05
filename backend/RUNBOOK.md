# SULTAN — Favqulodda vaziyatlar qo'llanmasi (RUNBOOK)

> Chop etib kassa yoniga osib qo'ying. Har yangi xodimga bir marta ko'rsating.

## 1. Dastur ochilmayapti / "Server bilan aloqa yo'q"

1. Server kompyuterida `start-sultan.bat` ishlab turibdimi? Qora oyna yopilgan bo'lsa — qayta oching.
2. 1 daqiqa kutib ilovani qayta oching.
3. Bo'lmasa — **QOG'OZ REJIMIGA O'TING** (3-bo'lim) va egaga xabar bering.

## 2. Printer chek chiqarmayapti

1. Printer yoqilganmi, qog'oz bormi, USB/tarmoq kabeli joyidami?
2. Admin → Sozlamalar → "Printerlarni aniqlash" → sinov cheki.
3. Chek chiqmasa ham ZAKAZ SAQLANGAN — oshxonaga og'zaki ayting, keyin
   zakazni ochib "Hisob" tugmasi bilan qayta chiqaring.

## 3. QOG'OZ REJIMI (tizim butunlay ishlamay qolganda)

Kassada doim turishi kerak: raqamlangan qog'oz cheklar bloknoti + ruchka.

1. Har zakazni bloknotga yozing: **stol raqami, taomlar, soni, vaqt, ofitsant**.
2. To'lovni qabul qilganda: **summa, usul (naqd/karta), chegirma** ni yozing.
3. Qarz bo'lsa: **mijoz ism-familiyasi va telefoni** SHART.
4. Tizim qaytgach — HAR BIR qog'oz chekni tizimga kiriting (zakaz → to'lov),
   bloknotga "KIRITILDI" deb belgi qo'ying.
5. Kun oxirida kassani qo'lda sanab, tizimdagi "Kassa" bilan solishtiring.
   Farq bo'lsa — egaga ayting, o'zboshimchalik bilan "tuzatmang".

## 4. Baza (PostgreSQL) ishlamayapti

Belgi: server ochiq, lekin ilovada hamma narsa "xato" deydi.

1. Windows Services (services.msc) → `postgresql-x64-*` → Restart.
2. 2 daqiqada tiklanmasa — QOG'OZ REJIMI + egaga qo'ng'iroq.

## 5. Zaxiradan tiklash (faqat texnik odam)

Zaxiralar: `D:\sultan\backups\sultan_db_YYYY-MM-DD.dump` (har kuni 04:00 avtomatik).

```bash
# 1. Yangi bo'sh baza (agar eski buzilgan bo'lsa)
psql -U postgres -c "DROP DATABASE IF EXISTS sultan_db_old;"
psql -U postgres -c "ALTER DATABASE sultan_db RENAME TO sultan_db_old;"  # buzilganini saqlab qo'yamiz
psql -U postgres -c "CREATE DATABASE sultan_db;"

# 2. Oxirgi zaxirani tiklash
pg_restore -h localhost -U postgres -d sultan_db --no-owner "D:\sultan\backups\sultan_db_2026-07-03.dump"

# 3. Serverni qayta ishga tushirish va ilovada tekshirish
```

Zaxiradan KEYINGI ma'lumotlar (o'sha kun ichidagi zakazlar) yo'qoladi —
qog'oz cheklardan qayta kiritiladi (3-bo'lim, 4-band).

**MASHQ:** yilda kamida 1 marta test-kompyuterda tiklashni sinab ko'ring.
Sinalmagan zaxira — zaxira emas.

## 6. Internet yo'q (lokal tarmoq ishlayapti)

Hozirgi arxitekturada server RESTORANDA — ichki ish (zakaz, chek, kassa)
internet talab qilmaydi. Faqat:
- telefon orqali masofadan kirish ishlamaydi;
- Firestore ofsayt-nusxasi yangilanmaydi (internet qaytgach o'zi yangilanadi).

Hech narsa qilish shart emas.

## 7. Muhim raqamlar

- Egasi: ______________
- Texnik (dasturchi): ______________
- Internet-provayder: ______________
