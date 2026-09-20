# 🎵 Carrozzeria Tube (Android)

Pioneer Carrozzeria avtomobil magnitolalari va kiber audiotizimlari estetikasida yaratilgan, YouTube'dan musiqalarni qidirish, trenddagi qo'shiqlarni tinglash, professional Carrozzeria ekvalayzer sozlamalarini boshqarish hamda telefon ekrani o'chganda (qulflanganda) yoki boshqa ilovalarga o'tganda **fondan uzluksiz** ijro etish imkoniyatiga ega bo'lgan zamonaviy Android ilovasi.

---

## 🌟 Asosiy Imkoniyatlar

1. **Fon va Qulf Ekranida Uzluksiz Ishlash (Background Playback)**:
   - `AndroidX Media3 (ExoPlayer + MediaSessionService)` asosidagi Foreground Service.
   - `WAKE_LOCK` va `WIFI_LOCK` orqali tizim ilovani o'chirib qo'yishining oldi olinadi.
   - Telefon qulf ekrani (Lock screen) va bildirishnomalar panelida Carrozzeria pleyer boshqaruvi.
   - Boshqa ilovalarga (Telegram, Instagram, PUBG va h.k.) o'tganda musiqa to'xtovsiz davom etadi.

2. **2 Xil Carrozzeria Dizayn Temasi (Sozlamalardan tanlanadi)**:
   - **Classic OEL Retro (2000-yillar Pioneer)**: Pikselli VFD displey, suzuvchi kiber delfin animatsiyasi, 16 polosali OEL ustunlar, neon firuza ranglar (DEH-P88RS / MEH-P9000 uslubi).
   - **Cyber Navi Modern**: Zamonaviy sensorli avtomobil displeyi, dinamik HUD gradyentlari, amber va kiber moviy neon chiziqlar.

3. **Kichik Video Ekrani (Mini Video Bezel / V-OUT)**:
   - Carrozzeria magnitolasining korpusiga joylashtirilgan mini video oynasi.
   - Bitta tugma bilan OEL Spektr analizatori va Kichik Video rejimi o'rtasida almashish.

4. **Carrozzeria Audio DSP & Professional Ekvalayzer**:
   - **Ekvalayzer Rejimlari**: `POWERFUL`, `NATURAL`, `VOCAL`, `FLAT`, `SUPER BASS`, `CUSTOM 1`, `CUSTOM 2`.
   - **ASR (Advanced Sound Retriever)**: YouTube'ning siqilgan audio chastotalarini sun'iy ravishda qayta tiklash (High harmonic excitation).
   - **Loudness**: Past ovoz balandligida bass va treble chastotalarni mustahkamlash.
   - **Super Todoroki Bass / Subwoofer Control**: Kuchli klub bass effekti.
   - **SLA (Source Level Adjuster)**: Ovoz darajasini avtomatik moslashtirish.

5. **YouTube Trendlari va Qidiruv**:
   - O'zbekiston va xalqaro eng sara trend musiqalari avtomatik yuklanadi.
   - Tezkor qidiruv orqali istalgan qo'shiq, ijrochi va videoni topish mumkin.

---

## 🛠 Texnik Arxitektura

- **Dasturlash tili**: Kotlin 2.0
- **Foydalanuvchi interfeysi (UI)**: Jetpack Compose + Material 3
- **Audio & Media Engine**: AndroidX Media3 1.3.1 (ExoPlayer, MediaSession)
- **Audio DSP**: Android AudioEffects API (Equalizer, BassBoost, LoudnessEnhancer)
- **Asinxron ishlash**: Kotlin Coroutines & Flow
- **Rasm va vizualizatsiya**: Coil Compose + Custom Canvas

---

## 🚀 Ishga tushirish (Android Studio)

1. Android Studio dasturini oching.
2. `Open` tugmasini bosib, quyidagi manzilni tanlang:
   ```
   C:\Users\xolbo\.gemini\antigravity\scratch\carrozzeria-tube
   ```
3. Gradle sinxronizatsiyasi tugagach, telefoningizni USB orqali ulang yoki Emulyatorni ishga tushiring.
4. **Run 'app' (Shift + F10)** tugmasini bosing.
