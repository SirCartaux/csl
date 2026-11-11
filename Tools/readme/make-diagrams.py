#!/usr/bin/env python3
"""Exact, dependency-free SVG figures for the README."""
from pathlib import Path
from html import escape

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/readme'
OUT.mkdir(parents=True, exist_ok=True)

def svg(width, height, title, content):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-label="{escape(title)}">
<title>{escape(title)}</title>
<style>text{{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Arial,sans-serif}}.mono{{font-family:SFMono-Regular,Consolas,monospace}}</style>
<rect width="{width}" height="{height}" rx="24" fill="#10121B"/>
{content}</svg>'''

def text(x, y, value, size=18, fill='#EDE6D6', weight=500, cls=''):
    return f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" font-weight="{weight}" class="{cls}">{escape(value)}</text>'

cards = []
for x, key, title, note in [(30, '⌘ SPACE', 'Open', 'A shortcut to your next thing.'),
                           (420, 'TAB', 'Browse', 'Your query stays yours.'),
                           (810, 'RETURN', 'Go', 'Open the selected result.')]:
    cards += [f'<rect x="{x}" y="24" width="360" height="192" rx="16" fill="#161925" stroke="#282D3D"/>',
              f'<rect x="{x+25}" y="48" width="150" height="49" rx="8" fill="#222737" stroke="#62628A"/>',
              text(x+44,80,key,22,'#FFC24B',650,'mono'),
              text(x+25,139,title,25,'#EDE6D6',650),
              text(x+25,178,note,16,'#A0A9BF')]
(OUT/'keyboard.svg').write_text(svg(1200,240,'Open with Command Space, browse with Tab, go with Return',''.join(cards)))

parts=[text(38,43,'THE SEARCH PATH',15,'#FFC24B',650,'mono')]
for y,label,note in [(74,'Apps + websites','Ready sources'),(168,'Indexed folders','Live FSEvents index'),(262,'Spotlight files','Streamed results')]:
    parts += [f'<rect x="38" y="{y}" width="230" height="72" rx="12" fill="#161925" stroke="#3D455B"/>',
              text(57,y+29,label,19),text(57,y+52,note,13,'#A0A9BF')]
    cy=y+36
    parts.append(f'<path d="M268 {cy} H303 V204 H346" fill="none" stroke="#62628A" stroke-width="2"/>')
for x,title,sub,tint in [(346,'Search','Merge + stream','#FFC24B'),(628,'Local ranking','Match + usage context','#C6B5FF'),(910,'Native actions','Open · preview · reveal','#74E08A')]:
    parts += [f'<rect x="{x}" y="155" width="252" height="98" rx="14" fill="#161925" stroke="{tint}"/>',
              text(x+21,197,title,23,tint,650),text(x+21,227,sub,15,'#A0A9BF')]
    if x<910:
        parts.append(f'<path d="M{x+252} 204 h28 m-7 -5 7 5 -7 5" fill="none" stroke="#62628A" stroke-width="2"/>')
parts.append(text(346,312,'Ranking and learning stay on your Mac.',16,'#A0A9BF'))
(OUT/'search-flow.svg').write_text(svg(1200,372,'Search sources flow into search, local ranking and native actions',''.join(parts)))
print('Created keyboard.svg and search-flow.svg')
