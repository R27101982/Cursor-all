"""Собирает печатный реквизит: буквы-артефакты, записки Пивза и шпаргалку ведущего."""

from pathlib import Path

from pdf_render import render

ROOT = Path(__file__).parent
HTML_OUT = ROOT / "реквизит-для-печати.html"
PDF_OUT = ROOT / "Реквизит-для-печати.pdf"

LETTERS = [
    ("Л", "первый артефакт", "под сундуком"),
    ("Г", "второй артефакт", "в хулахупе у стража"),
    ("А", "третий артефакт", "под жёлтым предметом"),
    ("А", "четвёртый артефакт", "на ленте в центре паутины"),
    ("Я", "пятый артефакт", "в кармане у именинницы"),
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
        "№2 — после того, как подняли сундук",
        [
            "Одну нашли.",
            "Вторую не найдёте:",
            "я отдал её стражам",
            "в Запретную зону.",
        ],
    ),
    (
        "№3 — перед поиском по цвету",
        [
            "Третья буква лежит там,",
            "где я захочу.",
            "Ищите по всей площадке,",
            "мне нравится,",
            "когда вы бегаете.",
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
    ("0:03", "Шляпа + имена", "Шляпа. Палочки детям. 3 правила", "—"),
    ("0:08", "Палочки", "Палочка-верёвка. Окаменеть. Хихиканье", "—"),
    ("0:11", "Шторм", "Музыка старт/стоп. Люмос-Нокс-Левиоса-Петрификус", "—"),
    ("0:14", "Сила", "Состав на руки. Стакан воды у помощника", "—"),
    ("0:17", "Левиоса", "Помощник тянет леску на счёт «три»", "Л"),
    ("0:22", "Запретная зона", "Снежки, хулахупы, стражи. Записка №2", "Г"),
    ("0:28", "Поиск цвета", "Мелом два круга. Записка №3", "А"),
    ("0:33", "Нити", "Ленты. Паутина. Кристалл в центре", "А"),
    ("0:38", "Слово силы", "Музыку выключить. Записка №4", "Я"),
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
    <li>Леска — тянуть на «три», второй раз выше и держать, пока не заберу свиток.</li>
    <li>Стакан воды — в сцене с дымом, по-настоящему и сразу.</li>
    <li>Замок сундука — отпереть за секунду до хорового «АГЛАЯ».</li>
    <li>Хлопушка и музыка на полную — ровно на слове «Я».</li>
  </ul>

  <h2>Если что-то пошло не так</h2>
  <ul>
    <li>Шумят — молча поднять палочку и ждать. Не перекрикивать.</li>
    <li>Угадали имя раньше времени — играть недоверие: «Имя не может быть заклинанием».</li>
    <li>Отстаём — режем эстафету с прищепками и фазу хаоса с лентами. Это 4 минуты.</li>
    <li>Ребёнок стесняется — берём в помощники следить за Пивзом, не тащим в игру.</li>
    <li>Никакого счёта и выбывания: «Факультеты сегодня не соревнуются, а складываются».</li>
  </ul>
</section>
"""


def main() -> None:
    sheets = [cheat_sheet()]
    sheets += [letter_sheet(*item) for item in LETTERS]
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
