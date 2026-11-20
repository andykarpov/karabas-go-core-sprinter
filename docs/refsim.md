# Эталон: AHDL оригинала в симуляции (Ф0.2)

Оригинальный AHDL собирается Quartus 13 под Cyclone IV E в функциональный сетевой список Verilog (`.vo`). Его гоняет iverilog вместе с атомами Altera; наш перевод сравнивается с ним по модулям.

## Сборка

```
src/sim/ahdl/build_ref.sh [SRC] [TOP] [NAME]   # по умолчанию ACEX SP2_ACEX
```

| SRC | Исходник | Верх |
|---|---|---|
| `ACEX`, `MAX` | `upstream/sprinter-hard/MaxPlus2/{ACEX,MAX}` (2.18 Peters Plus) | `SP2_ACEX`, `SP2_MAX` |
| `303A` | `upstream/tt-sp2000-acex` (3.03a, основа перевода) | `BASE_303` |
| `K30` | `upstream/tt-sprinter-bios` @ 085ef3c `src/altera/acex/k30` (BIOS 3.05+) | `SP2_ACEX` (NAME `K30`) |
| `SCROLL` | `upstream/tt-scroll-cnf/src` (конфигурация игры) | `SCROLL` |
| каталог | любой каталог с `.TDF` / `.INC` / `.MIF` | — |

- Quartus — образ `karabas-quartus:13.0sp1` (docker, без сети), ~10 с на модуль. Результат: `src/sim/ahdl/build/<TOP>/simulation/modelsim/<TOP>.vo` (вне git).
- Атомы для iverilog: `/opt/altera/quartus/eda/sim_lib/cycloneive_atoms.v` + `altera_primitives.v` (`dffeas`); в образе docker их нет. Другой путь — переменная `QUARTUS_SIM_LIB`.
- Исходники писались под DOS: `INCLUDE "kbd"` ищет `kbd.inc`, поэтому скрипт кладёт рядом копии в нижнем регистре.
- MIF в синтаксисе MAX+plus II (`адрес : v1 v2 v3 ...;`) Quartus 13 не принимает: `tools/mif.py mif` переписывает их по адресу на строку (`tools/mif.py hex` даёт файл для `$readmemh`). MIF каталога `sprinter-hard/Quartus2/` испорчены (`docs/ahdl.md` п. 6.1) — его не берём; MIF `MaxPlus2/`, 3.03a и k30 совпадают слово в слово.

Все верхние уровни и подмодули собираются без ошибок (2026-11-20; модули — 2.18):

| TOP | LE | регистры | бит памяти |
|---|---|---|---|
| SP2_ACEX | 1 411 | 961 | 14 080 |
| DCP | 207 | 115 | 4 096 |
| VIDEO2 | 302 | 233 | 0 |
| ACCELER | 202 | 145 | 2 048 |
| AY | 228 | 181 | 2 048 |
| KBD | 89 | 61 | 2 048 |
| MOUSE | 50 | 44 | 0 |
| SP2_MAX | 104 | 56 | 0 |
| BASE_303 (3.03a) | 1 436 | | |
| K30 | 1 426 | | |
| SCROLL | 1 190 | | |

(В ACEX у оригинала 1 569 LE: другая технология и упаковка; у Cyclone IV 4-входовые LUT те же, порядок величины совпадает.)

## Оговорки

- Память: Quartus предупреждает «ALTDPRAM / altram doesn't support Cyclone IV E … read during write behavior will be different». У EAB ACEX адрес защёлкивается по `inclock`, выход — по `outclock` или без регистра; у M9K адрес всегда регистровый. Для `lpm_ram_dq` / `lpm_ram_dp` с `inclock` / `rdclock` = `CLK42` (KBD, AY, DCP, ACCELER, CBL) поведение совпадает; чтение в такте записи может отличаться — в сравнительных тестах такие такты не сравнивать.
- Сетевой список — функциональный: задержки `LCELL` / `EXP` оригинала (фильтры «anti gluk», формирователи импульсов) в нём нулевые. Где AHDL опирается на задержку, эталон ведёт себя как идеальная логика; такие места перечислены в `docs/ahdl.md`.
- Скорость iverilog на атомах: ~1 мс модельного времени за ~8 с для SP2_MAX. Кадр (20 мс) — минуты; длинные прогоны — verilator или поведенческие тесты.

## Проверка потока

`src/sim/ahdl/run_max_smoke.sh` — SP2_MAX от 42 МГц: CLK14 = 14,000 МГц, строка 64,0 мкс (секунды). С `+frame` — ещё кадр: 20,48 мс = 320 строк (~4 мин, только по необходимости).

## Как сравниваем перевод (Ф1)

Стенд на модуль: эталонный `.vo` и наш Verilog получают одинаковые входы (случайные + сценарии: циклы Z80 чтения / записи памяти и портов, M1, обновление), выходы сравниваются в каждом такте 42 МГц (для нашего модуля — в такте его разрешения). Расхождение — `<tb>: N errors` с первым тактом и сигналом.
