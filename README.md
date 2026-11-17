# تعلم لغة (taallam-lugha)

تطبيق أندرويد لتعليم الإنجليزي للعرب بالصور والنطق.

## آخر نسخة للتجربة
https://github.com/almarefa2015-tech/taallam-lugha/releases/download/latest/app-release.apk

## المحتوى
- `content/a1_cards.json` — خطة كروت مستوى A1 (الكلمة/الجملة، المعنى بالعربي، البرومبت اللي اتعمل بيه الكارت في Gemini).
- `assets/content/a1.json` — محتوى التطبيق (بيتولد من الخطة).
- `assets/cards/<unit>/` — صور الكروت (3D كرتون، الكلمة مكتوبة تحت الصورة)، معمولة في Gemini.

| الوحدة | الموضوع | الكروت |
|---|---|---|
| u01_food | الطعام والشراب | 10 كلمات + 4 جمل |
| u02_animals | الحيوانات | 10 كلمات + 4 جمل |

## البناء
كل push على `main` (lib / assets / pubspec) بيشغّل GitHub Actions اللي بيبني الـ APK ويرفعه على الـ release اسمه `latest`.
