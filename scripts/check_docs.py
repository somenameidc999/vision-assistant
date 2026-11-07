#!/usr/bin/env python3
"""Check repository-relative Markdown links; optionally check external URLs."""
import argparse
from pathlib import Path
import re
import urllib.request
import urllib.error

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(); parser.add_argument('--online', action='store_true'); args = parser.parse_args()
errors = []; urls = set(); count = 0
for directory in [root, root / 'docs', root / 'experiments', root / 'data', root / 'ios/VisionAssistant/Media']:
    paths = directory.glob('*.md') if directory == root else directory.rglob('*.md')
    for path in paths:
        for target in re.findall(r'\[[^\]]*\]\(([^\s)]+)(?:\s+[^)]*)?\)', path.read_text()):
            if target.startswith(('https://', 'http://')):
                urls.add(target); continue
            if target.startswith('#'): continue
            file = target.split('#')[0]
            if file and not (path.parent / file).exists(): errors.append(f'{path.relative_to(root)}: missing {file}')
            count += 1
if args.online:
    for url in sorted(urls):
        try:
            request = urllib.request.Request(url.split('#')[0], headers={'User-Agent': 'VisionAssistant-LinkCheck/0.1'})
            with urllib.request.urlopen(request, timeout=20) as response: response.read(1)
        except urllib.error.HTTPError as error:
            if error.code in (403, 429): print(f'ACCESS RESTRICTED (not verified): {url} [{error.code}]')
            else: errors.append(f'{url}: HTTP {error.code}')
        except Exception as error: errors.append(f'{url}: {type(error).__name__}')
if errors: raise SystemExit('\n'.join(errors))
print(f'PASS: {count} relative links; {len(urls)} external links ' + ('checked' if args.online else 'listed, not fetched'))
