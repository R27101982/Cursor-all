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
    ("0:00", "Появление", "Сундук под тканью. Записка №1. Хихиканье. Ровно 2 минуты", "—"),
    ("0:02", "Распределение", "Четыре угла размечены. Шляпа частит, дети бегут", "—"),
    ("0:04", "Палочки", "Палочка-верёвка. Окаменеть. 3 правила. Хихиканье", "—"),
    ("0:07", "Имена + шторм", "Бегут к названному. Люмос-Нокс-Левиоса-Петрификус", "—"),
    ("0:10", "Охота на снитчей", "Подбросить шарики. 4 гнезда. Золотой — в траве", "Л"),
    ("0:16", "Сила", "Состав на руки. Стакан воды. Записка №2", "—"),
    ("0:19", "Кольца квиддича", "Два родителя держат обручи. Третий — на землю", "Г"),
    ("0:25", "Левиоса", "Помощник тянет леску на счёт «три». Записка №3", "А"),
    ("0:29", "Запретная зона", "Снежки, хулахупы, стражи, «Кривоногус»", "А"),
    ("0:35", "Тропа порталов", "Обручи цепочкой. Третий круг — взявшись за руки", "—"),
    ("0:38", "Слово силы", "Музыку выключить. Записка №4. Присесть, шёпотом", "Я"),
    ("0:41", "Финал", "Помощник отпирает сундук + хлопушка", "—"),
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

/* Шпаргалка */
.cheat h1 {
  font-family: "Noto Serif", serif;
  font-size: 19pt;
  color: #2c2a4a;
  margin: 0 0 1mm;
}
.cheat .lead { font-size: 10pt; color: #6b6b6b; margin-bottom: 5mm; }
table { width: 100%; border-collapse: collapse; font-size: 10.5pt; }
th { text-align: left; background: #f2efe6; color: #2c2a4a; border-bottom: 1.5px solid #9a6a1f; }
th, td { padding: 2mm 2.5mm; border-bottom: 1px solid #ddd8c8; vertical-align: top; }
td.t { font-variant-numeric: tabular-nums; color: #9a6a1f; font-weight: 600; white-space: nowrap; }
td.l { font-weight: 700; font-size: 13pt; text-align: center; color: #2c2a4a; }
.cheat h2 { font-family: "Noto Serif", serif; font-size: 13pt; color: #2c2a4a; margin: 7mm 0 2mm; }
.cheat ul { margin: 0; padding-left: 5mm; font-size: 10.5pt; line-height: 1.5; }
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
    return f"""
<section class="sheet cheat">
  <h1>Шпаргалка ведущего</h1>
  <div class="lead">Один лист в карман мантии. Заклинание: А · Г · Л · А · Я</div>
  <table>
    <tr><th>Время</th><th>Блок</th><th>Что не забыть</th><th>Буква</th></tr>
    {rows}
  </table>

  <h2>Сигналы помощнику</h2>
  <ul>
    <li>Хихиканье Пивза — после письма, после сломанной палочки, после второго «А».</li>
    <li>Досыпать снитчи — во второй фазе охоты, незаметно, пока дети отдыхают.</li>
    <li>Леска — тянуть на «три», второй раз выше и держать, пока не заберу свиток.</li>
    <li>Стакан воды — в сцене с дымом, по-настоящему и сразу.</li>
    <li>Секундомер — на втором круге тропы порталов. Рекорд Пивза 20 секунд.</li>
    <li>Замок сундука — отпереть за секунду до хорового «АГЛАЯ».</li>
    <li>Хлопушка и музыка на полную — ровно на слове «Я».</li>
  </ul>

  <h2>Если что-то пошло не так</h2>
  <ul>
    <li>Шумят — молча поднять палочку и ждать. Не перекрикивать.</li>
    <li>Перевозбудились — уронить голос до шёпота и присесть на корточки.</li>
    <li>Угадали имя раньше времени — играть недоверие: «Имя не может быть заклинанием».</li>
    <li>Кольцо Пивза не даётся — молча показать: поднять руку над обручем и разжать пальцы.</li>
    <li>Отстаём — режем 4-ю фазу охоты, прищепки и один круг тропы. Это 5 минут.</li>
    <li>Ребёнок стесняется — хранитель мешка, судья на кольцах, счётчик голов.</li>
    <li>Никакого счёта и выбывания: «Факультеты сегодня не соревнуются, а складываются».</li>
    <li>Пересчитать шарики до ухода с площадки.</li>
  </ul>
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
