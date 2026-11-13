## O'rnatish

1. Pastdagi **Snowfall-….dmg** faylini yuklab oling va oching.
2. **Snowfall**'ni **Applications** papkasiga sudrab tashlang.
3. Applications'dan Snowfall'ni oching. Menu bar'da ❄️ belgisi paydo bo'ladi.

**Birinchi ochishda macOS ilovani to'xtatsa** (ilova Apple Developer imzosisiz tarqatilgan):
**System Settings → Privacy & Security** sahifasining pastidagi **Open Anyway** tugmasini bosing.
Yoki Terminal'da bitta buyruq ishlating:

```
xattr -dr com.apple.quarantine /Applications/Snowfall.app
```

Talablar: macOS 13 Ventura yoki yangiroq, Apple Silicon yoki Intel.
