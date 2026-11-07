import unittest
from install_iphone import choose_device, validate_backend, normalize_xcode_devices, validate_phone, process_id_from_events


class PhoneInstallTests(unittest.TestCase):
    def test_phone_backend_rejects_loopback_and_insecure_tailnet(self):
        for url in ['http://localhost:18787', 'http://127.0.0.1:18787',
                    'http://backend.demo.ts.net:8443', 'https://token@backend.demo.ts.net', 'http://8.8.8.8:18787', 'http://169.254.1.2:18787', 'http://172.32.0.1', 'http://10.01.2.3']:
            with self.assertRaises(ValueError): validate_backend(url)
        self.assertEqual(validate_backend('https://backend.demo.ts.net:8443/'), 'https://backend.demo.ts.net:8443')
        self.assertEqual(validate_backend('http://my-mac.local:18787'), 'http://my-mac.local:18787')
        for address in ['192.168.42.10', '10.0.0.1', '172.16.0.1', '172.31.255.254']:
            self.assertEqual(validate_backend('http://' + address + ':18787'), 'http://' + address + ':18787')

    def test_device_selection_requires_one_phone_or_an_explicit_choice(self):
        phone = {'identifier': 'phone-one', 'hardwareProperties': {'deviceType': 'iPhone'},
                 'deviceProperties': {'name': 'My phone'}}
        other = {'identifier': 'phone-two', 'hardwareProperties': {'deviceType': 'iPhone'}}
        self.assertEqual(choose_device([phone], None), phone)
        self.assertEqual(choose_device([phone, other], 'phone-one'), phone)
        for devices in [[], [phone, other], [{'hardwareProperties': {'deviceType': 'iPad'}}]]:
            with self.assertRaises(ValueError): choose_device(devices, None)

    def test_legacy_launch_verification_uses_the_actual_process_event(self):
        self.assertEqual(process_id_from_events('{"Event":"MountDeveloperImage"}{"Event":"GetPid","pid":549}'), 549)
        for text in ['success', '{"pid":549}', '{"Event":"GetPid","pid":0}',
                     '{"Event":"GetPid","pid":-1}', '{"Event":"GetPid","pid":true}']:
            self.assertIsNone(process_id_from_events(text))

    def test_legacy_phone_detection_and_compatibility_checks(self):
        device = {'identifier': 'legacy-phone', 'modelCode': 'iPhone13,2',
                  'platform': 'com.apple.platform.iphoneos', 'simulator': False,
                  'name': 'Test iPhone', 'available': True, 'operatingSystemVersion': '16.6.1 (20G81)'}
        phone = choose_device(normalize_xcode_devices([device, {**device, 'simulator': True}]), None)
        self.assertEqual(phone['hardwareProperties']['udid'], 'legacy-phone')
        self.assertTrue(validate_phone(phone))
        self.assertFalse(validate_phone(normalize_xcode_devices([{**device, 'operatingSystemVersion': '26.5'}])[0]))
        for version in ['15.8', '16.5.1', '']:
            with self.assertRaises(ValueError):
                validate_phone(normalize_xcode_devices([{**device, 'operatingSystemVersion': version}])[0])
        with self.assertRaisesRegex(ValueError, 'Developer Mode'):
            validate_phone(normalize_xcode_devices([{**device, 'available': False,
                'error': {'description': 'Enable Developer Mode in Settings'}}])[0])
        with self.assertRaisesRegex(ValueError, 'Xcode cannot use'):
            validate_phone(normalize_xcode_devices([{**device, 'available': False}])[0])


if __name__ == '__main__': unittest.main()
