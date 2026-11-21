# Ф0.4 — ROM BIOS, софт для проверки, лицензии, эмуляторы

Опись на 2026-11-20. Всё скачанное лежит локально в `~/Downloads/karabas-sd-sprinter/` (вне git, ничего из архивов не запускалось). Пометка «по данным unreal-ng» = взято из документов эмулятора unreal-ng (`docs/inprogress/2026-09-28-sprinter/*.md` в [alfishe/unreal-ng](https://github.com/alfishe/unreal-ng)), нами не проверено.

## 1. BIOS (ROM 256 КБ)

**Новее (2026-11-21, [unreal-ng `data/rom/sprinter`](https://github.com/alfishe/unreal-ng/tree/master/data/rom/sprinter), локально `roms/unreal-ng-2026-11-21/`):** `sp2k-3.06-hf2.rom` — «Firmware v3.06 Hotfix 2», релиз 19.01.2026, CRC `9aa7bb29`; поток ACEX (`0x30100`, 59 215 байт) **байт в байт как у 3.06** (k30, `5aa954b6`) — ядро берёт его как есть, на плате (26112106) POST и DSS 1.70 → Flex Navigator 1.15. **Это BIOS ядра** (самый стабильный, по словам команды). `sp2k-3.07-beta1.rom` — «Firmware v3.07 BETA 1», CRC `a06a1a02`: поток ACEX **другой** (отличие с `0x3014d`, в первых 512 байтах — хеш не из таблицы, ядро запустит 3.03a); нужен исходник конфигурации, не поддерживается. `sp2k-3.04.rom` там = MAME `1729cb5c`.

**Решение 2026-11-21: поддерживается только BIOS 3.06** (в `.kg`, CMOS `roms/cmos_306_mame.bin`). Остальные версии не поддерживаются и в сборку не входят; на плате (26112106) 2.13, 2.17, 3.00, 3.03, 3.04 грузят DSS 1.62 до Flex Navigator, 3.05 («BIOS v2.54», 2022, оба образа) уходит в циклический перезапуск — его не чиним. Конфигурация 3.03a в RTL остаётся (основа перевода, k30 — переключатели поверх неё, SCROLL), таблица хешей тоже.

### 1.1 Итог по версиям MAME

| Версия | Дата | Откуда исходный образ | Совпадение с MAME (CRC32 + SHA1) | Локально |
|---|---|---|---|---|
| 2.13 | 23.01.2002 | мастер-архив Ивана Мака: [winglion.sprinter.ru/sp2000/sprinter.zip](https://winglion.sprinter.ru/sp2000/sprinter.zip) → вложенный `sprinter/Sprinter.zip` → `_bin/0013/_SPRIN.BIN` (CRC `a6171af3`) | **после правки** номера платы (= 213) | `roms/mame-named/sp2k-2.13.rom`; исходник `roms/winglion-sprinter-zip-bins/_bin_0013__SPRIN.BIN` |
| 2.17 | 03.03.2002 | [winglion.sprinter.ru/sp2000/BIOS_ROMS.ZIP](https://winglion.sprinter.ru/sp2000/BIOS_ROMS.ZIP) → `_SP_217.ZIP/_SPRIN.BIN` (CRC `d644b1d2`; тот же файл в `sprinter.zip`, `_bin/0017`) | **после правки** (= 217) | `roms/mame-named/sp2k-2.17.rom`; исходник `roms/winglion-bios-roms/x/_SP_217/_SPRIN.BIN` |
| 3.00 | 07.04.2002 | `BIOS_ROMS.ZIP` → `_SP_300` (CRC `0d0aa5d4`) = [zxgit.org/Sprinter/2000](https://zxgit.org/Sprinter/2000) `2000/fw/bios/sp2k-3.00.253.bin` | **после правки** (= 300) | `roms/mame-named/sp2k-3.00.rom`; исходники `roms/winglion-bios-roms/x/_SP_300/`, `roms/zxgit-sprinter-2000/` |
| 3.03 | 13.05.2003 | `BIOS_ROMS.ZIP` → `_SP_303` (CRC `88e3e23b`) = zxgit `sp2k-3.03.253.bin` | **после правки** (= 303) | `roms/mame-named/sp2k-3.03.rom` |
| 3.04 | 17.06.2003 | zxgit `Sprinter/2000` `2000/fw/bios/sp2k-3.04.253.bin` (то же в `2003s/`, `2016s/`); [app.sprinter.ru/os/sprinter-firmware](https://app.sprinter.ru/os/sprinter-firmware) `sp2k_1k30_3.04.253.zip` → `sp2k-1k30-3.04.253.bin` | **да, как скачано** | `roms/zxgit-sprinter-2000/2000_fw_bios_sp2k-3.04.253.bin`, `roms/app-sprinter-firmware-304/x/sp2k-1k30-3.04.253.bin`, копия `roms/mame-named/sp2k-3.04.rom` |
| 3.05 | 01.09.2022 | от пользователя (Telegram, 2026-11-21) `EP1K30-305#000.ROM`, CRC `2d46deaf` — **другая сборка**, не MAME `fe1c2685` (не номер платы: перебор 0..999 не совпал); номер платы 0; строка `Hardware v3.05` | — | `roms/telegram-2026-11-21/sp2k-3.05-ep1k30.rom` |
| 3.06 | 25.06.2025 | от пользователя (Telegram, 2026-11-21) `EP1K30-306#000.ROM` = **MAME `187f4382` байт в байт** (BIOS 3.06, SETUP 1.60, нужен DSS ≥ 1.70); также `EP1K50-306#000.ROM` — та же BIOS с конфигурацией для EP1K50 | да | `roms/telegram-2026-11-21/sp2k-3.06-ep1k30.rom` (+ копия `roms/mame-named/sp2k-3.06.rom`), `sp2k-3.06-ep1k50.rom` |

Все пять полученных `roms/mame-named/*.rom` проверены по CRC32 и SHA1 из `sprinter.cpp` (`python3 -I`, zlib / hashlib).

Другие варианты 3.04: `BIOS_ROMS.ZIP/_SP_304` = ZXMAK2 `ROMS.PAK/SPRINTER/SP_304.BIN` = `src/bin/_SPRIN.BIN` в истории Tolik-Trek/Sprinter-BIOS — CRC `a3970620` (номер платы `0x24`); правкой номера на 7 даёт ровно MAME `1729cb5c`.

### 1.2 Почему образы MAME отличаются от архивных: номер платы

Образ BIOS персональный: в нём номер платы и контрольная сумма.

- Номер платы — 16 бит little-endian по смещению `0x20005` (страница 8, байты `+5..+6`). В архивных образах там 0, 1, `0x12`, `0x1A`, `0x24`.
- Контрольная сумма — 4 байта по `0x0004..0x0007`, считается по всему образу, где эти 4 байта = `FF`. Алгоритм `make_num` (исходник `MAKE_NUM.COM` / `make_num.c`: `sprinter.zip/LAST/BIOS/`, [Tolik-Trek/Scroll_CNF bin/make_num.c](https://github.com/Tolik-Trek/Scroll_CNF/blob/master/bin/make_num.c)).
- В MAME номер платы = номер версии (213, 217, 300, 303); у 3.04 он равен 7 (тот же образ, что в zxgit). Других отличий нет.
- Зачем номер: SETUP показывает его при старте (функция BIOS `#ED`), а установщик Thunder in the Deep выдаёт код регистрации, привязанный к плате. Ядру нужен любой номер (OSD-параметр или константа), но тогда меняется и контрольная сумма.

Пересчёт (так получены файлы `mame-named/`):

```python
import sys, zlib
def make_num(d):                      # = make_num.c
    b = [0, 0, 0, 0]
    for x in d:
        b[0] += x
        if b[0] >= 256:
            b[0] &= 255; b[1] += x
            if b[1] >= 256:
                b[1] &= 255; b[2] += x
                if b[2] >= 256:
                    b[2] &= 255; b[3] = (b[3] + x) & 255
    return bytes(b)
src, board, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
d = bytearray(open(src, 'rb').read())
d[0x20005:0x20007] = board.to_bytes(2, 'little')
d[4:8] = b'\xff' * 4
d[4:8] = make_num(d)
open(out, 'wb').write(d)
print('%08x' % (zlib.crc32(d) & 0xffffffff))
```

### 1.3 Раскладка ROM

16 страниц по 16 КБ.

| Страница | 2.1x–3.04 (Peters Plus) | 3.06 / 3.07 (Tolik-Trek, `bios/mem_map.txt`, `BUILD.a80`) |
|---|---|---|
| 0 (`0x00000`) | ROM: дисковые драйверы, упакованный SETUP (`BIOS300ex2.c`: «setup» `0..3FFF`) | ROM: дисковая подсистема и SETUP |
| 1 | пусто (`FF`) | логотип 128×72, 256 цветов |
| 2–4 | пусто | ПЗУ ZX: 128, 48, TR-DOS |
| 5–7, 9–11 | пусто | ROM-диск RECOVERY (96 КБ FAT12: DSS, FORMAT, FDISK) |
| 8 (`0x20000`) | BIOS («EXP»), строка `Sprinter BIOS: ver 3.04`; `+5..6` — номер платы | BIOS («EXP»), `Firmware v…` |
| `0x0C`–`0x0F` (`0x30000`) | загрузчик ПЛИС (`0x100` байт) + битстрим ACEX 59 215 байт с `0x30100` | универсальный загрузчик 1K30 / 1K50 + битстрим |

Проверено побайтно: `0x30100..+59214` в 2.17 / 3.00 / 3.03 / 3.04 = `upstream/sprinter-bios/ALTERA/SP2K_217 / 300 / 303 / 304.BIN`; 2.15 = `SP2K_215.BIN`. В 2.13 там свой битстрим (CRC `26f42985`): его нет в gitlab-наборе, но AHDL 2.13 есть в SP2000-ACEX (§1.5). Хвост после битстрима не пустой (не `FF`), не разбирали.

### 1.4 Кто делает 3.05 / 3.06, где исходники

- Автор — **Анатолий Белянский (Tolik-Trek)**, Sprinter Team. Исходники: [zxgit.org/Tolik-Trek/Sprinter-BIOS](https://zxgit.org/Tolik-Trek/Sprinter-BIOS) (sjasmplus + Lua; подмодуль [Shared_Includes](https://zxgit.org/Tolik-Trek/Shared_Includes)). `master` — «v3.06 Hotfix 2» (19.01.2026), `beta` — 3.07 beta (24.09.2026). История начинается 12.06.2023; 3.05 (2022) старше её, её исходника в публичной истории нет.
- Исходники 3.x — **переработанная реконструкция**, не оригинал. Первый коммит, `src/bios/exp/EXP.asm`, озаглавлен «EXPANSION VER 3.00», но уже с новым API. Происхождение неизвестно (по данным unreal-ng). Peters Plus выложила только исходники страницы 0 до 2.17 / Setup 253 (`upstream/sprinter-bios`); README gitlab: «we are working on recreation of sources for 3.00, 3.03, 3.04». Исходники EXP (страница 8) уровня 2.17 есть в мастер-архиве: `sprinter.zip/LAST/BIOS/EXP*.ASZ`, `_BIOS.REV` 2.17.
- Бинарников 3.05 / 3.06 не нашли нигде: ни релизов на zxgit / GitHub, ни app.sprinter.ru (там только 3.04), ни nedopc, ни поиска по имени `sp2k-3.06`. Ветки Sprinter-BIOS хранят только старый `src/bin/_SPRIN.BIN` = 3.04 `a3970620` (`roms/zxgit-tolik-sprinter-bios/`, 7 одинаковых копий с разных коммитов). По данным unreal-ng, сборка `92f5db8` (25.06.2025) даёт `bd9f27fe`, а не MAME `187f4382`, и «MAME-сборка» автора `mame_release_v306_25.05.2025` (с `sp_hdd_sys.chd`) не публичная.
- Гипотеза (не проверяли): MAME-образы 3.05 / 3.06 — авторские сборки с номером платы 305 / 306, как у 2.13–3.03. Проверить можно сборкой из исходников (sjasmplus 1.21.1, сценарий unreal-ng `tools/machines/sprinter/bios-build/make-bios.py`) и перебором номера. Мы **не собирали**: Lua в исходниках — это исполнение скачанного кода, нужно решение пользователя. Другие пути: спросить у автора / в Telegram [Sprinter Team](https://t.me/zx_sprinter), взять из ROM-набора MAME у пользователя.
- doc.sprinter.ru (документация), get.sprinter.ru, dss.sprinter.ru: в Ф0 отсюда обрывался TLS, 2026-11-21 открываются (сертификат в порядке, ошибка была на нашей стороне); app.sprinter.ru и winglion.sprinter.ru открываются.

### 1.5 Находки, расходящиеся с PLAN.md (для Ф0.3)

- **[github.com/Tolik-Trek/SP2000-ACEX](https://github.com/Tolik-Trek/SP2000-ACEX)** (коммиты 18.11.2026, лицензия не указана): восстановленный AHDL конфигураций ACEX **2.10, 2.11, 2.11m, 2.12, 2.13, 2.17, 2.18, 3.00, 3.03, 3.03a**. По коммиту на версию, в описании отличия и «исходный ACX». Файлы: `BASE_303.TDF`, `DCP`, `VIDEO2`, `ACCELER`, `AY`, `KBD`, `MOUSE` + `.MIF`. PLAN.md говорит «исходников конфигураций 3.00–3.04 нет» — теперь есть 3.00 и 3.03 (3.04 нет).
- **[github.com/Tolik-Trek/Scroll_CNF](https://github.com/Tolik-Trek/Scroll_CNF)**: AHDL-проект `SCROLL` (`src/SCROLL.TDF`, модули), список цепей `net_list/scroll.tdf`, оригинальный битстрим `original bitstream/SCROLL.ACX` (59 215 байт), сборка 1342 LC / 45 МГц. Вероятно, это «Game Configuration» с плавным скроллом из Thunder in the Deep. Не подтверждено: хеш MAME `0x3861cfa4` считается по записям загрузчика, а не по файлу.
- **[zxgit.org/Tolik-Trek/TITD](https://zxgit.org/Tolik-Trek/TITD)**: дизассемблер загрузчика игры и `reversing/GAME_00.ACX`, `K30.ACX`, `K30L.ACX`.
- **[zxgit.org/Sergey/Sprinter-Core-HDL](https://zxgit.org/Sergey/Sprinter-Core-HDL)** (MIT): заявленный перевод AHDL → Verilog / SystemVerilog. Пока только README.
- В истории Sprinter-BIOS (`master` до 2026-05) были `src/altera/quartus/acex/SP2_ACEX.qsf` и `src/altera/acex/k30/*.TDF` (по данным unreal-ng, не менялись с 2024-08 до 2026-09). Это AHDL «Core 1K30 v3.05», т. е. конфигурация BIOS 3.05 / 3.06.
- [GitHub Tolik-Trek/GoDCP](https://github.com/Tolik-Trek/GoDCP) (MIT): редактор карты портов DCP.

## 2. Софт для проверки

Источник — каталог сообщества [app.sprinter.ru](https://app.sprinter.ru/) (Sprinter Team; прямые ссылки `https://app.sprinter.ru/downloads/<раздел>/<имя>/<id>`, без входа) и мастер-архив Ивана Мака [winglion.sprinter.ru](https://winglion.sprinter.ru/). Каждый архив — в своём подкаталоге; `x/` — распакованное (только данные).

### 2.1 ОС и образы дисков

| Что | URL | Локально |
|---|---|---|
| **Образ HDD с DSS 1.62.93 и почти всем каталогом app.sprinter.ru** (из комплекта ZXMAK2 2.9.3.8, 07.10.2021): `sp_disk1.vhd`, fixed VHD 2 ГиБ (сырой MBR-диск + 512 Б футер), FAT16 с LBA 62. Внутри `FN BIN DEMOS (DOOM, MORTAL, SPRIN-ZX, BALLS, ROTOZOOM…) DEV GAMES (TITD с инсталлятором и демо, KLAD, sokoban, tetris) MEDIA MODEM TESTS (UMT 2.3, timer, .trd) TRD UTILS ZX (ПЗУ Spectrum/Scorpion/Pentagon, SPECTRUM.EXE, ZXMODE.EXE)`; `SYSTEM.BAT` запускает `fn` | [app.sprinter.ru/os/zxmak2](https://app.sprinter.ru/os/zxmak2) → `SprinterEmu.rar` (34.6 МБ) | `emulators/app-zxmak2/SprinterEmu.rar`; `x/SprinterEmu/HDD/sp_disk1.vhd` (разрежен, на диске 54 МБ), `x/SprinterEmu/DSS/dss_1_62_92.img`, `ROMS.PAK`, `ZXMAK2.vmz`, `machines.config` |
| DSS 1.62.92 — загрузочная дискета 1.44 МБ (FAT12; `SYSTEM.DOS/EXE`, `BIN DEMOS DOCS FM FN GAMES PICS ZX KEYBOARD`) | [app.sprinter.ru/os/estex-dss162](https://app.sprinter.ru/os/estex-dss162) `dss_1_62_92.zip` | `os/app-dss162-a/x/dss_1_62_92.img` (= образ из ZXMAK2) |
| DSS 1.62.93 — патч (`system.dos`, `SYSTEM.EXE`) | там же, `dss_1_62_93.zip` | `os/app-dss162-b/` |
| DSS 1.60 R (Peters Plus, 2003) — дискета 1.44 МБ с установщиком, `CMD DEMO FN SOFTWARE ZX` | [app.sprinter.ru/os/estex-dss160](https://app.sprinter.ru/os/estex-dss160) | `os/app-dss160/x/dss_1_60.img` |
| DSS 1.61 patch 2 (Vasil Ivanov) | [app.sprinter.ru/os/estex-dss161](https://app.sprinter.ru/os/estex-dss161) | `os/app-dss161/` |
| DSS 1.60 R, файлы выпуска | `upstream/sprinter-dos/release` | в репозитории |

Чего нет: «MAME-сборки» автора BIOS с `sp_hdd_sys.chd` (DSS 1.71.57) и `sp_hdd_media.chd` (по данным unreal-ng, существует, не публичная). По данным unreal-ng, DSS 1.71 на BIOS 3.04 падает («Fatal error») и требует 3.06+. Публичный DSS 1.71 — только в исходниках [zxgit.org/Tolik-Trek/Estex-DSS](https://zxgit.org/Tolik-Trek/Estex-DSS) и внутри ROM-диска RECOVERY в 3.06+.

### 2.2 Игры, демо, утилиты

| Что | Автор, год | URL | Локально |
|---|---|---|---|
| **Thunder in the Deep 1.10** — своя конфигурация ПЛИС (скролл); уже установленная (`TITD.EXE`, `TITD.PAK`, `titd0/1.exe`) | Deviants / Peters Plus, 2003 | [app.sprinter.ru/games/thunder-in-the-deep](https://app.sprinter.ru/games/thunder-in-the-deep) | `games/app-titd/x/` |
| TITD: демо 1 (11.2002), демо 2 (01.2003, один уровень), полный дистрибутив с инсталлятором (нужен код регистрации, привязанный к номеру платы) | там же | [nedopc TITD](http://www.nedopc.org/nedopc/Sprinter/TITD): `titd06-demo.zip`, `titdd2.zip`, `titd.zip` | `games/nedopc-titd/` |
| Tetris 1.5.2 (`.EXE` + `TETRIS.TRD`) | Shaos, 2002 | [/games/tetris](https://app.sprinter.ru/games/tetris) | `games/app-tetris/` |
| Sokoban (Forth), КЛАД 0.26 | Sprinter Team; CHRV | [/games/sokoban](https://app.sprinter.ru/games/sokoban), [/games/klad](https://app.sprinter.ru/games/klad) | `games/app-sokoban/`, `games/app-klad/` |
| Mortal Kombat demo (CBL-звук `MISS2.CBL`, `MORTAL.TRD`, нужен режим ZX) | Peters Plus, 1999 | [/demos/mortal](https://app.sprinter.ru/demos/mortal) | `demos/app-mortal/` |
| Balls, RotoZoom (ускоритель, спрайты) | Sayman, 2021 | [/demos/balls](https://app.sprinter.ru/demos/balls), [/demos/rotozoom](https://app.sprinter.ru/demos/rotozoom) | `demos/app-balls/`, `demos/app-rotozoom/` |
| Fractals; Real 3D; Demo Examples (plasma, flames, 256color, starway…) | Shaos; Sprinter Team | [/demos/fractals](https://app.sprinter.ru/demos/fractals), [/demos/real-3d](https://app.sprinter.ru/demos/real-3d), [/demos/demo-examples](https://app.sprinter.ru/demos/demo-examples) | `demos/app-fractals/`, `demos/app-real3d/`, `demos/app-examples/` |
| Flex Navigator 1.00 / 1.10 / 1.13 | Anton Enin | [/utils/flex-navigator](https://app.sprinter.ru/utils/flex-navigator) | `utils/app-fn-a,b,c/` |
| WAV player, GFX viewer, PT3 player, TRD tools | Ivan Mak; Anton Enin; Sayman; Sprinter Team | `/utils/wav-player`, `/utils/gfx-viewer`, `/utils/pt3player`, `/utils/trd-tools` | `utils/app-wavplay/`, `app-gfxview/`, `app-pt3play/`, `app-trdtools/` |
| fdisk, format, boot, FFORMAT (FDD) | Hard/WCG, Sayman; Peters Plus; Vasil Ivanov | `/system/fdisk`, `/system/format`, `/system/boot`, `/utils/floppy-formatter` | `utils/app-fdisk/`, `app-format/`, `app-boot/`, `app-fformat/` |

Не скачано, но есть: DOOM (28.8 МБ, [/demos/doom2](https://app.sprinter.ru/demos/doom2); уже есть на `sp_disk1.vhd` в `DEMOS/DOOM`); средства разработки (`/development/*`: Solid C, MASM80, TASM, OrgAsm, DemoN, Forth); мастер-архивы `MY_SPRINTER_HDD_COPY.ZIP` (57 МБ, HDD Ивана Мака 2001 г.), `2_DEMO.ZIP` (22 МБ), `public.zip` (213 МБ, архив А. Горячева); демо 2025 «don't blink» ([zxart](https://zxart.ee/eng/software/demoscene/demo/dont-blink/), требует новый BIOS / DSS).

### 2.3 Документы (скачаны)

- `docs/winglion/`: `sp2000.pdf` (руководство по программированию Sp2000, Иван Мак), `Sprinter.pdf` (схема Sp2000s), `Z84C15.pdf`, `montaj.htm` (заметки о проблемах схемы).
- `docs/winglion-sprinter-zip/sprinter.zip` (20 МБ): сборник исходников Peters Plus. Внутри: `LAST/BIOS/*.ASZ` (исходники BIOS EXP 2.17), `LAST/ALTERA/VIDEO.SCF`, `SP2000/SP2000_T.BIN` (битстрим), вложенный `Sprinter.zip` с 21 образом BIOS 2.02–2.17 (распакованы в `roms/winglion-sprinter-zip-bins/`) и старыми ПЗУ Sp97 128 КБ.

### 2.4 Форматы образов

- **MAME** (`sprinter.cpp`, `beta_m.cpp`): дисковод через Beta Disk (ВГ93). Форматы `add_pc_formats()` (сырые PC `.img` / `.ima` 720K / 1.44M), `TRD`, `SCL`, MFM-контейнеры (`.mfi`, `.hfe` и т. п.); приводы 3.5" DD/HD, 5.25" HD/QD. IDE: два канала, ATA-диск (в MAME — `.chd`), ATAPI CD-ROM на `ata0:1`. Software list у драйвера нет.
- **ZXMAK2**: HDD `.vhd` (fixed), FDD `.img` 1.44M, `.trd`.
- **Сообщество**: DSS-дискеты — сырые `.img` 1.44 МБ FAT12; HDD — MBR + FAT16 (тип `06`), загрузчик DSS в LBA 1–3 («Starting...»). На реальном Sprinter сейчас обычно CF-карта на IDE. ZX-софт — `.trd` внутри FAT, запуск через DSS / FN.
- Для ядра: `sp_disk1.vhd` = сырой образ (VHD-футер в последних 512 байтах), годится для `hdf_ata` как есть или после отрезания футера.

## 3. Лицензии (как заявляют публикующие)

| Что | Заявление |
|---|---|
| Всё о Sprinter (ПО, схемы, BIOS) | winglion.sprinter.ru, Иван Мак: «01.02.2007 ф. "Петерс Плюс" снимает все ограничения на распространение информации по компьютеру Sprinter»; «Вся информация о компьютере Sprinter… передается общественности совершенно свободно и безвозмездно» |
| BIOS 2.17 (исходники), DSS 1.60 (исходники и выпуск), apps | README gitlab sprinter-computer: «we believe it was done under PUBLIC DOMAIN terms»; apps: «most software included here are PUBLIC DOMAIN (if not specified differently)» |
| BIOS 3.00–3.04 (образы) | zxgit Sprinter/2000 и app.sprinter.ru: лицензия не указана. 3.03 / 3.04 «официально не выпускались» (readme zxgit) |
| BIOS 3.05+ (Tolik-Trek Sprinter-BIOS, Shared_Includes, Estex-DSS) | файла лицензии нет; unreal-ng считает их MIT «по правилу проекта» — это их допущение |
| SP2000-ACEX, Scroll_CNF | лицензия не указана |
| GoDCP, Sergey/Sprinter-Core-HDL | MIT |
| Thunder in the Deep | «Copyright (C) 2003 Deviants, all rights reserved. Published by PETERS PLUS LTD… NOT free software. The basic fee for a single registration is $12». Распространяется сообществом (nedopc, app.sprinter.ru) |
| Софт app.sprinter.ru | на страницах лицензий нет (только авторы); MASM80: «(c) 1980,81 Microsoft Corp. All rights reserved» |
| nedopc wiki | CC BY-SA 4.0 (тексты сайта) |
| MAME `sprinter.cpp` | BSD-3-Clause |

Вопрос пользователю (не решали): класть ли образ BIOS в выпускаемый `.kg` публичного репозитория (как ПЗУ в других ядрах) или грузить с SD. TITD — только с SD пользователя.

## 4. Другие эмуляторы (второй эталон)

| Эмулятор | Что умеет | Исходники |
|---|---|---|
| **MAME** `sprinter` (Andrei Holub, с 0.255, 2023) | самый полный: DCP, ускоритель, видео, CBL, IDE, CD, загрузка конфигурации по хешу (TITD `0x3861cfa4`) | BSD-3, `upstream/mame/` |
| **sp_mame** (Tolik-Trek, форк MAME; также [zxgit Tolik-Trek/MAME](https://zxgit.org/Tolik-Trek/MAME)) | правки Sprinter: «tmkonf», задержки DMA, общие HDD (2026) | [github.com/Tolik-Trek/sp_mame](https://github.com/Tolik-Trek/sp_mame), лицензия MAME |
| **unreal-ng** (alfishe, 2026) | модель Sprinter; BIOS 3.04 / 3.06 HF2 / 3.07 beta грузятся до DSS; подробная документация (порты, BIOS, HDD, сборка BIOS) | [github.com/alfishe/unreal-ng](https://github.com/alfishe/unreal-ng), GPL-3.0 |
| **ZXMAK2** (Alex Makeev), машина Sprinter «Alpha» | IDE, FDD, CMOS, клавиатура / мышь через SIO, ускоритель | [github.com/zxmak/ZXMAK2](https://github.com/zxmak/ZXMAK2) (`src/ZXMAK2.Hardware/Sprinter/`), GPL-3.0; сборка с HDD — app.sprinter.ru |
| **SprintEm** (Shaos, с 2002, бывш. SPRINT / Zpring) | HLE: запускает `.EXE`, эмулируя вызовы BIOS / DSS, без железа | [gitlab.com/nedopc/sprintem](https://gitlab.com/nedopc/sprintem), GPL-2.0; примеры `.EXE` в `disk/` |
| Sprinter200x (SaymanNsk) | не эмулятор: AHDL `Altera_1K30` + ПО | [github.com/SaymanNsk/Sprinter200x](https://github.com/SaymanNsk/Sprinter200x), GPL-3.0 |

## 5. Что не найдено

- Образы BIOS **3.05** (`fe1c2685`) и **3.06** (`187f4382`). Варианты в §1.4.
- Готовый образ HDD с DSS 1.71 (MAME `.chd` автора).
- Исходник страницы 8 BIOS 3.00–3.04 в оригинале (есть 2.17-уровень в мастер-архиве и реконструкция Tolik-Trek).
- doc.sprinter.ru не открылся (нет TLS-соединения).

Объём локально: 134 МБ (из них `SprinterEmu.rar` 35 МБ и разрежённый `sp_disk1.vhd`: 2 ГиБ по размеру, 54 МБ на диске). Больше, чем «десятки МБ», из-за образа HDD; при нехватке места его можно удалить, архив `.rar` остаётся.

### Образы 3.05 / 3.06 и системный диск DSS 1.7x (от пользователя, 2026-11-21)

- Хеш конфигурации ACEX по алгоритму MAME (сумма по первым 4096 **записям** потока, по биту в записи — см. `docs/configs.md`, скрипт `acxhash.py`): 3.05 и 3.06 EP1K30 — **`5aa954b6`** (k30), 3.06 EP1K50 — `e9dcc183` (другой кристалл; не нужна). Числа `383a0f9f` / `8cd33f23`, записанные здесь раньше, — ошибка (сумма сырых байтов ROM с `0x30100`, не хеш MAME).
- Архивы `~/Downloads/Telegram Desktop/`: `SPRINTER.7z` / `SPRINTER_archive.zip` — одно дерево системного диска (DOCS, DEV, DEMOS, UTILS, GAMES, MEDIA, ZX, TRD, DSS, TESTS, FN, BIN, MODEM, C, TITD); `SPRINTER_v2.7z` — новее: `SYSTEM.DOS` 25.06.2025 (DSS 1.7x, под BIOS 3.06), без TITD. Из `SPRINTER_v2` собирать образ HDD FAT16 для проверки 3.06.

### Авторский MAME 3.06 (`mame_release_v306_25.05.2025.rar`, от пользователя 2026-11-21)

Распаковано нужное в `~/Downloads/karabas-sd-sprinter/mame306/` (сам `mame.exe` — Windows, не нужен):
- `roms/sprinter.zip` — **полный набор BIOS MAME**, все 7 CRC совпадают с `sprinter.cpp`, в том числе **3.05 `fe1c2685`** (→ `roms/mame-named/sp2k-3.05.rom`); 3.05 из Telegram `2d46deaf` — другая сборка.
- `roms/sprinter/_SPRIN.BIN` — ещё одна сборка 3.06 (`df18c931`, SETUP 1.60; хеш конфигурации — пересчитать `acxhash.py`).
- `IMG/sp_hdd_sys.chd` (96 МБ) — системный HDD автора под 3.06 (нужен `chdman extracthd` → сырой образ для SD); `IMG/dss171u.img` — загрузочная дискета DSS 1.71; `nvram/sprinter_6/rtc` — CMOS (128 байт) автора под 3.06; `_306.bat` — запуск: дисковод 0 5.25" QD, 1 — 3.5" HD (дискета DSS во 2-м), HDD1 sys, HDD2 media, CD на втором канале, NeoGS на ISA.
- Официальный релиз 3.06 (`spdx_release_v306_25.05.2025`): `hdd/system.zip` (DSS 3.06, 666 файлов, без `BOOT.EXE`), `firmware/` (ROM EP1K30/50, `.pof` MAX EPM7064 / EPM7128, `UP306.EXE`), `docs/sp-dx-sch.pdf`; hotfix1 — `UP306F1.EXE` (BIOS внутри).

