#!/usr/bin/env python3
"""Exercise the running local backend with public fixtures, not a live microphone."""
import base64
from datetime import datetime, timedelta, timezone
import io
import json
from pathlib import Path
import time
import urllib.request
import uuid
import wave
from PIL import Image

root = Path(__file__).resolve().parents[1]
env = dict(line.split('=', 1) for line in (root / '.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
base = 'http://127.0.0.1:' + env.get('PORT', '18787')
def request(method, path, payload=None):
    body = json.dumps(payload).encode() if payload is not None else None
    headers = {'Authorization': 'Bearer ' + env['SESSION_TOKEN']}
    if body is not None: headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(base + path, data=body, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=35) as response:
        data = response.read()
        return json.loads(data) if data else None
def frames():
    source = str(uuid.uuid4())
    result = []
    for index, second in enumerate([10, 20]):
        image = Image.open(root / f'runs/fixtures/video-{second:03}.png').convert('RGB')
        data = io.BytesIO(); image.save(data, 'JPEG', quality=80)
        result.append({'id': str(uuid.uuid4()), 'sourceId': source, 'playbackSeconds': second,
            'capturedAt': (datetime.now(timezone.utc) - timedelta(seconds=5 if index == 0 else 0)).isoformat().replace('+00:00', 'Z'),
            'jpeg': base64.b64encode(data.getvalue()).decode()})
    return result
assert request('GET', '/health')['status'] == 'ok'
with wave.open(str(root / 'runs/feasibility/question.wav'), 'rb') as source:
    audio = io.BytesIO()
    with wave.open(audio, 'wb') as canonical:
        canonical.setparams(source.getparams())
        canonical.writeframes(source.readframes(source.getnframes()))
session = request('POST', '/v1/sessions')['sessionId']
records = []
try:
    for question in [ {'text': 'What is the main object in the photograph?'}, {'text': 'What color is it?'},
                      {'audio': {'format': 'wav', 'data': base64.b64encode(audio.getvalue()).decode()}} ]:
        start = time.monotonic()
        result = request('POST', f'/v1/sessions/{session}/turns', {'turnId': str(uuid.uuid4()), 'frames': frames(), **question})
        assert result['transcript'] and result['answer'] and len(result['frames']) == 2
        assert 'jpeg' not in result['frames'][0]
        ledger = json.loads((root / 'runs/budget.json').read_text())
        accounted = sum(entry.get('actual', entry['reserved']) for entry in ledger['entries'])
        assert abs(accounted - result['budget']['accountedUSD']) < 1e-9, 'Runtime and experiments must share one ledger.'
        records.append({'mode': 'audio' if 'audio' in question else 'text', 'roundTripMs': round((time.monotonic()-start)*1000), **result})
        print(json.dumps({'mode': records[-1]['mode'], 'roundTripMs': records[-1]['roundTripMs'],
                          'answer': result['answer'], 'usage': result['usage']}))
finally:
    request('DELETE', f'/v1/sessions/{session}')
(root / 'runs/backend-smoke.json').write_text(json.dumps({'source': 'public CC0 images and synthesized audio; no live microphone', 'results': records}, indent=2))
print('PASS: health, session creation, image question, contextual follow-up, audio plus images, session deletion')
