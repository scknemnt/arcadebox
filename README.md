# Arcade Box
<img width="1448" height="1086" alt="Arcadebox_logo1" src="https://github.com/user-attachments/assets/aff5c3da-ac61-4b54-b625-9c6c7f5d72c5" />

Ev tipi ayakta kabin için **kiosk kabuk**. Windows veya Linux masaüstü görünmez: açılış → senin menün → oyun (RetroArch tam ekran) → menüye dönüş.

Bu depo **yazılımı** içerir. Ticari ROM, BIOS ve kutu görselleri **yok**. Kendi yasal dump’larını `roms/` ve `bios/` altına koyarsın.

**Hedef donanım:** Raspberry Pi 4 (8 GB) + HDMI (CRT/SCART sonra). Geliştirme: Windows.

---

## Ne yapar

- 4:3 CRT tarzı frontend (scanline, RGB mask, yıldız alanı)
- Klasör taraması: `roms/<sistem>/` içindeki her dosya menüde görünür
- Tek emülatör: **RetroArch** + libretro core
- Oyun çıkınca menü müziği ve liste geri gelir
- Servis menüsü: **F2** / logo (TEST, tuş ata, CRT)

Sistemler: Atari 2600, NES, SNES, Mega Drive, Arcade (FBNeo), Neo Geo, PlayStation.

---

## Bu repoda olmayanlar

| Klasör | Sen koyarsın |
|---|---|
| `roms/<sistem>/` | Yasal ROM / CHD / cue |
| `bios/psx/` | PS1 BIOS (`.bin`) |
| `roms/neogeo/neogeo.zip` | Neo Geo BIOS |
| `emulators/retroarch/` | Windows’ta portable RetroArch + `.dll` core |
| `music/` | İsteğe bağlı menü MP3 |

---

## Windows (geliştirme)

Python 3 (stdlib yeter). RetroArch portable:

```
emulators/retroarch/retroarch.exe
emulators/retroarch/cores/*.dll
```

| | |
|---|---|
| Pencere | `start.bat` |
| Tam ekran kiosk | `start-kiosk.bat` |
| Windows otostart | `kiosk/windows-otostart-kur.bat` bir kez |

Kabinde otomatik oturum aç (`netplwiz`). CRT için 800×600.

**Core’lar (Windows `.dll`):** Stella, Mesen (yedek Nestopia/FCEUmm), Snes9x, Genesis Plus GX, FBNeo, SwanStation (yedek Beetle PSX / PCSX ReARMed).

---

## Raspberry Pi 4 (kiosk)

- OS: **Raspberry Pi OS Lite 64-bit** (SD)
- Oyunlar: USB flash, klasör adı `ArcadeBox` (FAT32)
- Imager kullanıcı/hostname: `arcadebox`

USB’yi mavi USB3’e tak, SSH:

```sh
sudo mkdir -p /mnt/usb
sudo mount -t vfat /dev/sda1 /mnt/usb
cd /mnt/usb/ArcadeBox
tr -d '\r' < kiosk/pi-kur.sh > /tmp/pi-kur.sh
tr -d '\r' < kiosk/linux-start.sh > /tmp/linux-start.sh
sudo cp /tmp/linux-start.sh kiosk/linux-start.sh
sudo sh /tmp/pi-kur.sh
```

Windows satır sonları (`CRLF`) scripti bozar; `tr` ile LF yap. Script `ROOT=/` basarsa USB’den değil `/tmp` üzerinden çalışıyorsundur — normal. Autostart’ı README’deki Pi notlarına göre `~/.xinitrc` ile düzelt.

Core’lar (Linux `.so`, Windows DLL değil):

```sh
sudo apt-get install -y unzip wget
mkdir -p ~/.config/retroarch/cores
cd /tmp
for c in stella_libretro nestopia_libretro fceumm_libretro snes9x_libretro genesis_plus_gx_libretro fbneo_libretro pcsx_rearmed_libretro; do
  wget -O "$c.so.zip" "https://buildbot.libretro.com/nightly/linux/aarch64/latest/${c}.so.zip"
  unzip -o "$c.so.zip" -d ~/.config/retroarch/cores
done
```

veya `sh kiosk/pi-cores.sh`.

USB etiketi `ESD-USB` ise her açılışta `/mnt/arcade` bağlanır (`pi-kur.sh` fstab yazar). HDMI: güç soketine en yakın port.

---

## Klasörler

```
ArcadeBox/
  backend/arcadebox.py    yerel sunucu + RetroArch başlatıcı
  frontend/               kiosk UI
  data/                   sistem ve başlık eşlemesi (ROM yok)
  kiosk/                  Windows / Linux / Pi otostart
  roms/<sistem>/          senin dump’ların
  bios/                   senin BIOS’un
  config.json             port, tuşlar, CRT
```

Menü ROM dosya adından üretilir; arcade kısa adları `data/arcade-titles.json` ile çözülür.

Kapak indir (opsiyonel, libretro thumbnail CDN):

```
python backend/fetch_covers.py
```

---

## Kontroller

Çubuk / D-pad, **Gamepad0** tamam, **Gamepad1** geri, **Gamepad8** servis. Klavye: oklar, Enter, Esc, F2. PS3 pad USB HID olarak görünürse menüde çalışır; oyunda RetroArch bind.

---

## Lisans / yasal

Kod bu depoda. **ROM, BIOS ve ticari müzik dağıtılmaz.** Kendi kopyalarını kullan.
