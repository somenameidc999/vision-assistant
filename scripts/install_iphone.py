#!/usr/bin/env python3
"""Build, sign, install and launch the native demo on one paired iPhone.

Uses Xcode's local Apple Account. Never accepts Apple passwords or provider keys.
Device identifiers, provisioning output and configuration remain under ignored runs/.
"""
import argparse
import json
import ipaddress
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
MINIMUM_IOS = (16, 6)


def local_values():
    values = {}
    path = ROOT / '.env'
    if path.exists():
        for line in path.read_text().splitlines():
            if '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                if key in {'IPHONE_BACKEND_URL', 'IPHONE_DEVELOPMENT_TEAM'}:
                    values[key] = value.strip().strip('\"\'')
    return values


def validate_backend(value):
    url = urlparse(value)
    host = url.hostname or ''
    if url.username or url.password or url.query or url.fragment:
        raise ValueError('The backend URL must not contain credentials, a query, or a fragment.')
    if host in {'localhost', '127.0.0.1', '::1'}:
        raise ValueError('An iPhone cannot use the Mac backend at localhost. Use the private HTTPS or .local address.')
    try:
        address = ipaddress.IPv4Address(host)
        private_ipv4 = any(address in ipaddress.IPv4Network(network)
                           for network in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'))
    except ipaddress.AddressValueError:
        private_ipv4 = False
    if not ((url.scheme == 'https' and host.endswith('.ts.net'))
            or (url.scheme in {'http', 'https'} and (host.endswith('.local') or private_ipv4))):
        raise ValueError('Use a private .ts.net HTTPS address, the Mac’s .local address, or its private LAN IPv4 address.')
    return value.rstrip('/')


def choose_device(devices, requested):
    phones = [d for d in devices if d.get('hardwareProperties', {}).get('deviceType') == 'iPhone']
    if requested:
        phones = [d for d in phones if requested in {
            d.get('identifier'), d.get('hardwareProperties', {}).get('udid'),
            d.get('deviceProperties', {}).get('name')}]
    if not phones:
        raise ValueError('Xcode cannot see the selected iPhone. Connect by USB, unlock it, and tap Trust on the iPhone.')
    if len(phones) != 1:
        raise ValueError('More than one iPhone is visible. Select yours with --device <name-or-identifier>.')
    return phones[0]


def normalize_xcode_devices(devices):
    """xcdevice supports older iPhones that CoreDevice cannot manage."""
    return [{
        'identifier': device['identifier'],
        'hardwareProperties': {'deviceType': 'iPhone', 'udid': device['identifier']},
        'deviceProperties': {'name': device.get('name', ''),
                             'osVersionNumber': device.get('operatingSystemVersion', '').split(' ')[0]},
        'available': device.get('available', False),
        'error': device.get('error'),
    } for device in devices if not device.get('simulator')
       and device.get('platform') == 'com.apple.platform.iphoneos'
       and device.get('modelCode', '').startswith('iPhone')]


def validate_phone(phone):
    version = phone.get('deviceProperties', {}).get('osVersionNumber', '')
    if not re.fullmatch(r'\d+\.\d+(?:\.\d+)?', version):
        raise ValueError('Xcode could not read the iPhone’s iOS version. Unlock the phone and confirm Trust, then retry.')
    components = tuple(map(int, version.split('.')))
    if components[:2] < MINIMUM_IOS:
        raise ValueError('This build requires iOS 16.6 or later. Do not update or erase the phone automatically; review compatibility first.')
    error = phone.get('error') or {}
    if 'developer mode' in error.get('description', '').lower():
        raise ValueError('Enable Settings > Privacy & Security > Developer Mode on the iPhone, then confirm after its restart.')
    if not phone.get('available'):
        raise ValueError('Xcode cannot use the iPhone yet: ' + (error.get('description') or 'Unlock the phone and confirm Trust, then retry.'))
    return components[0] < 17


def process_id_from_events(text):
    """ios-deploy emits adjacent JSON events rather than one JSON document."""
    decoder = json.JSONDecoder()
    offset = 0
    while offset < len(text):
        start = text.find('{', offset)
        if start < 0:
            break
        try:
            event, consumed = decoder.raw_decode(text[start:])
        except ValueError:
            offset = start + 1
            continue
        offset = start + consumed
        if isinstance(event, dict) and event.get('Event') == 'GetPid':
            pid = event.get('pid')
            if isinstance(pid, int) and not isinstance(pid, bool) and pid > 0:
                return pid
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--start-session', action='store_true', help='Start the foreground session after launch in this Debug development build.')
    parser.add_argument('--device', help='Paired iPhone name or UDID; inferred only if exactly one phone is present.')
    parser.add_argument('--team', help='Apple development team ID. Otherwise uses the selected Xcode project team.')
    parser.add_argument('--backend-url', help='Private phone-reachable backend URL; defaults to IPHONE_BACKEND_URL in ignored .env.')
    args = parser.parse_args()
    values = local_values()
    backend = validate_backend(args.backend_url or values.get('IPHONE_BACKEND_URL', ''))
    runs = ROOT / 'runs'; runs.mkdir(exist_ok=True)
    task_env = dict(os.environ)
    if not task_env.get('DEVELOPER_DIR'):
        installed = Path('/Applications/Xcode-26.6.0.app/Contents/Developer')
        if installed.exists(): task_env['DEVELOPER_DIR'] = str(installed)

    def run(arguments, log=None):
        if log:
            with log.open('w') as stream:
                result = subprocess.run(arguments, cwd=ROOT, env=task_env, stdout=stream, stderr=subprocess.STDOUT)
            if result.returncode:
                raise ValueError(f'Command failed. Review {log.relative_to(ROOT)} for the exact error.')
        else:
            subprocess.run(arguments, cwd=ROOT, env=task_env, check=True)

    run(['xcodebuild', '-checkFirstLaunchStatus'])
    listing = runs / 'iphone-xcdevices.json'
    run(['xcrun', 'xcdevice', 'list', '--timeout', '8'], listing)
    phone = choose_device(normalize_xcode_devices(json.loads(listing.read_text())), args.device)
    legacy = validate_phone(phone)
    identifier = phone['identifier']
    build_device_id = phone['hardwareProperties']['udid']
    if legacy:
        if not shutil.which('ios-deploy'):
            raise ValueError('iOS 16 installation requires ios-deploy. Install it with brew install ios-deploy, then retry.')
    else:
        info = runs / 'iphone-device-details.json'
        run(['xcrun', 'devicectl', 'device', 'info', 'details', '--device', identifier, '--json-output', str(info)])
        properties = json.loads(info.read_text()).get('result', {}).get('deviceProperties', {})
        if properties.get('developerModeStatus') not in (None, 'enabled'):
            raise ValueError('Enable Settings > Privacy & Security > Developer Mode on the iPhone, then confirm after its restart.')

    team = args.team or values.get('IPHONE_DEVELOPMENT_TEAM')
    project = ROOT / 'ios/VisionAssistant.xcodeproj'
    if not project.exists(): run(['xcodegen', 'generate', '--spec', 'ios/project.yml'])
    if not team:
        settings = runs / 'iphone-build-settings.json'
        run(['xcodebuild', '-project', str(project), '-scheme', 'VisionAssistant',
             '-destination', 'generic/platform=iOS', '-showBuildSettings', '-json'], settings)
        # xcodebuild may prefix package resolution diagnostics before its JSON array.
        text = settings.read_text(); start = text.find('[\n')
        if start < 0: start = text.find('[')
        data, _ = json.JSONDecoder().raw_decode(text[start:])
        team = next((target['buildSettings'].get('DEVELOPMENT_TEAM') for target in data
                     if target.get('target') == 'VisionAssistant'), None)
    if not team or not re.fullmatch(r'[A-Za-z0-9]{10}', team):
        raise ValueError('Select your Personal Team in Xcode > VisionAssistant target > Signing & Capabilities, or pass --team <team-id>. Do not share Apple passwords.')

    run([sys.executable, 'scripts/bootstrap.py', '--client-only', '--backend-url', backend])
    bundle_id = 'local.personal.visionassistant.' + team.lower()
    build = runs / 'iPhoneBuild'
    run(['xcodebuild', '-project', str(project), '-scheme', 'VisionAssistant',
         '-destination', f'id={build_device_id}', '-derivedDataPath', str(build),
         '-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration',
         f'DEVELOPMENT_TEAM={team}', f'PRODUCT_BUNDLE_IDENTIFIER={bundle_id}',
         'CODE_SIGN_STYLE=Automatic', 'build'], runs / 'iphone-signed-build.log')
    app = build / 'Build/Products/Debug-iphoneos/VisionAssistant.app'
    run(['codesign', '--verify', '--deep', '--strict', str(app)])
    with (app / 'Info.plist').open('rb') as stream:
        bundle_id = plistlib.load(stream)['CFBundleIdentifier']
    if legacy:
        legacy_log = runs / 'iphone-legacy-install.log'
        run(['ios-deploy', '--id', identifier, '--bundle', str(app), '--timeout', '20'], legacy_log)
        if shutil.which('idevicedebug'):
            launch_args = ['--start-session'] if args.start_session else []
            run(['idevicedebug', '--udid', identifier, '--detach', '--', 'run', bundle_id, *launch_args], runs / 'iphone-legacy-launch.log')
            process_log = runs / 'iphone-process-check.log'
            run(['ios-deploy', '--id', identifier, '--get_pid', '--bundle_id', bundle_id,
                 '--json', '--timeout', '10'], process_log)
            if process_id_from_events(process_log.read_text()) is None:
                raise ValueError('The app installed, but its process is not running. Open Vision Assistant on the iPhone and review runs/iphone-legacy-launch.log.')
        else:
            print('Installed Vision Assistant. Open the app on the iPhone; automatic launch requires brew install libimobiledevice.')
            return
    else:
        run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', identifier,
             str(app), '--json-output', str(runs / 'iphone-install.json')])
        run(['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', identifier,
             '--json-output', str(runs / 'iphone-launch.json'), bundle_id, *(['--start-session'] if args.start_session else [])])
    print('Installed and launched Vision Assistant on the paired iPhone. Camera and live voice behavior still require a run on the phone.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
