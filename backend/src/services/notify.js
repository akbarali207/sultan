// ============================================================
// Bildirishnoma interfeysi (Faza 1 zamini -> Faza 3 FCM).
//
// Butun tizim bildirishnomani FAQAT shu modul orqali yuboradi — provayder
// almashsa (console -> FCM -> ntfy) biznes-kod O'ZGARMAYDI.
//
// FCM ulash (kelajakda, ~1 kun ish):
//   1. npm install firebase-admin
//   2. Firebase konsolda service account kaliti -> .env: GOOGLE_APPLICATION_CREDENTIALS
//   3. Quyidagi providers ro'yxatiga fcm provayderini qo'shish:
//        const admin = require('firebase-admin');
//        admin.initializeApp();
//        { name: 'fcm', send: (n) => admin.messaging().send({
//            topic: n.topic || 'owner',
//            data: { title: n.title, body: n.body, entity: n.entity || '' },
//          }) }
//   Android ilova (com.sultan.sultan) firebase_messaging bilan 'owner'
//   topic'iga obuna bo'ladi. PUL YO'LIGA HECH QACHON ULANMAYDI — faqat xabar.
// ============================================================

const providers = [
  {
    name: 'console',
    send: async (n) => console.log(`[notify] ${n.title}${n.body ? ' — ' + n.body : ''}`),
  },
];

// n: { title, body?, topic?, entity? }
// Hech qachon throw qilmaydi — bildirishnoma xatosi asosiy ishni to'xtatmasin.
async function notify(n) {
  for (const p of providers) {
    try {
      await p.send(n);
    } catch (e) {
      console.log(`[notify] ${p.name} xatosi:`, e.message);
    }
  }
}

module.exports = { notify };
