# מערכת נוכחות נהגים (NFC)

נהג מקרב את הטלפון לתג במשאית, הטלפון פותח קישור, והמערכת רושמת כניסה או יציאה (לפי הסריקה הקודמת) עם שעה, מספר משאית ומיקום GPS.

## מבנה
- `supabase/schema.sql` – מסד הנתונים והאבטחה
- `docs/index.html` – דף ההחתמה של הנהג (נפתח מהתג)
- `docs/admin.html` – מסך המנהל
- `docs/config.js` – פרטי החיבור ל-Supabase

## הקמה (כ-30 דקות)

### 1. מסד נתונים – Supabase
1. נרשמים ב-https://supabase.com ויוצרים פרויקט (אזור: Frankfurt). תוכנית Pro עולה כ-25$ לחודש, אבל גם החינמית מספיקה ל-70 נהגים.
2. **SQL Editor** → מדביקים את כל `supabase/schema.sql` → **Run**.
3. **Authentication → Sign In / Providers**: מכבים את **Allow new users to sign up**.
4. **Authentication → Users → Add user**: יוצרים משתמש מנהל (אימייל + סיסמה).
5. חוזרים ל-SQL Editor ומריצים (עם האימייל שלך):
   ```sql
   insert into admins (user_id) select id from auth.users where email = 'manager@example.com';
   ```
6. **Project Settings → API**: מעתיקים את `Project URL` ואת `anon public key` לתוך `docs/config.js`.

### 2. אחסון האתר – Netlify
1. נרשמים ב-https://app.netlify.com.
2. **Add new site → Deploy manually** וגוררים את התיקייה `docs`.
3. מקבלים כתובת כמו `https://my-attendance.netlify.app` (אפשר לשנות שם בהגדרות האתר).

### 3. הוספת נהגים
נכנסים ל-`https://YOUR-SITE/admin.html`, לשונית **נהגים**, ומוסיפים לכל נהג שם, טלפון וקוד אישי.

### 4. צריבת התגים
1. בלשונית **קישורים לתגים** מופיע קישור לכל משאית, למשל `https://YOUR-SITE/?truck=12`.
2. מתקינים בטלפון את האפליקציה **NFC Tools** (חינם).
3. Write → Add a record → URL → מדביקים את הקישור → Write → מקרבים לתג.
4. מומלץ לנעול את התג (Other → Lock tag) כדי שלא ישנו אותו.

### 5. הנהג – פעם ראשונה
סורק את התג, מזין טלפון וקוד אישי, ומאז כל סריקה = החתמה. אם הנהג החליף טלפון: במסך המנהל לוחצים **אפס טלפון**.

## הערות
- **אייפון**: סורק NFC אוטומטית מאייפון XS ומעלה. **Android**: צריך ש-NFC יהיה מופעל.
- אם הנהג מנקה את נתוני הדפדפן הוא יתבקש להירשם שוב עם הקוד.
- סריקה כפולה בתוך דקה לא נרשמת פעמיים.
- כניסה שלא נסגרה ביציאה תוך 16 שעות נחשבת "משמרת חסרה" בדוח, והסריקה הבאה תירשם ככניסה חדשה.
