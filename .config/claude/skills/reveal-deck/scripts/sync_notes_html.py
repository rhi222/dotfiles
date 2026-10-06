#!/usr/bin/env python3
"""_reveal.html から、ノートとコメント機能つきの閲覧用 .html を作り直す。

使い方: sync_notes_html.py <deck>_reveal.html [<deck>.html]
  出力先を省略すると、入力名から "_reveal" を除いた名前に書く。
  スライド本体とスタイルは _reveal.html をそのまま使い、ノートは <aside class="notes"> から作る。
"""
import re, sys, pathlib

src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_name(src.name.replace('_reveal', ''))
shell = (pathlib.Path(__file__).parent.parent / 'assets' / 'notes_shell.html').read_text()
r = src.read_text()

style = r[r.index('<style>'):r.index('</style>') + 8]
extra = '''
  @page { size: 10in 5.625in; margin: 0; }
  @media print {
    html, body { background: #fff; }
    .wrap { max-width: none; padding: 0; margin: 0; }
    .slide { margin: 0; border: none; border-radius: 0; box-shadow: none; page-break-after: always; break-after: page; width: 10in; height: 5.625in; }
  }
  /* 閲覧用：reveal.js なしで同じ見た目にする */
  .reveal .slides section.slide { height: auto; width: 960px; margin: 26px auto 10px; display: block; }
  .reveal .slides section.slide .body { margin: 0 auto; }
  .reveal .note { width: 960px; margin: 0 auto 6px; }
'''
style = style.replace('</style>', extra + '</style>')

secs = re.findall(r'<section data-title="([^"]*)">(.*?)<aside class="notes">(.*?)</aside>\s*</section>', r, re.S)
if not secs:
    sys.exit('section と <aside class="notes"> の組が見つからない')
out = []
for i, (title, body, note) in enumerate(secs, 1):
    m = re.match(r'<b>(スピーカーノート（[^）]*）)</b><br>(.*)', note, re.S)
    label, text = (m.group(1), m.group(2)) if m else ('スピーカーノート', note)
    out.append(f'<!-- ===== {i} ===== -->\n<section class="slide" data-title="{title}">{body.rstrip()}\n</section>\n'
               f'<div class="note">\n  <div class="nh"><span class="lbl">{label}</span></div>\n  <p class="talk">{text}</p>\n</div>\n')

title = re.search(r'<title>(.*?)</title>', r).group(1).replace('（発表用）', '')
html = (shell.replace('<!--STYLE-->', style).replace('<!--SLIDES-->', '\n'.join(out))
        .replace('<!--TITLE-->', title))
dst.write_text(html)
print(f'{dst}: {len(secs)} slides')
