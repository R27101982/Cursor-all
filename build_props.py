"""Собирает печатный реквизит: буквы-артефакты, записки Пивза и шпаргалку ведущего."""

from pathlib import Path

from pdf_render import render

ROOT = Path(__file__).parent
HTML_OUT = ROOT / "реквизит-для-печати.html"
PDF_OUT = ROOT / "Реквизит-для-печати.pdf"

LETTERS = [
    ("Л", "первый артефакт", "внутрь золотого снитча, снитч — в траву у края площадки"),
    ("Г", "второй артефакт", "привязать ниткой к кольцу Пивза, которое лежит на земле"),
    ("А", "третий артефакт", "под сундук, на землю"),
    ("А", "четвёртый артефакт", "в хулахуп в Запретной зоне"),
    ("Я", "пятый артефакт", "в карман имениннице, заранее и через маму"),
]

NOTES = [
    (
        "№1 — в самом начале, из чемодана",
        [
            "Профессор!",
            "Заклинание я спрятал.",
            "Ищите. Только вы всё равно",
            "не найдёте, потому что вы",
            "взрослый и скучный.",
        ],
    ),
    (
        "№2 — после проверки силы, перед кольцами",
        [
            "Одну нашли.",
            "Вторую я закинул в кольцо.",
            "Достаньте,",
            "если умеете летать.",
        ],
    ),
    (
        "№3 — после того, как подняли сундук",
        [
            "Четвёртая буква",
            "у стражей.",
            "Они спят.",
            "Разбудите — пожалеете.",
        ],
    ),
    (
        "№4 — перед последним испытанием",
        [
            "Последнюю букву",
            "я не прятал.",
            "Её нельзя найти.",
            "Её можно только",
            "получить в подарок.",
        ],
    ),
]

CUES = [
    ("0:00", "Появление", "Сундук под тканью. Записка №1. Хихиканье", "—"),
    ("0:03", "Шляпа", "Четыре обруча — круги факультетов. Палочки и 3 правила", "—"),
    ("0:08", "Палочки", "Палочка-верёвка. Окаменеть. Хихиканье", "—"),
    ("0:11", "Шторм", "Люмос — Нокс — Левиоса — Петрификус — Риддикулус", "—"),
    ("0:14", "Клещи Пивза", "Прищепки всем и себе. С себя снимать нельзя", "—"),
    ("0:17", "Сила", "Состав на руки. Стакан воды у помощника", "—"),
    ("0:20", "Искра", "Стаканчики всем. Шарик по цепочке. Кубок на сундук", "—"),
    ("0:23", "Охота на снитчей", "Руками нельзя — ложки. Рукавицы. Золотой. Записка №2", "Л"),
    ("0:30", "Кольца квиддича", "Родители держат обручи. Стаканчики. Кольцо — на землю", "Г"),
    ("0:35", "Левиоса", "Помощник тянет леску на счёт «три». Записка №3", "А"),
    ("0:39", "Запретная зона", "Снежки, переодевание, «Кривоногус», шарф", "А"),
    ("0:44", "Тропа порталов", "Обручи цепочкой. Второй круг — взявшись за руки", "—"),
    ("0:46", "Имя вслух", "Музыку выключить. Записка №4. Палочки на Аглаю, хором имя", "Я"),
    ("0:48", "Финал", "Отпереть сундук + хлопушка. Подарок и свечи", "—"),
    ("0:52", "Круг", "Медали каждому, пожелания, хором «С днём рождения»", "—"),
]

BONUS = [
    "Дуэль факультетов — танцевальный баттл, музыка по 40 секунд",
    "Магические фанты — мешочек и карточки заданий, работает сидя",
    "Парные заклинания — ленточки, найди свой цвет",
    "Поиск цвета — два круга мелом, «раз, два, три — жёлтый найди»",
]

CSS = """
@page { size: A4; margin: 12mm; }
* { box-sizing: border-box; }
body { margin: 0; font-family: "Source Sans 3", sans-serif; color: #1a1a1a; }

.sheet { height: 273mm; break-after: page; display: flex; flex-direction: column; }
.sheet:last-child { break-after: auto; }

/* Буква-артефакт */
.letter-sheet { align-items: center; justify-content: center; text-align: center; }
.frame {
  border: 4px double #9a6a1f;
  border-radius: 6mm;
  padding: 20mm 38mm 14mm;
  background: #fcfaf4;
}
.glyph {
  font-family: "Noto Serif", serif;
  font-size: 270pt;
  font-weight: 700;
  line-height: 1;
  color: #2c2a4a;
}
.frame .caption {
  margin-top: 8mm;
  font-size: 11pt;
  letter-spacing: .3em;
  text-transform: uppercase;
  color: #9a6a1f;
}
.hint { margin-top: 10mm; font-size: 10pt; color: #8a8a8a; }

/* Мини-буквы: вкладыш в снитч и запасные */
.mini-sheet h1 { font-family: "Noto Serif", serif; font-size: 19pt; color: #2c2a4a; margin: 0 0 1mm; }
.mini-sheet .lead { font-size: 10pt; color: #6b6b6b; margin-bottom: 8mm; }
.mini-grid { display: flex; flex-wrap: wrap; gap: 6mm; }
.mini {
  width: 22mm; height: 22mm;
  border: 1px dashed #9a6a1f;
  display: flex; align-items: center; justify-content: center;
  font-family: "Noto Serif", serif;
  font-size: 26pt; font-weight: 700; color: #2c2a4a;
}

/* Записка Пивза */
.note-sheet { justify-content: center; }
.note {
  border: 2px dashed #999;
  padding: 16mm 14mm;
  margin: 0 7mm;
  background: #fdfdf8;
  transform: rotate(-0.8deg);
}
.note .line {
  font-family: "Noto Serif", serif;
  font-style: italic;
  font-size: 26pt;
  line-height: 1.55;
  color: #23233a;
}
.note .sign {
  text-align: right;
  font-family: "Noto Serif", serif;
  font-style: italic;
  font-size: 30pt;
  margin-top: 8mm;
  color: #23233a;
  transform: rotate(-3deg);
}
.note-when {
  margin-bottom: 6mm;
  font-size: 10pt;
  letter-spacing: .18em;
  text-transform: uppercase;
  color: #9a6a1f;
}

/* Шпаргалка: обычный поток, иначе многоколоночный блок обрезается по высоте */
.sheet.cheat { display: block; height: auto; }
.cheat h1 {
  font-family: "Noto Serif", serif;
  font-size: 19pt;
  color: #2c2a4a;
  margin: 0 0 1mm;
}
.cheat .lead { font-size: 10pt; color: #6b6b6b; margin-bottom: 5mm; }
table { width: 100%; border-collapse: collapse; font-size: 10.4pt; }
th { text-align: left; background: #f2efe6; color: #2c2a4a; border-bottom: 1.5px solid #9a6a1f; }
th, td { padding: 1.8mm 2.5mm; border-bottom: 1px solid #ddd8c8; vertical-align: top; }
td.t { font-variant-numeric: tabular-nums; color: #9a6a1f; font-weight: 600; white-space: nowrap; }
td.l { font-weight: 700; font-size: 13.5pt; text-align: center; color: #2c2a4a; }
.cheat h2 {
  font-family: "Noto Serif", serif;
  font-size: 13pt;
  color: #2c2a4a;
  margin: 0 0 2mm;
  break-after: avoid;
}
.cheat ul { margin: 0 0 5mm; padding-left: 4.5mm; font-size: 9.6pt; line-height: 1.4; }
.cheat-cols { column-count: 2; column-gap: 7mm; margin-top: 5mm; }
.cheat-cols section { break-inside: avoid; }
"""


def letter_sheet(glyph: str, caption: str, where: str) -> str:
    return f"""
<section class="sheet letter-sheet">
  <div class="frame">
    <div class="glyph">{glyph}</div>
    <div class="caption">{caption}</div>
  </div>
  <div class="hint">Спрятать: {where}. Свернуть в свиток и перевязать нитью.</div>
</section>
"""


def mini_sheet() -> str:
    cells = "".join(
        f'<div class="mini">{glyph}</div>'
        for _ in range(4)
        for glyph, *_ in LETTERS
    )
    return f"""
<section class="sheet mini-sheet">
  <h1>Мини-буквы</h1>
  <div class="lead">
    Вырезать по пунктиру и свернуть в трубочку. Буква Л кладётся внутрь золотого снитча —
    большая карточка туда не влезет. Остальные — запасные, на случай дождя и потерь.
  </div>
  <div class="mini-grid">{cells}</div>
</section>
"""


def note_sheet(when: str, lines: list[str]) -> str:
    body = "".join(
        f'<div class="line" style="transform: rotate({(-1) ** i * 0.5:.1f}deg)">{line}</div>'
        for i, line in enumerate(lines)
    )
    return f"""
<section class="sheet note-sheet">
  <div class="note-when">Записка {when}</div>
  <div class="note">
    {body}
    <div class="sign">Пивз</div>
  </div>
</section>
"""


def cheat_sheet() -> str:
    rows = "".join(
        f'<tr><td class="t">{t}</td><td><b>{name}</b></td><td>{what}</td>'
        f'<td class="l">{letter}</td></tr>'
        for t, name, what, letter in CUES
    )
    bonus = "".join(f"<li>{item}</li>" for item in BONUS)
    return f"""
<section class="sheet cheat">
  <h1>Шпаргалка ведущего</h1>
  <div class="lead">
    Два листа в карман мантии: тайминг и напоминания. Полная версия 55 минут. Заклинание: А · Г · Л · А · Я.
    Чтобы уложиться в 45 — выбросить «Клещей Пивза» и «Тропу порталов», сократить охоту и кольца.
  </div>
  <table>
    <tr><th>Время</th><th>Блок</th><th>Что не забыть</th><th>Буква</th></tr>
    {rows}
  </table>

  <div class="cheat-cols">
    <section>
      <h2>Сигналы помощнику</h2>
      <ul>
        <li>Хихиканье Пивза — после письма, после сломанной палочки, после второго «А».</li>
        <li>Подбросить прищепки — через минуту после начала «Клещей».</li>
        <li>Ложки — раздать сразу после команды «руками нельзя».</li>
        <li>Досыпать снитчи — перед заклятием неуклюжести, пока дети отдыхают.</li>
        <li>Искра в кубок на сундуке — после каждой найденной буквы.</li>
        <li>Леска — тянуть на «три», второй раз выше и держать, пока не заберу свиток.</li>
        <li>Стакан воды — в сцене с дымом, по-настоящему и сразу.</li>
        <li>Секундомер — на тропе порталов. Рекорд Пивза 20 секунд.</li>
        <li>Замок сундука — отпереть за секунду до хорового «АГЛАЯ».</li>
        <li>Хлопушка и музыка на полную — ровно на слове «Я».</li>
      </ul>
    </section>

    <section>
      <h2>После торта, по 5 минут</h2>
      <ul>
        {bonus}
      </ul>
    </section>

    <section>
      <h2>Если что-то пошло не так</h2>
      <ul>
        <li>Шумят — молча поднять палочку и ждать. Не перекрикивать.</li>
        <li>Перевозбудились — уронить голос до шёпота и присесть на корточки.</li>
        <li>Угадали имя раньше времени — играть недоверие: «Имя не может быть заклинанием».</li>
        <li>Кольцо Пивза не даётся — молча показать: поднять руку над обручем и разжать пальцы.</li>
        <li>Отстаём — режем 4-ю фазу охоты, переодевание и второй круг тропы.</li>
        <li>Ребёнок стесняется — хранитель мешка, судья на кольцах, счётчик голов.</li>
        <li>Никакого счёта и выбывания: «Факультеты не соревнуются, а складываются».</li>
        <li>Пересчитать шарики до ухода с площадки.</li>
      </ul>
    </section>
  </div>
</section>
"""


def main() -> None:
    sheets = [cheat_sheet()]
    sheets += [letter_sheet(*item) for item in LETTERS]
    sheets.append(mini_sheet())
    sheets += [note_sheet(when, lines) for when, lines in NOTES]

    page = (
        "<!DOCTYPE html><html lang='ru'><head><meta charset='utf-8'>"
        "<title>Реквизит для печати</title>"
        f"<style>{CSS}</style></head><body>{''.join(sheets)}</body></html>"
    )
    HTML_OUT.write_text(page, encoding="utf-8")

    render(HTML_OUT, PDF_OUT)


if __name__ == "__main__":
    main()
