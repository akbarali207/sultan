// Rol tekshiruvi — authMiddleware'dan KEYIN ishlatiladi (req.user.role mavjud bo'ladi).
// Misol: router.post('/', authMiddleware, requireRole('admin'), handler)
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user || !req.user.role) {
      return res.status(401).json({ message: 'Avtorizatsiya talab qilinadi' });
    }
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ message: 'Ruxsat yo\'q' });
    }
    next();
  };
}

module.exports = { requireRole };
