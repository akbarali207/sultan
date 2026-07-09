class AppConstants {
  // UZOQ (internet) manzil: doimiy domen (Cloudflare Tunnel orqali POS-PC'ga).
  // Bino tashqarisidan (uy/telefon) kirishda ishlatiladi.
  static const String remoteBaseUrl = 'https://sultanpos.net/api';

  // FAOL manzil — ilova ishga tushganda ApiService.resolveBase() aniqlaydi:
  //   restoran Wi-Fi'sida lokal POS-PC topilса -> lokal (internet shart emas),
  //   topilmasa -> remote (internet). Shu tufayli internet uzilса ham ishlaydi.
  static String _activeBaseUrl = remoteBaseUrl;
  static String get baseUrl => _activeBaseUrl;
  static set baseUrl(String v) => _activeBaseUrl = v;

  // Rasm/upload manzili — baseUrl host'i (api'siz). Masalan https://sultanpos.net
  static String get imageBase => baseUrl.replaceAll('/api', '');

  static const String login = '/auth/login';
  static const String verifyPassword = '/auth/verify-password';
  static const String faceCheckin = '/auth/face-checkin';
  static const String users = '/users';
  static const String roles = '/roles';
  static const String attendance = '/users/attendance';
  static const String menuCategories = '/menu/categories';
  static const String menuItems = '/menu/items';
  static const String ingredients = '/menu/ingredients';
  static const String menuRecipe = '/menu/recipe';
  static const String orders = '/orders';
  static const String tables = '/orders/tables';
  static const String expenses = '/expenses';
  static const String expenseTypes = '/expenses/types';
  static const String expenseOutflows = '/expenses/outflows';
  static const String dashboardReport = '/reports/dashboard';
  static const String dailyReport = '/reports/daily';
  static const String stockReport = '/reports/stock';
  static const String attendanceReport = '/reports/attendance';
  static const String reportSummary = '/reports/summary';
  static const String hikvisionEnroll = '/hikvision/enroll';
  static const String payrollReport = '/reports/payroll';
  static const String salaryPayments = '/reports/salary-payments';
  static const String salaryFines = '/reports/salary-fines';
  static const String salaryBonuses = '/reports/salary-bonuses';
  static const String lateFineOverride = '/reports/late-fine-override';
  static const String cashbox = '/reports/cashbox';
  static const String debts = '/reports/debts';
  static const String stock = '/stock';
  static const String stockIncoming = '/stock/incoming';
  static const String stockLow = '/stock/low';
  static const String warehouses = '/stock/warehouses';
  static const String stockAssignFromRecipe = '/stock/assign-from-recipe';
  static const String inventory = '/inventory';
  static const String tableware = '/tableware';
  static const String stations = '/stations';
  static const String printersList = '/print/printers'; // kompdagi o'rnatilgan printerlar (backenddan)
  static const String printTest = '/print/test'; // sinov cheki (printerni aniqlash)
  static const String rooms = '/rooms';
  static const String roomTables = '/rooms/tables';

  static const String roleAdmin = 'admin';
  static const String roleWaiter = 'waiter';
  static const String roleCashier = 'cashier';
}