# Версии конфигурации ACEX: 2.18 → 3.03a и k30 (Ф1.0)

Источники: коммиты `upstream/tt-sp2000-acex` (3.00 `e93c37c8`, 3.03 `ea1f5e1b`, 3.03a `26b05fdf`) и k30 (`upstream/tt-sprinter-bios` @ 085ef3c `src/altera/acex/k30`), сравнение с 2.18 (`sprinter-hard/MaxPlus2`). Строки ниже — по `BASE_303.TDF`, `DCP.TDF`, `VIDEO2.TDF` 3.03a.

## 2.18 → 3.00 («программа может гасить изображение»)

- `SVIDEO.DIR_PORT[4] = RGMOD2` (было `GND` или `RGMOD1` при `SCREEN_OFF = "USE"`): бит 2 регистра видеорежима (порт `C5`) гасит изображение.

## 3.00 → 3.03 («программное управление клавиатурой, прерыванием и сбросом»)

| Где | 3.00 | 3.03 |
|---|---|---|
| `/RESET` | `!DFF(KEYS.kb_reset & SOFT_RESET)` | `!DFF((KEYS.kb_reset or !ALL_MODE5) & SOFT_RESET)` — Ctrl+Alt+Del запрещается битом 5 `ALL_MODE` |
| `KEYS.ena` | `!ALL_MODE0` | `ALL_MODE1` — чтение матрицы ZX по биту 1 |
| `NMI_X` | `GND` (или Alt+F12 при `NMI_ON`) | `!ALL_MODE4 & kb_alt & !kb_f12` — NMI по Alt+F12, запрет битом 4 |
| `CAS_A` | `LCELL(DECODE.CAS)` | `DECODE.CAS or DFF(!MC_WRITE & DECODE.CAS)` — CAS при записи на такт дольше |
| `/WE` | `DFFE(/WE_OUT or DECODE.RAS, CLK42, , /RESET)` | `!DFF(!/WE_OUT & !DECODE.CAS, !CLK42, !/WE_OUT & !DECODE.RAS)` — по спаду 42 МГц |
| `BLK_MR` | комбинационный | триггер на CLK42 (та же функция) |
| `ZX_PORT[6]` | `SP_SCR & !(A13 & !G_LINE7) & !G_LINE6` | `… & !ALL_MODE0` — бит 0 `ALL_MODE` отключает дублирование ZX-экрана в видео-ОЗУ |
| DCP `RAS.ena` / `CAS.ena` | одной формулой | разбиты на `LCELL` (та же функция) |
| VIDEO2 `V_CS0` | `GND` | `DFF(!VCM0 & VCM1, CLK42, V_CSX1)` — вторая страница видео-ОЗУ (512 КБ) |
| `DCP.MIF` | ячейка `EE` = `2000` | `2041` (3.03), снова `2000` в 3.03a (страница перехвата Reset после SCROLL) |

Это закрывает часть пунктов «3.0x?» из `docs/mame.md`: биты `ALL_MODE` 0, 1, 4, 5 (D2), дублирование ZX-экрана, гашение. Код 89 на чтение (D4), бит 1 данных кодов 16 / 17 (D12), `PN5` (D14) в 3.03a **не менялись** — у MAME это либо k30, либо ошибка эмулятора.

## k30 (BIOS 3.05 / 3.06): отдельная ветка от 2.18

k30 сделан из авторского 2.18 (ACCELER, AY — байт в байт), изменений 3.00–3.03 в нём нет. Своё:

| Где | 2.18 | k30 |
|---|---|---|
| `KEYS.int_ena` | `ALL_MODE0` | `ALL_MODE0 & ALL_MODE3` — прерывание клавиатуры по биту 3 (MAME: `(ALL_MODE & 9) == 9`) |
| `KEYS.ena` | `!ALL_MODE0` | `VCC` — матрица ZX всегда |
| `ZX_PORT[6]` | без `ALL_MODE0` | `… & !ALL_MODE0` (как 3.03) |
| DCP `PN[7..5].clrn` | `/RESET & CNF7` | `PN[7..6]` — `PN5` больше не ставится вместе с Pentagon-512 |
| VIDEO2 | — | формирователь записи в видео-ОЗУ (`V_WEMM…`, `F_WR`, цепочки `LCELL` — задержки, у нас не нужны), `WR_PIC.d = MODE0[5]`, `TSN_W3.d = X_MODE_BOND` |

Вывод для ядра: перевод 3.03a, параметр / пункт OSD «Config 3.03 / 3.05+» переключает перечисленные строки; VIDEO2 k30 — сверить по эталону при переводе VIDEO2 (`WR_PIC`, `TSN_W3`).
