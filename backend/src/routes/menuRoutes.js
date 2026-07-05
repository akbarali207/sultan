const express = require('express');
const router = express.Router();
const authMiddleware = require('../middleware/authMiddleware');
const { requireRole } = require('../middleware/roleMiddleware');
const adminOnly = requireRole('admin');
const upload = require('../middleware/uploadMiddleware');
const {
  getCategories, createCategory, updateCategory, deleteCategory,
  getMenuItems, createMenuItem, updateMenuItem, deleteMenuItem, setMenuAvailability, setDailyTracked, getMenuItemCost,
  createPfItem,
  getIngredients, createIngredient,
  getRecipe, addRecipeItem, updateRecipeItem, deleteRecipeItem
} = require('../controllers/menuController');

// O'qish — barcha xodimlar (ofitsant menyuni ko'radi). Yozish — faqat admin.
router.get('/categories', authMiddleware, getCategories);
router.post('/categories', authMiddleware, adminOnly, createCategory);
router.put('/categories/:id', authMiddleware, adminOnly, updateCategory);
router.delete('/categories/:id', authMiddleware, adminOnly, deleteCategory);

router.get('/items', authMiddleware, getMenuItems);
router.get('/items/:id/cost', authMiddleware, adminOnly, getMenuItemCost);
router.post('/items', authMiddleware, adminOnly, upload.single('image'), createMenuItem);
router.put('/items/:id', authMiddleware, adminOnly, upload.single('image'), updateMenuItem);
router.put('/items/:id/available', authMiddleware, adminOnly, setMenuAvailability); // stop-list
router.put('/items/:id/daily-track', authMiddleware, adminOnly, setDailyTracked); // kunlik kuzat belgisi
router.delete('/items/:id', authMiddleware, adminOnly, deleteMenuItem);

router.get('/ingredients', authMiddleware, adminOnly, getIngredients);
router.post('/ingredients', authMiddleware, adminOnly, createIngredient);

router.post('/pf', authMiddleware, adminOnly, createPfItem); // polufabrikat yaratish

router.get('/recipe/:id', authMiddleware, adminOnly, getRecipe);
router.post('/recipe', authMiddleware, adminOnly, addRecipeItem);
router.put('/recipe/:id', authMiddleware, adminOnly, updateRecipeItem);
router.delete('/recipe/:id', authMiddleware, adminOnly, deleteRecipeItem);

module.exports = router;