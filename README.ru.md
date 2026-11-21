# Ядро Sprinter Sp2000 для Karabas Go / Mini / Mini G

[English version](README.md)

PetersPlus Sprinter Sp2000 (Z84C15 на 21 МГц, Altera ACEX + MAX, 4 МБ ОЗУ, 256 КБ видео-ОЗУ, Estex DSS) для плат семейства Karabas Go (Xilinx Spartan-6 XC6SLX25). AHDL ПЛИС Спринтера (ACEX, MAX) переведён в Verilog и сверен в симуляции с сетевыми списками исходников оригинала (`docs/translation.md`, `docs/versions.md`).

| Плата | Файл ядра | Видео | Звук |
|---|---|---|---|
| Karabas Go | `sprinter.kg` | VGA | ЦАП I2S |
| Karabas Mini | `sprinter.kg` | HDMI | HDMI, аналоговый выход (сигма-дельта) |
| Karabas Mini G | `sprinter.kg` | HDMI | HDMI, ЦАП I2S (PCM5102) |

Файл ядра лежит в `src/`. BIOS внутри: **Sprinter BIOS 3.06 Hotfix 2**, единственная поддерживаемая версия.

Состояние: сборка 26112201. Проверено на плате Mini G: BIOS 3.06 HF2 и SETUP, часы CMOS, DSS 1.70 и Flex Navigator 1.15 с образа жёсткого диска, DSS с образа дискеты, клавиатура и мышь, Thunder in the Deep (своя конфигурация ACEX, скроллинг и звук). Сборки для Go и Mini на платах не запускались.

## Возможности

- **Конфигурации ACEX** («личности», выбор по хешу потока конфигурации, который заливает программа, как в MAME): 3.03a (основа), **k30** (BIOS 3.05 / 3.06) и **SCROLL** (Thunder in the Deep, `GAME_00`, `LDCONF gc.bin`). Незнакомый поток работает как 3.03a.
- **Машина:** Z84C15 (T80 с CTC, SIO, PIO), ACEX с ускорителем, 4 МБ ОЗУ (SDRAM), видео-ОЗУ, ROM и fastram в SRAM, MAX (синхроимпульсы, сброс, загрузка конфигурации).
- **Видео:** режимы ACEX и палитра, удвоение строк до 720 x 576, 50 Гц.
- **Звук:** AY и CBL / Covox ACEX.
- **Диски:** первичный канал IDE, master и slave, на образах жёстких дисков (`.img`, `.hdf`, `.vhd`) на SD-карте; ВГ93 с дисководами A и B на образах дискет (`.img` / `.ima` 720 КБ и 1,44 МБ, `.trd`).
- **Часы:** CMOS / RTC BIOS на часах платы, хранится в `/config/sprinter.eep`.
- **Управление:** USB-клавиатура (скан-коды AT), USB-мышь (последовательная мышь на SIO).

Не сделано: вторичный канал IDE, магнитофон, ISA, физический дисковод на Go, версии BIOS кроме 3.06.

## Как запустить

1. Скопировать `sprinter.kg` (один файл для Go, Mini и Mini G) в корень SD-карты прошивки.
2. Создать на карте папку `/sprinter` и положить туда образ жёсткого диска с DSS. Загрузочный образ из дерева DSS делает `tools/mkhdd.py` (кластер 64 сектора, от 132 МБ: на кластерах меньше загрузчик DSS 1.70 зависает, `docs/storage.md`).
3. Выбрать Sprinter Sp2000 в меню ядер, в OSD смонтировать образ как **HDD Master**, нажать **Menu+F12**.
4. BIOS загрузит DSS с жёсткого диска. При первом запуске BIOS может один раз сообщить об ошибке контрольной суммы CMOS и записать значения по умолчанию.

«Menu» — клавиша Windows. **Del** при старте (держать) — SETUP, **Alt** — альтернативный загрузочный диск. **Ctrl+Alt+Del** — сброс машины, **Menu+F12** — перезагрузка конфигурации (кнопка RESET оригинала).

## Меню OSD

| Пункт | Значения | Клавиши |
|---|---|---|
| Reset | | Menu+F12 |
| Disk A, Disk B | образы дискет `.img .ima .trd` | Menu+F5, Menu+F6 |
| HDD Master, HDD Slave | образы жёстких дисков `.img .hdf .vhd` | |
| VGA Sync (Go) | -H -V / +H -V / -H +V / +H +V | |

## Сборка

`cd src && make minig` (или `go`, `mini`), ISE 14.7; образа BIOS в git нет (`docs/roms.md`, `docs/minig.md`). Симуляция: `src/sim/eq/run_eq.sh` (эквивалентность с сетевыми списками Quartus из AHDL оригинала), `src/sim/machine/run_machine.sh`.

## Источники

- `upstream/sprinter-*`: схемы, BIOS, DOS и программы Спринтера с [gitlab.com/sprinter-computer](https://gitlab.com/sprinter-computer) (подмодули).
- `upstream/tt-*`: AHDL конфигураций ACEX и исходники BIOS от Tolik-Trek (подмодули, см. ниже).
- `tools/fetch_mame.sh`: драйвер Sprinter из MAME (BSD-3-Clause), поведенческий эталон, скачивается в `upstream/mame/`.

## Авторы и лицензия

Verilog логики ACEX / MAX переведён с AHDL Ивана Мака / Peters Plus (конфигурация 2.18, [gitlab.com/sprinter-computer/hard](https://gitlab.com/sprinter-computer/hard)) и восстановленного AHDL Анатолия Белянского (Tolik-Trek): конфигурации 2.06–3.03a ([github.com/Tolik-Trek/SP2000-ACEX](https://github.com/Tolik-Trek/SP2000-ACEX)), конфигурация k30 для BIOS 3.05+ ([zxgit.org/Tolik-Trek/Sprinter-BIOS](https://zxgit.org/Tolik-Trek/Sprinter-BIOS)) и конфигурация SCROLL игры Thunder in the Deep ([github.com/Tolik-Trek/Scroll_CNF](https://github.com/Tolik-Trek/Scroll_CNF)). BIOS 3.06 Hotfix 2 — Sprinter Team (образ из [unreal-ng](https://github.com/alfishe/unreal-ng)). ВГ93 — из MiSTer, IDE — `hdf_ata` из karabas-go-modules.

Наши файлы — GPL-3 (`LICENSE`). Прошивки, ROM и программы Спринтера принадлежат их авторам.
