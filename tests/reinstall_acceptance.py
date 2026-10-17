#!/usr/bin/env python3
"""#27 vertical acceptance: actual dd_xitong menu -> real Python business flow.

No network/root/real boot mutations. Only the host boundary is substituted;
release verification uses real gpgv and credentials use real ssh-keygen/OpenSSL.
"""
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
from reinstall_fixture import FIXTURES, fixture_host_type, install_test_trust, require_tools

ROOT = Path(__file__).resolve().parents[1]


def load_installer():
    spec = importlib.util.spec_from_file_location('secure_reinstall', ROOT / 'reinstall.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Console:
    def __init__(self, answers):
        self.answers = iter(answers)

    def ask(self, prompt):
        print(prompt)
        try:
            return next(self.answers)
        except StopIteration:
            raise EOFError

    secret = ask

    def say(self, message):
        print(message)


def driver():
    module = load_installer()
    distro, version = sys.argv[2:4]
    class ForbiddenHost:
        def __getattr__(self, name):
            raise AssertionError('unsupported version touched host: ' + name)
    if (distro, version) not in getattr(module, 'CATALOG', {}):
        return module.run(ForbiddenHost(), Console([]), distro, version, [2222])
    require_tools()
    scenario = os.environ.get('REINSTALL_SCENARIO', 'ok')
    install_test_trust(module, scenario)
    host = fixture_host_type(module)(os.environ['REINSTALL_TEST_ROOT'], scenario)
    key = (FIXTURES / 'login.pub').read_text().strip()
    if scenario == 'bad-key':
        key = 'ssh-ed25519 AAAA'
    elif scenario == 'missing-login-key':
        key = ''
    answers = ['operator', 'KEY', key, 'KEY']
    if scenario == 'unconfirmed-key':
        answers[-1] = 'no'
    if scenario in ('password', 'password-mismatch', 'short-password'):
        password = 'Fixture-only-password-8&unique'
        if scenario == 'short-password':
            password = 'short'
        answers = ['operator', 'PASSWORD', password,
                   password if scenario != 'password-mismatch' else password + 'wrong']
    if scenario not in ('eof',):
        answers.append({'cancel':'no', 'empty-confirm':'', 'invalid-confirm':'ERASE /dev/vdb'}.get(scenario, 'ERASE /dev/vda'))
    with host.lock() if scenario == 'concurrent' else contextlib.nullcontext():
        result = module.run(host, Console(answers), distro, version, [2222])
    report = Path(os.environ['REINSTALL_TEST_REPORT'])
    report.write_text(json.dumps(host.report(result), ensure_ascii=True, indent=2))
    os.chmod(report, 0o600)
    return result


class ReinstallMenuTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        require_tools()  # Missing dependency is a clear failure, never a success skip.

    def menu(self, choice, scenario='ok'):
        # Established seam: extract definitions to suppress main-menu startup.
        # We still invoke the actual production dd_xitong, not a duplicate menu.
        script = r'''
export KJ_TEST_NONINTERACTIVE=1
source <(awk '/^if \[ "\$#" -eq 0 \]; then$/ {exit} {print}' "$ROOT/kejilion.sh")
root_use() { :; }
kj_secure_reinstall() { python3 "$ROOT/tests/reinstall_acceptance.py" --driver "$1" "$2"; }
reboot() { echo UNSAFE_REBOOT; return 99; }
curl() { echo UNSAFE_DOWNLOAD; return 99; }
wget() { echo UNSAFE_DOWNLOAD; return 99; }
dd_xitong
'''
        with tempfile.TemporaryDirectory(prefix='reinstall-acceptance-') as temporary:
            root = Path(temporary) / 'host'
            root.mkdir(mode=0o700)
            report = Path(temporary) / 'result.json'
            env = dict(os.environ, ROOT=str(ROOT), REINSTALL_SCENARIO=scenario,
                       REINSTALL_TEST_ROOT=str(root), REINSTALL_TEST_REPORT=str(report))
            result = subprocess.run(['bash', '-c', script], input=f'{choice}\n0\n', text=True,
                                    capture_output=True, env=env, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('Traceback', result.stderr, result.stderr)
            self.assertNotIn('UNSAFE_', result.stdout + result.stderr)
            self.assertNotIn('Fixture-only-password-8&unique', result.stdout + result.stderr)
            data = json.loads(report.read_text()) if report.exists() else None
            if data:
                # Credentials must not escape in process argv or user-facing logs.
                commands = json.dumps(data['commands'])
                self.assertNotIn('Fixture-only-password-8&unique', commands)
                self.assertNotIn('$6$', commands + result.stdout + result.stderr)
            return result, data

    def assert_not_armed(self, data, *, preserved=False):
        self.assertIsNotNone(data, 'driver never reached the real supported business flow')
        self.assertNotEqual(data['result'], 0)
        self.assertFalse(data['rebooted'])
        if not preserved:
            self.assertFalse(data['entry_exists'])
            self.assertTrue(data['cfg_restored'])
            self.assertTrue(data['env_restored'])
            self.assertEqual(data['workspaces'], [])

    def test_unsupported_legacy_versions_stop_without_host_operations(self):
        for choice in (3, 4, 14):
            with self.subTest(choice=choice):
                result, data = self.menu(choice)
                self.assertIn('不可用', result.stdout)
                self.assertIsNone(data)

    def test_all_catalog_targets_commit_one_shot_only_after_confirmation(self):
        for choice, version in ((1, '13'), (2, '12'), (11, '26.04'), (12, '24.04'), (13, '22.04')):
            with self.subTest(version=version):
                result, data = self.menu(choice)
                self.assertIsNotNone(data)
                self.assertEqual(data['result'], 0, result.stdout + result.stderr)
                self.assertTrue(data['rebooted'])
                self.assertTrue(data['entry_exists'])
                names = [cmd[0] for cmd in data['commands']]
                self.assertEqual(names.count('reboot'), 1)
                self.assertEqual(names.count('update-grub'), 1)
                self.assertEqual(names.count('grub-reboot'), 1)
                self.assertLess(names.index('gpgv'), names.index('update-grub'))
                self.assertLess(names.index('update-grub'), names.index('grub-reboot'))
                self.assertLess(names.index('grub-reboot'), names.index('reboot'))
                self.assertIn('set default=0', data['cfg'])
                menu_entries = [line for line in data['cfg'].splitlines() if line.startswith('menuentry ')]
                self.assertIn("--id 'normal'", menu_entries[0], 'installer replaced the persistent default boot entry')
                self.assertIn('saved_entry=normal', data['env'])
                self.assertIn('next_entry=kejilion-install-', data['env'])
                self.assertEqual(data['workspace_modes'], [0o700])
                self.assertIn('ssh -p 2222 operator@192.0.2.10', result.stdout)
                self.assertIn('备份', result.stdout)
                self.assertIn('控制台', result.stdout)
                self.assertNotIn('已验证远端登录成功', result.stdout)

    def test_cancel_empty_invalid_and_eof_never_change_boot(self):
        for scenario in ('cancel', 'empty-confirm', 'invalid-confirm', 'eof', 'unconfirmed-key'):
            with self.subTest(scenario=scenario):
                _, data = self.menu(12, scenario)
                self.assert_not_armed(data)
                self.assertNotIn('update-grub', [cmd[0] for cmd in data['commands']])

    def test_authentication_and_transport_fail_closed(self):
        for scenario in ('certificate-failure', 'timeout', 'redirect', 'http-downgrade',
                         'partial-download', 'missing-signature', 'missing-key',
                         'wrong-fingerprint', 'bad-signature', 'bad-manifest', 'bad-artifact'):
            with self.subTest(scenario=scenario):
                _, data = self.menu(12, scenario)
                self.assert_not_armed(data)
                self.assertNotIn('update-grub', [cmd[0] for cmd in data['commands']])
                names = [cmd[0] for cmd in data['commands']]
                self.assertNotIn('reboot', names)
                self.assertNotIn('xorriso', names)
                if scenario in ('missing-key', 'wrong-fingerprint', 'bad-signature', 'bad-manifest', 'bad-artifact'):
                    self.assertIn('gpgv', names)
                if scenario == 'missing-signature':
                    self.assertTrue(data['downloads'][-1].endswith('SHA256SUMS.gpg'))
                if scenario == 'bad-artifact':
                    self.assertTrue(data['downloads'][-1].endswith('.iso'))

    def test_debian_signed_release_chain_and_replay_window(self):
        for scenario in ('bad-signature', 'bad-manifest', 'bad-artifact', 'expired-release'):
            with self.subTest(scenario=scenario):
                _, data = self.menu(2, scenario)
                self.assert_not_armed(data)

    def test_unusable_hosts_stop_before_downloading(self):
        for scenario in ('multi-disk', 'special-route', 'ipv6', 'dns-stub', 'uefi', 'low-memory', 'missing-dependency'):
            with self.subTest(scenario=scenario):
                _, data = self.menu(12, scenario)
                self.assert_not_armed(data)
                self.assertEqual(data['downloads'], [])

    def test_missing_invalid_or_unconfirmed_credentials_do_not_arm_boot(self):
        for scenario in ('bad-key', 'missing-login-key', 'password-mismatch', 'short-password'):
            with self.subTest(scenario=scenario):
                _, data = self.menu(12, scenario)
                self.assert_not_armed(data)
                self.assertEqual(data['downloads'], [])

    def test_preparation_changed_host_and_transaction_failures_restore_exact_boot_files(self):
        for scenario in ('prepare-failure', 'extract-failure', 'changed-inventory',
                         'update-grub-failure', 'grub-syntax-failure',
                         'grub-reboot-failure', 'reboot-failure', 'signal-interrupt'):
            with self.subTest(scenario=scenario):
                _, data = self.menu(12, scenario)
                self.assert_not_armed(data)
                names = [cmd[0] for cmd in data['commands']]
                reached = {'extract-failure':'xorriso', 'update-grub-failure':'update-grub',
                           'grub-syntax-failure':'grub-script-check', 'grub-reboot-failure':'grub-reboot',
                           'reboot-failure':'reboot', 'signal-interrupt':'update-grub'}.get(scenario)
                if reached:
                    self.assertEqual(names.count(reached), 1, 'failure injection was not reached')
                if scenario == 'changed-inventory':
                    self.assertEqual(data['inventory_calls'], 2)

    def test_rollback_failure_warns_and_preserves_private_backups(self):
        result, data = self.menu(12, 'rollback-failure')
        self.assert_not_armed(data, preserved=True)
        self.assertIn('撤销', result.stdout)
        self.assertIn('不要重启', result.stdout)
        self.assertIn('grub.cfg.before', result.stdout)
        self.assertTrue(data['workspaces'])
        self.assertEqual(data['workspace_modes'], [0o700])
        self.assertNotIn('reboot', [cmd[0] for cmd in data['commands']])

    def test_unknown_existing_entry_and_workspace_are_not_overwritten(self):
        for scenario in ('stale-entry', 'stale-work', 'symlink-work', 'concurrent'):
            with self.subTest(scenario=scenario):
                _, data = self.menu(12, scenario)
                self.assert_not_armed(data, preserved=True)
                self.assertTrue(data['cfg_restored'])
                self.assertTrue(data['env_restored'])
                self.assertNotIn('update-grub', [cmd[0] for cmd in data['commands']])
                if scenario == 'stale-entry':
                    self.assertEqual(data['entry_text'], '# unrelated pre-existing entry\n')
                if scenario in ('stale-work', 'symlink-work'):
                    self.assertEqual(len(data['workspaces']), 1)
                if scenario == 'symlink-work':
                    self.assertEqual(data['unrelated_text'], 'must not be modified')
                if scenario == 'concurrent':
                    self.assertEqual(data['inventory_calls'], 0)

    def test_ubuntu_payload_has_runnable_hook_matching_network_login_and_firewall(self):
        for scenario in ('ok', 'dhcp', 'password'):
            with self.subTest(scenario=scenario):
                result, data = self.menu(12, scenario)
                self.assertIsNotNone(data)
                self.assertEqual(data['result'], 0, result.stdout)
                files = data['payload']
                auto = json.loads(files['autoinstall.yaml']['data'])
                hook = files['scripts/casper-bottom/99-reinstall-config']
                self.assertEqual(hook['mode'], 0o755)
                runtime_hooks = [item for name, item in files.items()
                                 if name.startswith('scripts/casper-bottom/')
                                 and '/root/autoinstall.yaml' in item['data']]
                self.assertTrue(runtime_hooks, 'no native hook copies autoinstall into the live root')
                self.assertTrue(all(item['mode'] == 0o755 for item in runtime_hooks))
                ethernet = next(iter(auto['network']['ethernets'].values()))
                self.assertEqual(ethernet['match']['macaddress'], '52:54:00:12:34:56')
                self.assertEqual(ethernet['dhcp4'], scenario == 'dhcp')
                if scenario != 'dhcp':
                    self.assertEqual(ethernet['addresses'], ['192.0.2.10/24'])
                    self.assertEqual(ethernet['nameservers']['addresses'], ['9.9.9.9'])
                self.assertFalse(auto['refresh-installer']['update'])
                self.assertFalse(auto['apt']['geoip'])
                self.assertEqual(auto['identity']['username'], 'operator')
                self.assertEqual(auto['ssh']['allow-pw'], scenario == 'password')
                sshd = files['reinstall/sshd_config']['data']
                self.assertIn('Port 2222\n', sshd)
                self.assertNotIn('Port 22\n', sshd)
                self.assertIn('PermitRootLogin no', sshd)
                self.assertIn('PasswordAuthentication ' + ('yes' if scenario == 'password' else 'no'), sshd)
                target = files['reinstall/target.sh']['data']
                self.assertIn('ufw allow', target)
                self.assertNotIn('ufw disable', target)
                self.assertNotIn('iptables -F', target)
                self.assertIn('toram', data['cfg'])
                self.assertIn('ipv6.disable=1', data['cfg'])
                self.assertIn('BOOTIF=01-52-54-00-12-34-56', data['cfg'])
                self.assertIn('ip=:::::eth0:dhcp' if scenario == 'dhcp'
                              else 'ip=192.0.2.10::192.0.2.1:255.255.255.0:', data['cfg'])
                self.assertNotIn('Fixture-only-password-8&unique', json.dumps(files))

    def test_debian_payload_carries_local_preseed_and_https_only_runtime(self):
        result, data = self.menu(2)
        self.assertIsNotNone(data)
        self.assertEqual(data['result'], 0, result.stdout)
        files = data['payload']
        preseed = files['preseed.cfg']['data']
        self.assertIn('d-i partman-auto/disk string /dev/vda', preseed)
        self.assertIn('d-i passwd/root-login boolean false', preseed)
        self.assertIn('d-i netcfg/get_ipaddress string 192.0.2.10', preseed)
        self.assertIn('d-i debian-installer/allow_unauthenticated boolean false', preseed)
        self.assertNotIn('preseed/url=', data['cfg'])
        for item in files.values():
            self.assertNotIn('http://', item['data'])
        self.assertIn('preseed/file=/preseed.cfg', data['cfg'])
        self.assertIn('ip=192.0.2.10::192.0.2.1:255.255.255.0:', data['cfg'])
        self.assertIn('ipv6.disable=1', data['cfg'])
        # Native Trixie initramfs has bin -> usr/bin and its shell lives only
        # under usr/bin. A newc directory named bin would destroy /bin/sh.
        self.assertNotIn('bin', files, 'overlay replaces the native merged-/usr bin symlink')
        self.assertNotIn('bin/wget', files)
        self.assertIn('usr/bin/wget.real', files)
        self.assertEqual(files['usr/bin/wget.real']['mode'], 0o755)
        self.assertIn('reinstall-runtime/native-archive.gpg', files)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--driver':
        sys.exit(driver())
    unittest.main()
