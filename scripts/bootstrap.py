#!/usr/bin/env python3
"""Create ignored local configuration. Never print credential values."""
import json
import os
from pathlib import Path
import secrets
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--client-only', action='store_true', help='Configure an iOS client without storing an OpenRouter credential.')
parser.add_argument('--backend-url', help='Local backend URL or private Tailscale HTTPS URL.')
args = parser.parse_args()

root = Path(__file__).resolve().parents[1]
path = root / '.env'
values = {}
if path.exists():
    for line in path.read_text().splitlines():
        if '=' in line and not line.startswith('#'):
            key, value = line.split('=', 1)
            values[key] = value.strip().strip('\"\'')
if not args.client_only and not values.get('OPENROUTER_API_KEY'):
    raise SystemExit('Set OPENROUTER_API_KEY in the ignored .env file before running bootstrap.')
if not args.client_only and not values.get('SESSION_TOKEN'):
    values['SESSION_TOKEN'] = secrets.token_hex(32)
values.setdefault('OPENROUTER_MODEL', 'google/gemini-3.8-flash')
values.setdefault('BUDGET_LIMIT_USD', '10')
values.setdefault('PORT', '18787')
if not args.client_only:
    path.write_text(''.join(f'{key}={value}\n' for key, value in values.items()))
    os.chmod(path, 0o600)
config = root / 'ios/VisionAssistant/LocalConfig.json'
config.parent.mkdir(parents=True, exist_ok=True)
backend_url = args.backend_url or values.get('BACKEND_URL') or 'http://localhost:' + values['PORT']
config.write_text(json.dumps({'backendURL': backend_url, 'sessionToken': values.get('SESSION_TOKEN', '')}, indent=2) + '\n')
os.chmod(config, 0o600)
print('Local client configuration created. Credential values hidden.' if args.client_only else 'Local backend and simulator configuration created. Credential values hidden.')
