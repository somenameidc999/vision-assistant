#!/usr/bin/env python3
"""Package current Git-visible sources, including authorized uncommitted work, without local secrets."""
import hashlib
import io
from pathlib import Path
import re
import subprocess
import tarfile

root = Path(__file__).resolve().parents[1]
output = root / 'runs/vision-assistant-demo.tar.gz'
output.parent.mkdir(exist_ok=True)
paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).split(b'\0')
secrets = []
env = root / '.env'
if env.exists():
    for line in env.read_text().splitlines():
        if line.startswith(('OPENROUTER_API_KEY=', 'SESSION_TOKEN=')):
            value = line.split('=', 1)[1].strip().strip('\"\'')
            if value: secrets.append(value.encode())
manifest = []
try:
    with tarfile.open(output, 'w:gz', dereference=False) as archive:
        for raw in sorted(set(paths)):
            if not raw: continue
            relative = Path(raw.decode())
            path = root / relative
            if path.is_symlink() or not path.is_file(): continue
            content = path.read_bytes()
            if any(secret in content for secret in secrets) or re.search(rb'sk-or-v1-[A-Za-z0-9]{20,}', content):
                raise SystemExit('Packaging stopped: credential-like content found in a source file. No values printed.')
            manifest.append(hashlib.sha256(content).hexdigest() + '  ' + str(relative))
            archive.add(path, arcname=str(Path('vision-assistant-demo') / relative), recursive=False)
        payload = ('\n'.join(manifest) + '\n').encode()
        info = tarfile.TarInfo('vision-assistant-demo/MANIFEST.sha256'); info.size = len(payload)
        archive.addfile(info, io.BytesIO(payload))
except BaseException:
    output.unlink(missing_ok=True)
    raise
print(f'Packaged {len(manifest)} source files at {output}. Local credentials, captures, build outputs, and dependencies are excluded.')
