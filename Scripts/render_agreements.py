"""Render editable agreement sources into the app's PDF resources."""

from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib.colors import HexColor
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A5
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Docs" / "Backend" / "Agreements"
RESOURCES = ROOT / "App" / "CommunityContent"
pdfmetrics.registerFont(TTFont("Fredoka", str(RESOURCES / "Fonts" / "Fredoka-Variable.ttf")))
pdfmetrics.registerFont(TTFont("ComicNeue", str(RESOURCES / "Fonts" / "ComicNeue-Regular.ttf")))
INK = HexColor("#20152f")
VIOLET = HexColor("#644896")
STYLES = {
    "title": ParagraphStyle("Title", fontName="Fredoka", fontSize=25, leading=27,
                            textColor=INK, spaceAfter=6),
    "status": ParagraphStyle("Status", fontName="Fredoka", fontSize=9, leading=13,
                             textColor=VIOLET, spaceAfter=7),
    "section": ParagraphStyle("Section", fontName="Fredoka", fontSize=11, leading=15,
                              textColor=VIOLET, spaceBefore=6, spaceAfter=3, keepWithNext=True),
    "body": ParagraphStyle("Body", fontName="ComicNeue", fontSize=9.6, leading=12.4,
                           alignment=TA_LEFT, textColor=INK, spaceAfter=4),
}


def render(name):
    source = SOURCES / f"{name}.md"
    destination = RESOURCES / f"{name}.pdf"
    story = []
    for line in source.read_text(encoding="utf-8").splitlines():
        if line.startswith("# "):
            story.append(Paragraph(escape(line[2:]), STYLES["title"]))
        elif line.startswith("## "):
            story.append(Paragraph(escape(line[3:]), STYLES["section"]))
        elif line.startswith("Draft "):
            story.append(Paragraph(escape(line), STYLES["status"]))
        elif line:
            story.append(Paragraph(escape(line), STYLES["body"]))
        else:
            story.append(Spacer(1, 1 * mm))
    doc = SimpleDocTemplate(str(destination), pagesize=A5, title=name,
                            leftMargin=13 * mm, rightMargin=13 * mm, topMargin=11 * mm,
                            bottomMargin=9 * mm, invariant=True)
    doc.build(story)


if __name__ == "__main__":
    for agreement in ("Terms", "Privacy"):
        render(agreement)
