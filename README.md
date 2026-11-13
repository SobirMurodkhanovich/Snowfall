# ❄️ Snowfall

Mac ekraningizda qor yog'adi. Tushgan qor **Dock ustiga** va ekranning pastiga yig'iladi,
qor to'xtagach esa asta-sekin **erib ketadi**. Qor ishingizga xalaqit bermaydi: sichqoncha
bosishlari qor orqali pastdagi oynalarga o'tadi.

## O'rnatish

1. [Releases](../../releases/latest) sahifasidan `Snowfall-x.y.z.dmg` faylini yuklab oling.
2. DMG'ni oching va **Snowfall**'ni **Applications** papkasiga sudrab tashlang.
3. Applications'dan Snowfall'ni oching. Menu bar'da ❄️ belgisi paydo bo'ladi.

### Birinchi ochishda macOS ilovani to'xtatsa

Ilova Apple Developer imzosisiz tarqatiladi, shuning uchun macOS uni birinchi marta to'xtatadi.
Ruxsatni bir marta berish kifoya:

- **System Settings → Privacy & Security** sahifasining pastidagi **Open Anyway** tugmasini bosing, yoki
- Terminal'da quyidagi buyruqni ishlating:

  ```
  xattr -dr com.apple.quarantine /Applications/Snowfall.app
  ```

## Ishlatish

Menu bar'dagi ❄️ belgisini bosing:

| Menyu | Nima qiladi |
| --- | --- |
| Qorni to'xtatish / Qor yog'dirish | Qorni yoqadi yoki o'chiradi. O'chirilganda yig'ilgan qor asta eriydi |
| Qor kuchi: Kam / O'rtacha / Ko'p | Qor qanchalik qalin yog'ishini belgilaydi |
| Shamol: Shamolsiz / Yengil / Kuchli | Qor parchalarini yon tomonga uchiradi |
| Oynalar ustida yog'sin | Yoqilgan: qor hamma oynalar ustida yog'adi. O'chirilgan: faqat ish stoli fonida |
| Yig'ilgan qorni tozalash | Uyumni darhol olib tashlaydi |
| Dock'ni aniq o'lchash… | Dock kengligini aniq o'lchash uchun ruxsat so'raydi (pastda batafsil) |
| Mac yonganda ishga tushsin | Kompyuter yonganda Snowfall avtomatik ochiladi |

### Dock haqida

macOS boshqa ilovalarga Dock'ning kengligini bermaydi, shuning uchun Snowfall uni Dock
sozlamalaridan taxminan hisoblaydi. Qor Dock chetidan sal chiqib yoki yetmay turgan bo'lsa,
menyudagi **Dock'ni aniq o'lchash…** bandini bosing va **System Settings → Privacy & Security →
Accessibility** bo'limida Snowfall'ga ruxsat bering. Ilova imzosiz bo'lgani uchun har yangi
versiyadan keyin bu ruxsatni qayta berish kerak bo'lishi mumkin.

Dock yashirin turgan (auto-hide) yoki ekranning yon tomonida bo'lsa, qor ekranning eng pastiga yig'iladi.

## Yangi versiya chiqarish

DMG'ni GitHub Actions yasaydi ([`.github/workflows/build-dmg.yml`](.github/workflows/build-dmg.yml)).
Yangi versiya chiqarish uchun tag qo'yib push qiling:

```
git tag v1.0.1
git push origin v1.0.1
```

Bir necha daqiqadan keyin **Releases** sahifasida `Snowfall-1.0.1.dmg` paydo bo'ladi.
`main`'ga qilingan har bir push ham DMG yasaydi. U Actions sahifasidagi o'sha ishning
**Artifacts** bo'limida turadi.

## O'zingiz yig'ish

Xcode yoki Command Line Tools kerak (`xcode-select --install`).

```
scripts/build-app.sh 1.0.0             # dist/Snowfall.app (Apple Silicon + Intel)
scripts/make-dmg.sh dist/Snowfall.dmg  # dist/Snowfall.dmg
open dist/Snowfall.app
```

Ikonkani qayta chizish: `scripts/make-icon.sh`.

## Ichki tuzilma

| Fayl | Vazifasi |
| --- | --- |
| `Sources/Snowfall/AppDelegate.swift` | Menu bar menyusi, sozlamalar, har bir ekranga oyna ochish |
| `Sources/Snowfall/SnowWindow.swift` | Shaffof oyna: sichqonchani o'tkazib yuboradi, hamma Space'larda turadi |
| `Sources/Snowfall/SnowSimulation.swift` | Qor parchalarining harakati: tushish, chayqalish, shamol |
| `Sources/Snowfall/SnowPile.swift` | Yig'ilgan qor: ekran 2 pt'lik ustunlarga bo'linadi, qiya joydan qor sirpanadi, asta eriydi |
| `Sources/Snowfall/SnowRenderer.swift` | Metal orqali chizish (CPU'ni kam sarflaydi) |
| `Sources/Snowfall/DockLocator.swift` | Dock qayerdaligini aniqlaydi |

Talablar: macOS 13 Ventura yoki yangiroq.
