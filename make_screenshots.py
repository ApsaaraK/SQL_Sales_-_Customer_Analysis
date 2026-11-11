#!/usr/bin/env python3
"""
make_screenshots.py - (optional) renders the database diagram and one image per query
(SQL on top, result table below) into screenshots/. Needs: pip install playwright && playwright install chromium
"""
import html
import re
from pathlib import Path

import pandas as pd
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).parent
OUT = ROOT / "screenshots"
OUT.mkdir(exist_ok=True)

# ------------------------------------------------------------------ database diagram
TABLES = {
    "customers":   (30, 50,  [("customer_id", "text", "PK"), ("district", "text", ""), ("province", "text", ""), ("signup_date", "date", "")]),
    "orders":      (300, 50, [("order_id", "text", "PK"), ("order_date", "date", ""), ("customer_id", "text", "FK"), ("channel", "text", "")]),
    "order_items": (570, 50, [("order_item_id", "text", "PK"), ("order_id", "text", "FK"), ("product_id", "text", "FK"),
                              ("quantity", "integer", ""), ("list_price", "numeric", ""), ("discount_pct", "numeric", ""), ("returned", "smallint", "")]),
    "products":    (840, 50, [("product_id", "text", "PK"), ("product_name", "text", ""), ("category", "text", ""),
                              ("list_price", "numeric", ""), ("unit_cost", "numeric", "")]),
}
W, HEAD, ROW = 210, 30, 24


def row_y(table, col):
    x, y, cols = TABLES[table]
    idx = [c[0] for c in cols].index(col)
    return y + HEAD + idx * ROW + ROW / 2


def erd_svg():
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="285" font-family="Arial, Helvetica, sans-serif">',
             '<rect width="1080" height="285" fill="#f5f6f8"/>',
             '<text x="30" y="30" font-size="16" font-weight="bold" fill="#1b2430">Retail database: four tables, one-to-many relationships</text>']

    def link(child, ccol, parent, pcol, child_side, parent_side):
        cx = TABLES[child][0] + (0 if child_side == "left" else W)
        px = TABLES[parent][0] + (0 if parent_side == "left" else W)
        cy, py = row_y(child, ccol), row_y(parent, pcol)
        parts.append(f'<line x1="{px}" y1="{py}" x2="{cx}" y2="{cy}" stroke="#2a9d8f" stroke-width="2"/>')
        parts.append(f'<text x="{px + (-8 if parent_side == "left" else 8)}" y="{py - 6}" font-size="12" font-weight="bold" fill="#1f3864" text-anchor="{"end" if parent_side == "left" else "start"}">1</text>')
        parts.append(f'<text x="{cx + (-8 if child_side == "left" else 8)}" y="{cy - 6}" font-size="12" font-weight="bold" fill="#1f3864" text-anchor="{"end" if child_side == "left" else "start"}">N</text>')

    for name, (x, y, cols) in TABLES.items():
        h = HEAD + ROW * len(cols)
        parts.append(f'<rect x="{x}" y="{y}" width="{W}" height="{h}" rx="6" fill="#fff" stroke="#1f3864" stroke-width="1.5"/>')
        parts.append(f'<path d="M{x},{y + HEAD} V{y + 6} Q{x},{y} {x + 6},{y} H{x + W - 6} Q{x + W},{y} {x + W},{y + 6} V{y + HEAD} Z" fill="#1f3864"/>')
        parts.append(f'<text x="{x + 12}" y="{y + 20}" font-size="14" font-weight="bold" fill="#fff">{name}</text>')
        for i, (col, typ, flag) in enumerate(cols):
            cy = y + HEAD + i * ROW + 16
            colour = "#b9770e" if flag == "PK" else "#2a9d8f" if flag == "FK" else "#1b2430"
            parts.append(f'<text x="{x + 12}" y="{cy}" font-size="12" fill="{colour}" font-weight="{"bold" if flag else "normal"}">{col}</text>')
            parts.append(f'<text x="{x + W - 10}" y="{cy}" font-size="11" fill="#5b6573" text-anchor="end">{(flag + "  ") if flag else ""}{typ}</text>')
    link("orders", "customer_id", "customers", "customer_id", "left", "right")
    link("order_items", "order_id", "orders", "order_id", "left", "right")
    link("order_items", "product_id", "products", "product_id", "right", "left")
    parts.append("</svg>")
    return "".join(parts)


# ------------------------------------------------------------------ query pages
KEYWORDS = r"\b(WITH|AS|SELECT|FROM|WHERE|GROUP BY|ORDER BY|JOIN|LEFT JOIN|CROSS JOIN|ON|USING|LIMIT|OVER|PARTITION BY|FILTER|CASE|WHEN|THEN|ELSE|END|DISTINCT|COUNT|SUM|AVG|ROUND|LAG|RANK|ROW_NUMBER|MIN|MAX|COALESCE|NULLIF|DESC|ASC|AND|WINDOW|ROWS BETWEEN|PRECEDING|CURRENT ROW)\b"
QUESTIONS = {
    "q1_top_customers": "Q1. Which customers generate the most revenue?",
    "q2_repeat_customers": "Q2. What percentage of customers make another purchase?",
    "q3_monthly_revenue": "Q3. How does monthly revenue change?",
    "q4_bought_together": "Q4. Which products are commonly bought together?",
    "q5_inactive_customers": "Q5. Which customers have become inactive?",
    "q6_category_revenue": "Q6. Which categories contribute the most revenue?",
}
CSS = """body{font-family:Arial,Helvetica,sans-serif;background:#f5f6f8;margin:0;padding:24px;width:1052px;color:#1b2430}
h1{font-size:18px;margin:0 0 12px}h2{font-size:13px;color:#5b6573;margin:18px 0 6px;text-transform:uppercase;letter-spacing:.5px}
pre{background:#10151c;color:#d6deeb;padding:14px 16px;border-radius:8px;font:12px/1.5 Consolas,monospace;margin:0;white-space:pre-wrap}
.k{color:#7fb3ff;font-weight:bold}.c{color:#7f8c9b}
table{border-collapse:collapse;background:#fff;font-size:12px;border-radius:8px;overflow:hidden;box-shadow:0 1px 2px rgba(0,0,0,.1)}
th{background:#1f3864;color:#fff;padding:7px 10px;text-align:left}td{padding:6px 10px;border-top:1px solid #e6e9ee;text-align:right}
td:first-child,th:first-child{text-align:left}"""


def highlight(sql):
    lines = []
    for line in sql.rstrip().splitlines():
        if line.strip().startswith("--"):
            lines.append(f'<span class="c">{html.escape(line)}</span>')
        else:
            lines.append(re.sub(KEYWORDS, r'<span class="k">\1</span>', html.escape(line), flags=re.I))
    return "\n".join(lines)


def query_page(name):
    sql = (ROOT / "sql" / "queries" / f"{name}.sql").read_text(encoding="utf-8")
    df = pd.read_csv(ROOT / "results" / f"{name}.csv")
    shown = df.head(12)
    table = shown.to_html(index=False, na_rep="", border=0, float_format=lambda v: f"{v:,.2f}")
    note = f"<p style='font-size:11px;color:#5b6573'>Showing {len(shown)} of {len(df)} rows.</p>" if len(df) > len(shown) else ""
    return (f"<html><head><meta charset='utf-8'><style>{CSS}</style></head><body><h1>{QUESTIONS[name]}</h1>"
            f"<h2>SQL (PostgreSQL)</h2><pre>{highlight(sql)}</pre><h2>Result</h2>{table}{note}</body></html>")


with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 1100, "height": 400})
    page.set_content(f"<body style='margin:0'>{erd_svg()}</body>")
    page.set_viewport_size({"width": 1080, "height": 285})
    page.screenshot(path=str(OUT / "database_diagram.png"))
    page.set_viewport_size({"width": 1100, "height": 400})
    for name in QUESTIONS:
        page.set_content(query_page(name))
        page.screenshot(path=str(OUT / f"{name}.png"), full_page=True)
    browser.close()
print("Screenshots written to", OUT)
