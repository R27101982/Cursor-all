"""Собирает печатный PDF сценария из markdown-исходника."""

import html
import re
from pathlib import Path

import markdown

from pdf_render import render

ROOT = Path(__file__).parent
SRC = ROOT / "сценарий-хогвартс-аглая.md"
HTML_OUT = ROOT / "сценарий-хогвартс-аглая.html"
PDF_OUT = ROOT / "Сценарий-Хогвартс-Аглая.pdf"

CSS = """
@page { size: A4; margin: 14mm 14mm 15mm 14mm; }

:root {
  --ink: #1a1a1a;
  --muted: #6b6b6b;
  --gold: #9a6a1f;
  --deep: #2c2a4a;
  --rule: #d8d3c4;
}

* { box-sizing: border-box; }

body {
  font-family: "Source Sans 3", "Noto Sans", sans-serif;
  font-size: 10.8pt;
  line-height: 1.42;
  color: var(--ink);
  margin: 0;
}

h1, h2, h3, h4 { font-family: "Noto Serif", serif; break-after: avoid; }

/* Титул */
.cover { text-align: center; padding-top: 55mm; break-after: page; }
.cover .kicker { font-size: 11pt; letter-spacing: .32em; text-transform: uppercase; color: var(--gold); }
.cover h1 {
  font-size: 34pt; line-height: 1.1; margin: 10mm 0 4mm; color: var(--deep);
}
.cover .sub { font-size: 15pt; color: var(--muted); font-family: "Noto Serif", serif; }
.cover .rule { width: 45mm; height: 2px; background: var(--gold); margin: 12mm auto; }
.cover .meta { font-size: 11pt; line-height: 1.9; }
.cover .meta b { color: var(--deep); }

/* Заголовок блока = крупная плашка со временем */
h1.block {
  font-size: 16pt;
  color: var(--deep);
  margin: 0 0 3.5mm;
  padding: 0 0 2mm 0;
  border-bottom: 2.5px solid var(--gold);
  break-before: page;
}
h1.block .time {
  display: block;
  font-family: "Source Sans 3", sans-serif;
  font-size: 10pt;
  letter-spacing: .22em;
  color: var(--gold);
  margin-bottom: 1.5mm;
}
h1.block:first-of-type { break-before: avoid; }

h1 { font-size: 17pt; color: var(--deep); margin: 9mm 0 3mm; }
h2 { font-size: 14pt; color: var(--deep); margin: 7mm 0 2.5mm; }
h3 { font-size: 12pt; margin: 5mm 0 2mm; }

hr { border: 0; border-top: 1px solid var(--rule); margin: 6mm 0; }

p { margin: 0 0 2.6mm; }

/* Реплики ведущего — то, что читают вслух */
blockquote {
  margin: 3mm 0 3mm 0;
  padding: 1.5mm 0 1.5mm 5mm;
  border-left: 3px solid var(--gold);
  break-inside: avoid;
}
blockquote p {
  font-size: 12.2pt;
  line-height: 1.38;
  margin: 0 0 1.3mm;
  color: #111;
}
blockquote p:last-child { margin-bottom: 0; }

/* Буква-артефакт */
.letter {
  break-inside: avoid;
  text-align: center;
  font-family: "Noto Serif", serif;
  font-size: 52pt;
  font-weight: 700;
  color: var(--deep);
  border: 2.5px solid var(--gold);
  border-radius: 3mm;
  padding: 4mm 0 5mm;
  margin: 5mm auto;
  width: 42mm;
  letter-spacing: .05em;
}

table {
  width: 100%;
  border-collapse: collapse;
  margin: 4mm 0 5mm;
  font-size: 10.4pt;
  break-inside: avoid;
}
th {
  text-align: left;
  background: #f2efe6;
  color: var(--deep);
  font-weight: 600;
  border-bottom: 1.5px solid var(--gold);
}
th, td { padding: 1.8mm 2.5mm; border-bottom: 1px solid var(--rule); vertical-align: top; }

ul, ol { margin: 0 0 3mm; padding-left: 6mm; }
li { margin-bottom: 1.4mm; }

strong { color: #000; }
em { color: var(--muted); }
"""

# «0:10–0:16 — НАЗВАНИЕ» и «5 МИНУТ — НАЗВАНИЕ»: короткая метка слева, название справа.
TIME_RE = re.compile(r"^([^—]{1,20}?)\s+—\s+(.+)$")


def transform(html_body: str) -> str:
    """Оформляет заголовки блоков со временем и одиночные буквы-артефакты."""

    def h1_repl(match: re.Match) -> str:
        inner = match.group(1).strip()
        plain = re.sub(r"<[^>]+>", "", inner)

        if len(plain) <= 2 and plain.isalpha():
            return f'<div class="letter">{plain}</div>'

        timed = TIME_RE.match(plain)
        if timed:
            when, title = timed.groups()
            return (
                f'<h1 class="block"><span class="time">{html.escape(when)}</span>'
                f"{html.escape(title)}</h1>"
            )
        return match.group(0)

    return re.sub(r"<h1>(.*?)</h1>", h1_repl, html_body, flags=re.S)


def build_cover(meta_lines: list[str]) -> str:
    items = "<br>".join(meta_lines)
    return f"""
<section class="cover">
  <div class="kicker">Хогвартс</div>
  <h1>Последнее<br>заклинание</h1>
  <div class="sub">День рождения Аглаи · сценарий на 45 минут</div>
  <div class="rule"></div>
  <div class="meta">{items}</div>
</section>
"""


def main() -> None:
    text = SRC.read_text(encoding="utf-8")

    # Титул собираем отдельно, поэтому шапку из markdown убираем.
    body_md = text.split("---", 1)[1].lstrip() if text.startswith("#") else text

    body = markdown.markdown(body_md, extensions=["tables", "sane_lists"])
    body = transform(body)

    cover = build_cover(
        [
            "<b>Ведущий:</b> профессор Макгонагал, брат Минервы",
            "<b>Дети:</b> 7–10 лет, уличная площадка",
            "<b>Заклинание:</b> А · Г · Л · А · Я",
            "<b>Нужен помощник:</b> один взрослый",
        ]
    )

    page = (
        "<!DOCTYPE html><html lang='ru'><head><meta charset='utf-8'>"
        "<title>Последнее заклинание Хогвартса — сценарий на 45 минут</title>"
        f"<style>{CSS}</style></head><body>{cover}{body}</body></html>"
    )
    HTML_OUT.write_text(page, encoding="utf-8")

    render(HTML_OUT, PDF_OUT)


if __name__ == "__main__":
    main()
