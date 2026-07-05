@echo off
rem Kunlik zaxira: pg_dump + Firestore ko'zgusi (Task Scheduler har kuni 04:00 chaqiradi)
cd /d D:\sultan\backend
node backup-db.js >> D:\sultan\backups\backup.log 2>&1
