"""Offline OS adapter, NOT an alternate installer implementation.

Only command transport, host inventory and filesystem ownership boundaries are
replaced. Authentication, credential validation/hashing, config generation,
initramfs construction and the complete BootTransaction remain production code.
Unknown commands fail closed; this adapter can NEVER invoke reboot/update-grub.
"""
import base64
import datetime
import gzip
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import tempfile
from types import SimpleNamespace

FIXTURES = Path(__file__).parent / 'fixtures' / 'reinstall'
METADATA = json.loads((FIXTURES / 'metadata.json').read_text())


def require_tools():
    missing = [name for name in ('gpgv', 'ssh-keygen', 'openssl') if not shutil.which(name)]
    if missing:
        raise RuntimeError('Offline reinstall tests require installed executables on PATH: ' + ', '.join(missing))


def install_test_trust(module, scenario='ok'):
    """Replace only the trust anchor and wall clock, never verification logic."""
    encoded = base64.b64encode((FIXTURES / 'release-key.gpg').read_bytes()).decode()
    fingerprint = METADATA['fingerprint']
    if scenario == 'wrong-fingerprint':
        fingerprint = 'A' * 40
    if scenario == 'missing-key':
        encoded = base64.b64encode(b'not an OpenPGP certificate').decode()
    module.TRUST = {name: (fingerprint, encoded) for name in ('debian-12', 'debian-13', 'ubuntu')}
    class Clock(datetime.datetime):
        @classmethod
        def now(cls, tz=None):
            now = datetime.datetime.fromisoformat(METADATA['clock'])
            if scenario == 'expired-release':
                now += datetime.timedelta(days=90)
            return now.astimezone(tz) if tz else now.replace(tzinfo=None)
    module.datetime = SimpleNamespace(datetime=Clock, timezone=datetime.timezone, timedelta=datetime.timedelta)


def read_newc(data):
    result = {}
    offset = 0
    while offset + 110 <= len(data):
        header = data[offset:offset + 110]
        if header[:6] != b'070701':
            raise AssertionError('invalid newc header')
        values = [int(header[i:i + 8], 16) for i in range(6, 110, 8)]
        mode, length, namesize = values[1], values[6], values[11]
        start = offset + 110
        name = data[start:start + namesize - 1].decode()
        start = (start + namesize + 3) & ~3
        if name == 'TRAILER!!!':
            break
        result[name.lstrip('./')] = {'mode': stat.S_IMODE(mode), 'data': data[start:start + length].decode('utf-8', errors='replace')}
        offset = (start + length + 3) & ~3
    return result


def fixture_host_type(module):
    class FixtureHost(module.InstallerHost):
        def __init__(self, root, scenario='ok'):
            self.root = Path(root).resolve()
            self.scenario = scenario
            self.BOOT = self.root / 'boot'
            self.ENTRY = self.root / module.Host.ENTRY.relative_to('/')
            self.LOCKDIR = self.root / 'run/kejilion-reinstall'
            self.cfg = self.BOOT / 'grub/grub.cfg'
            self.env = self.BOOT / 'grub/grubenv'
            for path in (self.BOOT, self.ENTRY.parent, self.cfg.parent, self.LOCKDIR.parent):
                path.mkdir(parents=True, exist_ok=True)
            self.grub_header = '# original normal system default\nset default=0\n'
            self.normal_entry = "menuentry 'Normal system' --id 'normal' {\n echo 'normal fixture'\n}\n"
            self.cfg.write_text(self.grub_header + self.normal_entry)
            self.env.write_bytes(b'saved_entry=normal\n')
            self.original_cfg = self.cfg.read_bytes()
            self.original_env = self.env.read_bytes()
            self.commands = []
            self.downloads = []
            self.inventory_calls = 0
            self.rebooted = False
            self.work = None
            if scenario == 'stale-entry':
                self.ENTRY.write_text('# unrelated pre-existing entry\n')
            if scenario == 'stale-work':
                (self.BOOT / (self.WORK_PREFIX + 'old')).mkdir()
            if scenario == 'symlink-work':
                (self.root / 'unrelated').write_text('must not be modified')
                (self.BOOT / (self.WORK_PREFIX + 'symlink')).symlink_to(self.root / 'unrelated')

        def inside(self, path):
            path = Path(path)
            if not path.resolve().is_relative_to(self.root):
                raise AssertionError('fixture attempted to escape tempfile: ' + str(path))
            return path

        def _private_system_path(self, path, *, regular=False):
            path = self.inside(path)
            for part in (path, *path.parents):
                if part == self.root.parent:
                    break
                info = part.lstat()
                if stat.S_ISLNK(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o022:
                    raise module.HostError('Unsafe fixture system path')
            if regular and not path.is_file():
                raise module.HostError('Expected regular fixture system file')

        def _binary(self, name):
            if name in ('gpgv', 'ssh-keygen', 'openssl'):
                value = shutil.which(name)
                if not value:
                    raise RuntimeError('Missing test dependency: ' + name)
                return value
            if name in ('curl', 'xorriso', 'update-grub', 'grub-reboot', 'grub-editenv', 'grub-script-check', 'reboot'):
                return '/FIXTURE-NEVER-EXECUTED/' + name
            raise AssertionError('Unrecognized executable boundary: ' + name)

        def require(self, target):
            self.target = target
            if self.scenario == 'missing-dependency':
                raise module.HostError('Required trusted executable missing: xorriso')
            for name in ('gpgv', 'ssh-keygen', 'openssl'):
                self._binary(name)

        def inventory(self, ssh_ports=None):
            self.inventory_calls += 1
            value = json.loads((FIXTURES / 'inventory.json').read_text())
            value.update(grub_cfg=str(self.cfg), grub_env=str(self.env))
            scenario = self.scenario
            if scenario == 'dhcp':
                value['network']['mode'] = 'dhcp'
                value['network']['addresses'][0]['dynamic'] = True
            if scenario == 'multi-disk':
                value['disks'].append('/dev/vdb')
            if scenario == 'special-route':
                value['network']['routes'].append({'dst':'198.51.100.0/24','dev':'ens3','gateway':'192.0.2.1'})
            if scenario == 'ipv6':
                value['network']['addresses'] = [{'address':'2001:db8::10','prefix':64,'family':6}]
                value['network']['ssh_local_address'] = '2001:db8::10'
                value['network']['gateway6'] = 'fe80::1'
            if scenario == 'dns-stub':
                value['network']['dns'] = ['127.0.0.53']
            if scenario == 'uefi':
                value['firmware'] = 'uefi'
            if scenario in ('gpt-grub-boot', 'gpt-unknown-boot'):
                value['pttype'] = 'gpt'
                value['bios_embedding'] = False
            if scenario == 'gpt-grub-boot':
                value['boot_cmdline'] = 'BOOT_IMAGE=/boot/vmlinuz-fixture root=UUID=12345678-1234-1234-1234-123456789abc ro quiet'
            if scenario == 'gpt-unknown-boot':
                value['boot_cmdline'] = 'root=UUID=12345678-1234-1234-1234-123456789abc ro quiet'
            if scenario == 'low-memory':
                value['memory_bytes'] = 128 * 1024**2
            if scenario == 'changed-inventory' and self.inventory_calls > 1:
                value['disk_bytes'] += 4096
            if sorted(ssh_ports or []) != value['ssh_ports']:
                raise module.HostError('effective SSH ports mismatch')
            return value

        def prepare_work(self):
            self._no_stale_work()
            if self.scenario == 'prepare-failure':
                raise module.HostError('Cannot allocate private workspace')
            self.work = Path(tempfile.mkdtemp(prefix=self.WORK_PREFIX, dir=self.BOOT))
            os.chmod(self.work, 0o700)
            return self.work

        def password_hash(self, password):
            self.commands.append(['password-hash-stdin'])
            return super().password_hash(password)

        def transport_content(self, url):
            name = url.rsplit('/', 1)[-1]
            distro, version = self.target['distro'], self.target['version']
            if name == 'InRelease':
                path = FIXTURES / f'debian-{version}-InRelease'
            elif name == 'SHA256SUMS.gpg':
                path = FIXTURES / f'ubuntu-{version}-SHA256SUMS.gpg'
            elif name == 'SHA256SUMS':
                path = FIXTURES / ('debian-SHA256SUMS' if distro == 'debian' else f'ubuntu-{version}-SHA256SUMS')
            elif name in ('linux', 'vmlinuz'):
                path = FIXTURES / 'linux'
            elif name in ('initrd', 'initrd.gz'):
                path = FIXTURES / 'initrd'
            elif name.endswith('.iso'):
                path = FIXTURES / 'install.iso'
            else:
                raise AssertionError('unexpected fixture URL: ' + url)
            data = path.read_bytes()
            if self.scenario == 'bad-signature' and name in ('InRelease', 'SHA256SUMS.gpg'):
                if name == 'InRelease':
                    data = data.replace(b'Origin: Debian', b'Origin: EvilXX')
                else:
                    data = data[:-12] + bytes([data[-12] ^ 1]) + data[-11:]
            if self.scenario == 'bad-manifest' and name == 'SHA256SUMS':
                data += b'forged\n'
            if self.scenario == 'bad-artifact' and (name in ('linux', 'vmlinuz') or name.endswith('.iso')):
                data += b'tampered'
            return data

        def run(self, argv, *, timeout=30):
            self.commands.append(list(argv))
            name = argv[0]
            if name in ('gpgv', 'ssh-keygen'):
                for option in ('--homedir', '--keyring', '--output', '-f'):
                    if option in argv:
                        self.inside(argv[argv.index(option) + 1])
                if name == 'gpgv':
                    for value in argv[1:]:
                        if value.startswith('/'):
                            self.inside(value)
                result = subprocess.run([self._binary(name), *argv[1:]], stdin=subprocess.DEVNULL,
                                        capture_output=True, text=True, encoding='utf-8', errors='backslashreplace', timeout=timeout,
                                        env={'PATH': os.defpath, 'LC_ALL':'C', 'HOME':str(self.root)}, cwd=self.root)
                if result.returncode:
                    raise module.HostError(name + ' fixture verification failed')
                return result.stdout
            if name == 'curl':
                assert '--disable' in argv and '--location' not in argv and '-k' not in argv and '--insecure' not in argv
                assert argv[argv.index('--proto') + 1] == '=https'
                assert argv[argv.index('--proto-redir') + 1] == '=https'
                assert '--connect-timeout' in argv and '--max-time' in argv and '--max-filesize' in argv
                destination = self.inside(argv[argv.index('--output') + 1])
                url = argv[-1]
                self.downloads.append(url)
                if (self.scenario in ('certificate-failure', 'timeout')
                        or self.scenario == 'missing-signature' and url.endswith(('.gpg', '/InRelease'))):
                    raise module.HostError('Simulated transport failure: ' + self.scenario)
                destination.write_bytes(self.transport_content(url))
                if self.scenario in ('redirect', 'http-downgrade'):
                    return '302'
                if self.scenario == 'partial-download':
                    destination.write_bytes(b'partial')
                    raise module.HostError('Partial download interrupted')
                return '200'
            if name == 'xorriso':
                destination = self.inside(argv[-1])
                if self.scenario == 'extract-failure':
                    raise module.HostError('ISO extraction failed')
                destination.write_bytes((FIXTURES / ('linux' if argv[-2].endswith('vmlinuz') else 'initrd')).read_bytes())
                return ''
            if name == 'update-grub':
                text = self.ENTRY.read_text()
                marker = "KJ_REINSTALL_ENTRY"
                assert "exec cat <<'" + marker + "'\n" in text
                body = text.split("exec cat <<'" + marker + "'\n", 1)[1].rsplit(marker + '\n', 1)[0]
                # grub-mkconfig runs /etc/grub.d scripts in lexical filename
                # order. The original adapter's blind append hid a 09_* entry
                # becoming the persistent GRUB_DEFAULT=0 boot target.
                entries = [('10_linux', self.normal_entry), (self.ENTRY.name, body)]
                self.cfg.write_text(self.grub_header + ''.join(item[1] for item in sorted(entries)))
                if self.scenario == 'rollback-failure':
                    self.cfg.with_name(self.cfg.name + '.kejilion-restore').write_text('pre-existing collision')
                    raise module.HostError('Partial GRUB regeneration failed')
                if self.scenario == 'signal-interrupt':
                    os.kill(os.getpid(), signal.SIGTERM)
                if self.scenario == 'update-grub-failure':
                    raise module.HostError('Partial GRUB regeneration failed')
                return ''
            if name == 'grub-script-check':
                text = self.inside(argv[1]).read_text()
                assert text.count('{') == text.count('}')
                if self.scenario == 'grub-syntax-failure':
                    raise module.HostError('Generated GRUB syntax rejected')
                return ''
            if name == 'grub-reboot':
                self.env.write_text(self.original_env.decode() + 'next_entry=' + argv[1] + '\n')
                if self.scenario == 'grub-reboot-failure':
                    raise module.HostError('Arming one-shot boot failed')
                return ''
            if name == 'grub-editenv':
                return self.inside(argv[1]).read_text()
            if name == 'reboot':
                if self.scenario == 'reboot-failure':
                    raise module.HostError('Reboot request failed')
                self.rebooted = True
                return ''
            raise AssertionError('FORBIDDEN OS command: ' + repr(argv))

        def report(self, result):
            workspaces = list(self.BOOT.glob(self.WORK_PREFIX + '*'))
            payload = {}
            if self.work and (self.work / 'initrd').exists():
                data = (self.work / 'initrd').read_bytes()
                original = (FIXTURES / 'initrd').read_bytes()
                if data.startswith(original) and len(data) > len(original):
                    payload = read_newc(gzip.decompress(data[len(original):]))
            return {'result':result, 'commands':self.commands, 'downloads':self.downloads,
                    'rebooted':self.rebooted, 'entry_exists':os.path.lexists(self.ENTRY),
                    'entry_text':self.ENTRY.read_text() if self.ENTRY.is_file() else None,
                    'unrelated_text':(self.root / 'unrelated').read_text() if (self.root / 'unrelated').exists() else None,
                    'inventory_calls':self.inventory_calls,
                    'cfg_restored':self.cfg.read_bytes() == self.original_cfg,
                    'env_restored':self.env.read_bytes() == self.original_env,
                    'cfg':self.cfg.read_text(), 'env':self.env.read_text(),
                    'workspaces':[str(p) for p in workspaces], 'payload':payload,
                    'workspace_modes':[stat.S_IMODE(p.stat().st_mode) for p in workspaces]}
    return FixtureHost
