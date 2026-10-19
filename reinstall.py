#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Original repository-controlled installer policy for issue #27.
# Native Debian/Ubuntu installers retain their own distribution licenses.
# No bin456789/leitbogioro implementation code is vendored here.
import sys

"""Production, fail-closed host boundary for the standalone reinstall module.

Integration API (stdlib only):
    Host().inventory(ssh_ports: list[int] | None = None) -> dict
        READ ONLY. Caller may pass the JSON-decoded result of get_ssh_ports;
        its fallback is NOT trusted: compare it to successful sshd -T and ss.
        Raises HostError rather than returning guessed/partial facts.
    Host().prepare_work() -> pathlib.Path
        AFTER inventory, before material preparation. Creates a fresh 0700
        /boot/kejilion-reinstall.<random> directory; never adopts old state.
    Host().run(argv: list[str], *, timeout: int = 30) -> str
        OS-command seam. Explicit trusted executable paths and clean environment.

No GRUB transaction is implemented here. Parent owns final confirmation,
serialization (hold one root-private flock across inventory through reboot),
material authentication, stage_boot, signal handling and rollback. In particular,
prepare_work does NOT install an entry, change grubenv, or arm a reboot.
Do not call this fragment as a separate privileged script: import/concatenate it
into reinstall.py; no environment-controlled scripts or shell evaluation.
HostError should be caught by the parent and displayed without a traceback.
"""

import ipaddress
import json
import os
from pathlib import Path
import platform
import re
import shlex
import stat
import subprocess
import tempfile


class HostError(RuntimeError):
    pass


class Host:
    BOOT = Path('/boot')
    WORK_PREFIX = 'kejilion-reinstall.'
    # Append after the normal Linux/custom entries: GRUB_DEFAULT=0 must keep
    # selecting the original OS once next_entry has been consumed.
    ENTRY = Path('/etc/grub.d/99_kejilion_reinstall')
    TRUSTED_BIN_DIRS = ('/usr/sbin', '/usr/bin', '/sbin', '/bin')

    def _binary(self, name):
        if '/' in name:
            raise HostError('Command names must not contain a path')
        for directory in self.TRUSTED_BIN_DIRS:
            path = Path(directory, name)
            try:
                resolved = path.resolve(strict=True)
                info = resolved.stat()
            except FileNotFoundError:
                continue
            if (stat.S_ISREG(info.st_mode) and info.st_uid == 0
                    and not info.st_mode & 0o022 and os.access(resolved, os.X_OK)):
                # Validate the resolved binary, but preserve the invoked name.
                # Multicall executables (notably reboot -> systemctl) dispatch
                # by argv[0]; replacing it with the target silently changes work.
                return str(path)
        raise HostError('Required trusted system executable missing: ' + name)

    def run(self, argv, *, timeout=30):
        executable = self._binary(argv[0])
        try:
            result = subprocess.run(
                [executable, *argv[1:]], stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, encoding='utf-8', errors='backslashreplace', timeout=timeout,
                check=False, shell=False, cwd='/',
                env={'PATH': ':'.join(self.TRUSTED_BIN_DIRS), 'LC_ALL': 'C',
                     'LANG': 'C', 'HOME': '/root'},
            )
        except (OSError, subprocess.TimeoutExpired, UnicodeError) as exc:
            raise HostError('System query failed: ' + argv[0]) from exc
        if result.returncode != 0:
            # Do not propagate daemon configuration or command output as logs.
            raise HostError(f'{argv[0]} failed (exit {result.returncode}); inspect it locally')
        if len(result.stdout) > 8 * 1024 * 1024:
            raise HostError('Unexpectedly large system query: ' + argv[0])
        return result.stdout

    def _json(self, argv, kind=list):
        try:
            value = json.loads(self.run(argv))
        except (ValueError, TypeError) as exc:
            raise HostError('Invalid JSON from ' + argv[0]) from exc
        if not isinstance(value, kind):
            raise HostError('Unexpected JSON structure from ' + argv[0])
        return value

    @staticmethod
    def _private_system_path(path, *, regular=False):
        """Require root ownership and no symlink in a mutable system path."""
        path = Path(path)
        for part in (path, *path.parents):
            info = part.lstat()
            if stat.S_ISLNK(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
                raise HostError('Unsafe ownership, mode or symlink: ' + str(part))
        if regular and not stat.S_ISREG(path.lstat().st_mode):
            raise HostError('Expected regular file: ' + str(path))

    @staticmethod
    def _os_release():
        # os-release is data, NOT a shell script to source.
        data = {}
        for line in Path('/etc/os-release').read_text().splitlines():
            if not line or line.startswith('#'):
                continue
            key, sep, value = line.partition('=')
            if not sep or not re.fullmatch(r'[A-Z_][A-Z_0-9]*', key):
                raise HostError('Malformed os-release')
            try:
                words = shlex.split(value, comments=False, posix=True)
            except ValueError as exc:
                raise HostError('Malformed os-release value') from exc
            if len(words) > 1 or key in data:
                raise HostError('Ambiguous os-release value')
            data[key] = words[0] if words else ''
        if data.get('ID') not in ('debian', 'ubuntu') or not data.get('VERSION_ID'):
            raise HostError('Only Debian/Ubuntu source systems are supported')
        return data

    def _mount(self, target):
        data = self._json(['findmnt', '-J', '-T', target, '-o',
                           'SOURCE,TARGET,FSTYPE,OPTIONS,MAJ:MIN'], dict)
        entries = data.get('filesystems', [])
        if len(entries) != 1:
            raise HostError('Cannot identify mount for ' + target)
        return entries[0]

    def _storage(self):
        root = self._mount('/')
        boot = self._mount('/boot')
        if (root.get('target') != '/' or root.get('fstype') != 'ext4'
                or boot.get('fstype') != 'ext4'
                or root.get('maj:min') != boot.get('maj:min')
                or boot.get('target') != '/'):
            raise HostError('Only one ext4 root filesystem with /boot inside it is supported')
        if 'rw' not in root.get('options', '').split(','):
            raise HostError('Root filesystem is not writable')
        for flag in ('bind', 'rbind'):
            if flag in root.get('options', '').split(','):
                raise HostError('Bind-mounted root is not supported')
        data = self._json(['lsblk', '-J', '-b', '-o',
                          'NAME,PATH,TYPE,SIZE,FSTYPE,MOUNTPOINTS,PKNAME,PTTYPE,PARTTYPE,UUID,RO,RM'], dict)
        devices = []
        def visit(items):
            for item in items:
                devices.append(item)
                visit(item.get('children', []))
        visit(data.get('blockdevices', []))
        disks = [d for d in devices if d.get('type') == 'disk']
        if len(disks) != 1:
            raise HostError('Exactly one physical/virtual disk is required; multi-disk is unsupported')
        disk = disks[0]
        if disk.get('ro') or disk.get('rm') or disk.get('pttype') not in ('dos', 'gpt'):
            raise HostError('Disk must be writable, non-removable, partitioned MBR/GPT')
        if any(d.get('type') not in ('disk', 'part', 'rom') for d in devices):
            raise HostError('RAID, LVM, encryption, loop and other mapped devices are unsupported')
        source = root.get('source', '')
        if not re.fullmatch(r'/dev/[A-Za-z0-9._/-]+', source):
            raise HostError('Root must be a plain block partition, not overlay/subvolume')
        root_device = os.path.realpath(source)
        parts = [d for d in devices if os.path.realpath(d.get('path', '')) == root_device]
        if len(parts) != 1 or parts[0].get('type') != 'part':
            raise HostError('Root is not an unambiguous disk partition')
        part = parts[0]
        disk_path = disk.get('path', '')
        if (not re.fullmatch(r'/dev/[A-Za-z0-9._/-]+', disk_path)
                or part.get('pkname') not in (disk.get('name'), disk_path)
                or part.get('fstype') != 'ext4' or not part.get('uuid') or part.get('ro')):
            raise HostError('Root partition is not a writable ext4 child of the selected disk')
        # Allow ONLY root + optional swap + optional BIOS embedding partition.
        for device in devices:
            if device in (disk, part) or device.get('type') == 'rom':
                continue
            mounts = [m for m in device.get('mountpoints', []) if m]
            bios = str(device.get('parttype', '')).lower() in (
                '21686148-6449-6e6f-744e-656564454649', '0xef02')
            if (device.get('type') != 'part'
                    or device.get('pkname') not in (disk.get('name'), disk_path)
                    or not ((device.get('fstype') == 'swap' and all(m == '[SWAP]' for m in mounts))
                            or (bios and not mounts and not device.get('fstype')))):
                raise HostError('Only root, optional swap and optional BIOS-GRUB partition are supported')
        bios_embedding = any(
            str(device.get('parttype', '')).lower() in (
                '21686148-6449-6e6f-744e-656564454649', '0xef02')
            for device in devices)
        # No bootloader decision here: a GPT disk may legitimately lack the
        # embedding partition (core.img kept in the GPT gap). validate_inventory
        # refuses that layout unless the running kernel proves disk-GRUB boot.
        return {'disk': disk_path, 'root_disk': disk_path, 'disks': [disk_path],
                'disk_bytes': int(disk['size']), 'root_partition': root_device,
                'root_fstype': 'ext4', 'root_uuid': part['uuid'], 'simple_layout': True,
                'pttype': disk.get('pttype'), 'bios_embedding': bios_embedding}

    def _grub(self, storage):
        for directory in ('/boot', '/boot/grub', '/etc/grub.d'):
            self._private_system_path(directory)
        cfg = Path('/boot/grub/grub.cfg')
        env = Path('/boot/grub/grubenv')
        self._private_system_path(cfg, regular=True)
        self._private_system_path(env, regular=True)
        self._private_system_path('/etc/default/grub', regular=True)
        if not Path('/boot/grub/i386-pc').is_dir():
            raise HostError('Existing BIOS GRUB (i386-pc) installation is required')
        for command in ('update-grub', 'grub-reboot', 'grub-editenv', 'grub-script-check', 'reboot'):
            self._binary(command)
        if (os.path.realpath(self.run(['grub-probe', '--target=device', '/boot']).strip())
                != storage['root_partition']
                or self.run(['grub-probe', '--target=fs', '/boot']).strip() != 'ext2'
                or self.run(['grub-probe', '--target=abstraction', '/boot']).strip()
                or self.run(['grub-probe', '--target=fs_uuid', '/boot']).strip() != storage['root_uuid']):
            raise HostError('GRUB cannot directly read the root ext4 filesystem')
        text = cfg.read_text()
        if not all(token in text for token in ('load_env', 'next_entry', 'save_env next_entry')):
            raise HostError('Current GRUB config lacks supported one-shot boot handling')
        self.run(['grub-script-check', str(cfg)])
        values = {}
        for line in self.run(['grub-editenv', str(env), 'list']).splitlines():
            key, sep, value = line.partition('=')
            if not sep or key in values:
                raise HostError('Invalid GRUB environment')
            values[key] = value
        if values.get('next_entry') or values.get('prev_saved_entry'):
            raise HostError('An existing one-shot GRUB boot is armed; clear it manually before reinstall')
        self._no_stale_work()
        # Boolean keeps the parent's simple validation straightforward; details
        # are additional facts, not a guarantee that BIOS firmware booted GRUB.
        return {'grub': True, 'grub_cfg': str(cfg), 'grub_env': str(env),
                'grub_saved_entry': values.get('saved_entry')}

    def _no_stale_work(self):
        stale = list(self.BOOT.glob(self.WORK_PREFIX + '*'))
        active = getattr(self, 'active_work', None)
        if active in stale:
            self._private_system_path(active)
            if not active.is_dir() or stat.S_IMODE(active.stat().st_mode) != 0o700:
                raise HostError('Current workspace permissions changed')
            stale.remove(active)
        legacy_entry = self.ENTRY.with_name('09_kejilion_reinstall')
        if os.path.lexists(self.ENTRY) or os.path.lexists(legacy_entry) or stale:
            raise HostError(
                'Stale reinstall state exists. Do NOT reboot. Inspect '
                '/etc/grub.d/{09,99}_kejilion_reinstall and /boot/kejilion-reinstall.* '
                'from the console; restore the private grub.cfg/grubenv backups '
                'if a previous transaction created them, then remove ONLY that '
                'transaction\'s entry/work directory. Do not delete unknown state automatically.')

    @staticmethod
    def _address(value):
        try:
            return ipaddress.ip_address(value)
        except ValueError as exc:
            raise HostError('Invalid IP address in host configuration') from exc

    def _dns(self, interface):
        candidates = []
        for line in Path('/etc/resolv.conf').read_text().splitlines():
            fields = line.split('#', 1)[0].split(';', 1)[0].split()
            if fields and fields[0] == 'nameserver':
                if len(fields) != 2:
                    raise HostError('Invalid nameserver directive')
                candidates.append(fields[1])
        def usable(values):
            result = []
            for value in values:
                # Scoped link-local DNS cannot be preserved without richer config.
                if '%' in value:
                    continue
                address = self._address(value)
                if (address.is_loopback or address.is_link_local or address.is_unspecified
                        or address.is_multicast):
                    continue
                text = str(address)
                if text not in result:
                    result.append(text)
            return result
        direct = usable(candidates)
        if direct:
            return direct
        # A loopback stub is not an upstream DNS server. Query resolved without
        # a pager/terminal and collect both this link and global upstreams.
        upstreams = []
        for argv in (['resolvectl', 'dns', interface], ['resolvectl', 'dns']):
            try:
                output = self.run(argv)
            except HostError:
                continue
            for line in output.splitlines():
                prefix, sep, values = line.partition(':')
                if sep and (prefix == 'Global' or (
                        prefix.startswith('Link ') and prefix.endswith('(' + interface + ')'))):
                    upstreams.extend(values.split())
        direct = usable(upstreams)
        if not direct:
            raise HostError('Only local DNS stubs/no effective upstream DNS found; explicit verified DNS required')
        return direct

    def _network(self):
        links = self._json(['ip', '-j', '-d', 'link', 'show'])
        addr_rows = self._json(['ip', '-j', 'addr', 'show'])
        routes = []
        rules = []
        for flag, family in (('-4', 'inet'), ('-6', 'inet6')):
            for route in self._json(['ip', '-j', flag, 'route', 'show', 'table', 'all']):
                route = dict(route)
                route['family'] = family
                routes.append(route)
            for rule in self._json(['ip', '-j', flag, 'rule', 'show']):
                rule = dict(rule)
                rule['family'] = family
                rules.append(rule)
        allowed_tables = {'local', 'main', 'default', '255', '254', '253'}
        for rule in rules:
            if (str(rule.get('table')) not in allowed_tables or rule.get('src', 'all') != 'all'
                    or set(rule) - {'priority', 'src', 'table', 'family', 'protocol'}):
                raise HostError('Policy/source/special routing rules are unsupported')
            expected = {'local': 0, '255': 0, 'main': 32766, '254': 32766,
                        'default': 32767, '253': 32767}[str(rule['table'])]
            if rule.get('priority') != expected:
                raise HostError('Nonstandard routing rule priority is unsupported')
        interfaces = []
        active = []
        for link in links:
            name = link.get('ifname', '')
            if name == 'lo':
                continue
            if not re.fullmatch(r'[A-Za-z0-9_.-]{1,15}', name):
                raise HostError('Unsupported interface name')
            rows = [r for r in addr_rows if r.get('ifindex') == link.get('ifindex')]
            if len(rows) != 1:
                raise HostError('Interface/address inventory changed; retry')
            addresses = []
            for address in rows[0].get('addr_info', []):
                if address.get('family') not in ('inet', 'inet6'):
                    raise HostError('Unsupported address family')
                ip = self._address(address.get('local', ''))
                if ip.is_loopback or ip.is_link_local:
                    continue
                flags = address.get('flags', [])
                if any(address.get(k) or k in flags for k in ('tentative', 'dadfailed', 'deprecated', 'temporary', 'secondary')):
                    raise HostError('Temporary/secondary/unusable addresses are unsupported')
                if address.get('peer') or address.get('scope') != 'global' or ip.is_multicast or ip.is_unspecified:
                    raise HostError('Non-global or point-to-point addresses are unsupported')
                prefix = address.get('prefixlen')
                if type(prefix) is not int or not 0 <= prefix <= ip.max_prefixlen:
                    raise HostError('Invalid address prefix')
                addresses.append({'address': str(ip), 'prefix': prefix,
                                  'family': address['family'],
                                  'dynamic': bool(address.get('dynamic') or 'dynamic' in flags)})
            item = {'name': name, 'mac': link.get('address'), 'addresses': addresses,
                    'flags': link.get('flags', []), 'link_type': link.get('link_type'),
                    'kind': link.get('linkinfo', {}).get('info_kind')}
            interfaces.append(item)
            if addresses or 'UP' in item['flags']:
                active.append((link, item))
        if len(active) != 1:
            raise HostError('Exactly one active non-loopback network interface is supported')
        link, selected = active[0]
        name = selected['name']
        if (selected['link_type'] != 'ether' or selected['kind']
                or link.get('master') or link.get('link') or link.get('link_index')
                or 'UP' not in selected['flags'] or not selected['addresses']
                or not re.fullmatch(r'(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}', selected['mac'] or '')
                or selected['mac'].lower() == '00:00:00:00:00:00'
                or int(selected['mac'].split(':')[0], 16) & 1):
            raise HostError('Only a directly attached Ethernet interface is supported (no VLAN/bond/bridge/tunnel)')
        addresses = selected['addresses']
        for family in {address['family'] for address in addresses}:
            tables = {str(r.get('table')) for r in rules if r['family'] == family}
            if not (tables & {'local', '255'} and tables & {'main', '254'}):
                raise HostError('Management network lacks normal local/main routing rules')
        if any(sum(a['family'] == family for a in addresses) > 1 for family in ('inet', 'inet6')):
            raise HostError('Only one stable address per IP family is supported')
        gateways = {'inet': None, 'inet6': None}
        main_routes = []
        networks = [ipaddress.ip_network(f"{a['address']}/{a['prefix']}", strict=False) for a in addresses]
        for route in routes:
            table = str(route.get('table', 'main'))
            if table in ('local', '255'):
                continue
            if table not in ('main', '254'):
                raise HostError('Non-main routing tables are unsupported')
            if (route.get('dev') != name or route.get('type', 'unicast') != 'unicast'
                    or route.get('nexthops') or route.get('multipath') or route.get('encap')
                    or route.get('nhid') or route.get('via') or route.get('flags')):
                raise HostError('Multipath, special or other-interface routes are unsupported')
            dst = route.get('dst', 'default')
            family = route['family']
            if dst == 'default':
                if gateways[family] is not None or not route.get('gateway'):
                    raise HostError('Exactly one gateway per configured family is supported')
                gateway = self._address(route['gateway'])
                if (gateway.version != (4 if family == 'inet' else 6)
                        or gateway.is_unspecified or gateway.is_multicast or gateway.is_loopback):
                    raise HostError('Invalid default gateway')
                if not gateway.is_link_local and not any(gateway in net for net in networks):
                    raise HostError('Off-subnet gateway requires unsupported special routes')
                gateways[family] = str(gateway)
            else:
                try:
                    network = ipaddress.ip_network(dst, strict=False)
                except ValueError as exc:
                    raise HostError('Invalid route destination') from exc
                if not ((network in networks and not route.get('gateway'))
                        or (network.version == 6 and network.is_link_local and not route.get('gateway'))):
                    raise HostError('Additional static/host/special routes are unsupported')
            main_routes.append(route)
        if not any(gateways.values()):
            raise HostError('No unambiguous default gateway found')
        raw_ssh = os.environ.get('SSH_CONNECTION', '').split()
        if len(raw_ssh) != 4:
            raise HostError('Run in the actual management SSH session (SSH_CONNECTION required)')
        peer, peer_port, local, local_port = raw_ssh
        peer = str(self._address(peer))
        local = str(self._address(local))
        if (local not in [a['address'] for a in addresses]
                or not peer_port.isdecimal() or not local_port.isdecimal()
                or not 1 <= int(peer_port) <= 65535 or not 1 <= int(local_port) <= 65535):
            raise HostError('SSH management address/port is not assigned to the selected interface')
        family = 'inet' if self._address(local).version == 4 else 'inet6'
        if gateways[family] is None:
            raise HostError('SSH management address family has no supported default route')
        # Dynamic evidence comes from actual addresses, never lease-file guesses.
        dynamic = any(a['dynamic'] for a in addresses)
        if dynamic and not all(a['dynamic'] for a in addresses):
            raise HostError('Mixed DHCP/static address families require an unsupported per-family plan')
        return {'interfaces': interfaces, 'interface': name, 'mac': selected['mac'].lower(),
                'mode': 'dhcp' if dynamic else 'static', 'addresses': addresses,
                'gateway4': gateways['inet'], 'gateway6': gateways['inet6'],
                'dns': self._dns(name), 'routes': main_routes, 'rules': rules,
                'ssh_local_address': local, 'ssh_peer_address': peer,
                'ssh_local_port': int(local_port)}

    def _ssh_ports(self, supplied, network):
        # No sshd_config regex parsing and NO fallback to 22.
        effective = []
        for line in self.run(['sshd', '-T']).splitlines():
            fields = line.split()
            if fields and fields[0].lower() == 'port':
                if len(fields) != 2 or not fields[1].isdecimal() or not 1 <= int(fields[1]) <= 65535:
                    raise HostError('Invalid effective SSH port')
                effective.append(int(fields[1]))
        effective = sorted(set(effective))
        if not effective:
            raise HostError('sshd -T returned no effective ports')
        if supplied is not None:
            if (not isinstance(supplied, list) or not supplied
                    or any(type(p) is not int or not 1 <= p <= 65535 for p in supplied)
                    or sorted(set(supplied)) != effective):
                raise HostError('Caller SSH ports do not match successful sshd -T; no fallback is allowed')
        local = network['ssh_local_address']
        listeners = set()
        for line in self.run(['ss', '-H', '-ltn']).splitlines():
            fields = line.split()
            if len(fields) < 5:
                raise HostError('Cannot parse listening TCP sockets')
            endpoint = fields[3]
            address, sep, port = endpoint.rpartition(':')
            if not sep or not port.isdecimal():
                raise HostError('Cannot parse listening TCP endpoint')
            address = address.strip('[]')
            # An IPv6 wildcard does not prove IPv4 reachability (v6only).
            wildcard = '0.0.0.0' if self._address(local).version == 4 else '::'
            if address in (local, wildcard, '*'):
                listeners.add(int(port))
        if not set(effective) <= listeners or network['ssh_local_port'] not in effective:
            raise HostError('sshd -T ports do not match live management listeners/session; socket activation or stale config is unsupported')
        return effective

    def inventory(self, ssh_ports=None):
        """Read-only supported-host facts; supplied ports are JSON integer list."""
        try:
            if os.geteuid() != 0:
                raise HostError('Reinstall preflight requires actual root privileges')
            if platform.machine().lower() not in ('x86_64', 'amd64'):
                raise HostError('Only amd64 is supported')
            if Path('/sys/firmware/efi').exists():
                raise HostError('UEFI is unsupported; BIOS GRUB is required')
            if not Path('/sys').is_mount() or not Path('/proc').is_mount():
                raise HostError('Real host /sys and /proc mounts are required')
            release = self._os_release()
            storage = self._storage()
            grub = self._grub(storage)
            network = self._network()
            ports = self._ssh_ports(ssh_ports, network)
            meminfo = Path('/proc/meminfo').read_text()
            match = re.search(r'^MemTotal:\s+(\d+)\s+kB$', meminfo, re.MULTILINE)
            if not match:
                raise HostError('Cannot determine physical RAM')
            fs = os.statvfs('/boot')
            return {'os_id': release['ID'], 'os_version': release['VERSION_ID'],
                    'arch': 'amd64', 'firmware': 'bios', **storage, **grub,
                    'memory_bytes': int(match.group(1)) * 1024,
                    'boot_free_bytes': fs.f_bavail * fs.f_frsize,
                    'boot_cmdline': Path('/proc/cmdline').read_text(errors='replace'),
                    'network': network, 'ssh_ports': ports}
        except HostError:
            raise
        except (OSError, ValueError, TypeError, KeyError, AttributeError) as exc:
            raise HostError('Incomplete or inconsistent host inventory; refusing to guess') from exc

    def prepare_work(self):
        """Make a fresh private /boot workspace, never alter boot configuration.

        Parent MUST hold its exclusive root-private lock before this call, keep
        it through commit/rollback, and remove its workspace after safe cancel.
        Parent MUST NOT reuse any workspace from an earlier invocation.
        """
        if os.geteuid() != 0:
            raise HostError('Private boot workspace requires root')
        self._private_system_path(self.BOOT)
        self._no_stale_work()
        root, boot = self._mount('/'), self._mount(str(self.BOOT))
        if (root.get('target') != '/' or boot.get('target') != '/'
                or root.get('fstype') != 'ext4' or boot.get('fstype') != 'ext4'
                or root.get('maj:min') != boot.get('maj:min')):
            raise HostError('/boot must remain inside the same root ext4 filesystem')
        path = Path(tempfile.mkdtemp(prefix=self.WORK_PREFIX, dir=self.BOOT))
        os.chmod(path, 0o700)
        self.active_work = path
        descriptor = os.open(self.BOOT, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        return path


# Authentication and download boundaries. No downloaded code is executed.
import base64
import datetime
import gzip
import hashlib
import secrets
import shutil
import time
from urllib.parse import urlsplit


CATALOG = {
    ('debian', '12'): {'distro': 'debian', 'version': '12', 'codename': 'bookworm',
                      'installer': '20230607+deb12u15', 'release_version': '12.15', 'status': 'LTS 至 2028-06；软件包覆盖依 LTS 政策'},
    ('debian', '13'): {'distro': 'debian', 'version': '13', 'codename': 'trixie',
                      'installer': '20250803+deb13u7', 'release_version': '13.7', 'status': '稳定版；常规安全维护'},
    ('ubuntu', '22.04'): {'distro': 'ubuntu', 'version': '22.04', 'codename': 'jammy',
                         'iso': 'ubuntu-22.04.5-live-server-amd64.iso', 'status': 'LTS；标准维护至 2027-05'},
    ('ubuntu', '24.04'): {'distro': 'ubuntu', 'version': '24.04', 'codename': 'noble',
                         'iso': 'ubuntu-24.04.5-live-server-amd64.iso', 'status': 'LTS；标准维护至 2029-05'},
    ('ubuntu', '26.04'): {'distro': 'ubuntu', 'version': '26.04', 'codename': 'resolute',
                         'iso': 'ubuntu-26.04.1-live-server-amd64.iso', 'status': 'LTS；标准维护至 2031-05'},
}
# Binary OpenPGP certificates, fixed by this module's independently pinned hash.
# Primary fingerprints and official attribution are recorded in docs/reinstall.md.
DEBIAN_CERTIFICATES = (
    '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'
)
UBUNTU_CERTIFICATE = (
    'xsFNBE+tjmgBEAC7pKK78t89DW7mvMoSgiScLfPNF8/TSF380is0hFRL3dOmcXEfNsX26jtv8bdvvtkElB1fPwOntmqSAsrLOuUR'
    'VQ6GSxH7IDU5QFfaTIsudtLR5YTlC3ZuOTOb1HWEK26fDRXuIWjhFDXJH3KLv+rSrq0+x7ZtH++CHq5XJWk7VUh/wWcGxZefs7+1'
    'HTivymhjXCOwQvqblzZ5MAec9i4QIXxkqX1HY7ryxGVdjj9lApOnoU5EcSYr08cm7xQEgrdDLAZFQxDYBLDuV6E6jKEfAfwZINSE'
    'e4Ocm82vtCF5K0HiwhFU09ky2yogbMuTTi2f8ibN8SbbhZDJlDPd2ZkkpsKNfIALmOiPhHGvXGmtg6FdzRUOSGirSm8tcakpS+d0'
    '/IElbD453sksxg6s3cTs7Q+PudaccyQ0BqatMnzmfxCVOotT65kVnmz2P+4Q0gRSQ/Zi9Inz+OrzWxtn6/Tdw+FMUwvBccxW1r88'
    'k6uVLz23jW/8jOuwnUp4JKmZta/U2UZKTyPyrvTYhp/zK332BEnxiRY4ZfQjA4Iwlw00l4pYBDLLc6TFJtLbDv859UCisXa8MtWY'
    'WrlM3YfGFs9k1WemML8u79g2DK8g3VPkD94Q5anqufEGm74K/keOmss8cQoBX9VPFMpS1mFCT+2UdGP0UvMlADct0aFnAwtb9QAR'
    'AQABzUFVYnVudHUgQ0QgSW1hZ2UgQXV0b21hdGljIFNpZ25pbmcgS2V5ICgyMDEyKSA8Y2RpbWFnZUB1YnVudHUuY29tPsLBdwQT'
    'AQoAIQUCT62OaAIbAwULCQgHAwUVCgkICwUWAgMBAAIeAQIXgAAKCRDZSqPw7+IQkkhAEACJjZZXuAabMrC49Z52HywVZipJgoV5'
    'ufMi2LQYMkyGKVQQ/E74lUjccMmbQ4j00ihTYB+F/i29AxfavJnlSpWgmwjPO4YY5jvooUiXQmVHX10oM1w3+Y9wScmeUY3IhTtw'
    'iFaBJr6TZ7RvOTg/pbQ0GvzxNlkSobuqFCZ023mcl2Y7OkY1PZgxiLafD6Rx2O/gclQPs4YfHo8bKRA4o10702nE8YE+dixIgAQw'
    '67Txhq5idNxsWpudKq9J1fLgnEz7i9AJUOf12sg9X7ZvpXZ3QvMV5iOvLA4DRLv9HIxyz70XqeakS+uzfKXuCMzhdUTIb/tNACNB'
    '37+reIqdPsyUF3txVyWaL1jMkRsv617yKAiYvPNwMDRvrbKiJ4Icnd4tPzmqz5HBFUyULns3JzJNjpgKCvLGhVq+lVsdpMlpQxEG'
    '5/bhzJgB1jrIbkcOSfnQ1y0Gv9CItel+1q0BHMn0dPVWaNfKYFGsz4igW+uj//C09/gtGMm78PQfjqEoR2j/Tam/tmucxSK331yf'
    'm5ag2CQYGC3bswfII+4EanX9dN/RG3/2dsSyYruWpTIQG6Xa7+AZtYBDEXNYovgdJtXWyUtW0X7R6vIjh1HYer3dR6ivJ+q/bWGY'
    '45zHeNBNU33hlnlxEENif3RZ/j/w3SjGrtSQK69maNR6onq492e+6w=='
)
TRUST = {
    'debian-12': ('B8B80B5B623EAB6AD8775C45B7C5D7D6350947F8', DEBIAN_CERTIFICATES),
    'debian-13': ('04B54C3CDCA79751B16BC6B5225629DF75B188BD', DEBIAN_CERTIFICATES),
    'ubuntu': ('843938DF228D22F7B3742BC0D94AA3F0EFE21092', UBUNTU_CERTIFICATE),
}



def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def authenticate(host, work, target):
    trust_id = target['distro'] + ('-' + target['version'] if target['distro'] == 'debian' else '')
    fingerprint, encoded = TRUST[trust_id]
    key = work / 'release-key.gpg'
    key.write_bytes(base64.b64decode(encoded, validate=True))
    manifest = work / 'manifest'
    sig = work / 'signature'
    if target['distro'] == 'debian':
        base = 'https://deb.debian.org/debian/dists/' + target['codename']
        host.fetch(base + '/InRelease', sig, limit=8 * 1024 * 1024)
        status = host.run(['gpgv', '--homedir', str(work), '--status-fd', '1',
                           '--keyring', str(key), '--output', str(manifest), str(sig)])
    else:
        base = 'https://releases.ubuntu.com/' + target['version']
        host.fetch(base + '/SHA256SUMS', manifest, limit=1024 * 1024)
        host.fetch(base + '/SHA256SUMS.gpg', sig, limit=128 * 1024)
        status = host.run(['gpgv', '--homedir', str(work), '--status-fd', '1',
                           '--keyring', str(key), str(sig), str(manifest)])
    valid = [line.split() for line in status.splitlines() if line.startswith('[GNUPG:] VALIDSIG ')]
    if not any(row[2] == fingerprint or row[-1] == fingerprint for row in valid):
        raise HostError('发行版签名公钥指纹不匹配')
    if any(token in status for token in ('BADSIG', 'ERRSIG', 'REVKEYSIG', 'EXPKEYSIG', 'EXPSIG')):
        raise HostError('发行版签名无效或已过期')
    if target['distro'] == 'debian':
        fields = {}
        current = None
        for line in manifest.read_text().splitlines():
            if not line.strip():
                continue
            if line.startswith(' ') and current:
                fields[current] += '\n' + line.strip()
            else:
                current, sep, value = line.partition(':')
                if not sep or current in fields:
                    raise HostError('发行版 Release 格式错误')
                fields[current] = value.strip()
        if (fields.get('Codename') != target['codename'] or fields.get('Version') != target['release_version']
                or 'amd64' not in fields.get('Architectures', '').split()):
            raise HostError('发行版或架构与已签名清单不一致')
        from email.utils import parsedate_to_datetime
        now = datetime.datetime.now(datetime.timezone.utc)
        issued = parsedate_to_datetime(fields['Date'])
        # Stable Release may omit Valid-Until: impose a bounded replay window.
        if issued > now + datetime.timedelta(days=1) or now - issued > datetime.timedelta(days=366):
            raise HostError('发行版 Release 太旧或来自未来，拒绝回放')
        if fields.get('Valid-Until') and parsedate_to_datetime(fields['Valid-Until']) <= now:
            raise HostError('发行版 Release 已过有效期')
        rel = f"main/installer-amd64/{target['installer']}/images/SHA256SUMS"
        records = [row.split() for row in fields.get('SHA256', '').splitlines()]
        rows = [row for row in records if len(row) == 3 and row[2] == rel]
        if len(rows) != 1 or not re.fullmatch('[0-9a-f]{64}', rows[0][0]):
            raise HostError('固定安装器版本未被发行版签名清单覆盖；请等待仓库审查更新')
        sums = work / 'SHA256SUMS'
        host.fetch(base + '/' + rel, sums, limit=4 * 1024 * 1024)
        if sums.stat().st_size != int(rows[0][1]) or digest(sums) != rows[0][0]:
            raise HostError('安装器指纹清单与发行版签名不符')
        image_base = base + '/' + rel.rsplit('/', 1)[0]
        wanted = {'linux': './netboot/debian-installer/amd64/linux',
                  'initrd': './netboot/debian-installer/amd64/initrd.gz'}
        listing = sums.read_text()
    else:
        image_base = base
        wanted = {'install.iso': target['iso']}
        listing = manifest.read_text()
    entries = {}
    for line in listing.splitlines():
        match = re.fullmatch(r'([0-9a-fA-F]{64}) [ *](.+)', line)
        if match:
            entries.setdefault(match[2], []).append(match[1].lower())
    for local, remote in wanted.items():
        # Debian lists paths with ./, Ubuntu uses the bare filename.
        candidates = entries.get(remote, []) or entries.get(remote.removeprefix('./'), [])
        if len(candidates) != 1:
            raise HostError('必需安装材料没有唯一的已认证指纹：' + local)
        artifact = work / local
        host.fetch(image_base + '/' + remote.removeprefix('./'), artifact,
                   limit=(8 * 1024**3 if local == 'install.iso' else 512 * 1024**2))
        if digest(artifact) != candidates[0]:
            raise HostError('安装材料指纹不符：' + local)
    return wanted


def cpio_archive(files):
    """A newc initramfs overlay, containing only repository-generated files."""
    result = bytearray()
    directories = set()
    for name in files:
        parent = Path(name.lstrip('/')).parent
        while str(parent) != '.':
            directories.add(str(parent))
            parent = parent.parent
    parents = [(name, (b'', stat.S_IFDIR | (0o700 if name.split('/')[0] in ('reinstall', 'reinstall-runtime') else 0o755)))
               for name in sorted(directories, key=lambda x: (x.count('/'), x))]
    for index, (name, item) in enumerate([*parents, *files.items(), ('TRAILER!!!', (b'', 0))], 1):
        data, mode = item
        name = name.lstrip('/')
        if '..' in name.split('/') or not name or '\x00' in name:
            raise HostError('非法启动配置路径')
        encoded = name.encode() + b'\x00'
        values = [index, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(encoded), 0]
        result += b'070701' + ''.join(f'{v:08x}' for v in values).encode()
        result += encoded
        result += b'\x00' * (-len(result) % 4)
        result += data
        result += b'\x00' * (-len(result) % 4)
    result += b'\x00' * (-len(result) % 512)
    return bytes(result)


def prepare_payload(host, work, target, files):
    if target['distro'] == 'ubuntu':
        for source, destination in (('/casper/vmlinuz', 'linux'), ('/casper/initrd', 'initrd')):
            host.run(['xorriso', '-osirrox', 'on', '-indev', str(work / 'install.iso'),
                      '-extract', source, str(work / destination)], timeout=180)
    for name in ('linux', 'initrd'):
        path = work / name
        if not path.is_file() or path.is_symlink() or path.stat().st_size < 1024:
            raise HostError('认证后的启动材料提取失败：' + name)
    # Linux initramfs supports concatenated compressed/uncompressed newc archives.
    overlay = {name: (content.encode(), stat.S_IFREG | mode) for name, (content, mode) in files.items()}
    if target['distro'] == 'debian':
        overlay.update(preserve_debian_wget((work / 'initrd').read_bytes()))
    with (work / 'initrd').open('ab') as stream:
        stream.write(gzip.compress(cpio_archive(overlay), mtime=0))
        stream.flush()
        os.fsync(stream.fileno())
    return {name: digest(work / name) for name in ('linux', 'initrd', 'install.iso') if (work / name).is_file()}


"""Pure config fragment for issue #27; no host operations or internal tests.

validate_inventory(data,target)->plan. Accepts Host.inventory() JSON shape:
interfaces [{name,mac,addresses,flags,link_type,kind}], inet/inet6 address families,
main routes with family and default local/main/default rules. Rejects ambiguous
or unsupported IPv6/global, multi-NIC, multi-disk, special routes, UEFI/LVM/etc.
A GPT disk without a BIOS embedding partition is accepted only when
boot_cmdline carries an absolute BOOT_IMAGE (proof an on-disk bootloader
loaded this kernel; GRUB specifics are confirmed later by _grub()).
Account input comes LATER as plan['account']={username,mode,key,password_hash}.
username is revalidated immediately before rendering; random undisclosed hashes
for key-only mode are supported without enabling password login.

render_configs(plan,target)->{initrd_path:(text,permission_bits)}. The returned
mapping is sensitive; never log it. All files 0600 except executable native hooks
0755; parents must be root-private and generated in the cpio archive by parent.
Debian: authenticated native netboot, primary HTTPS only, native HTTP security
generator disabled; late writes HTTPS security/update sources and upgrades.
Ubuntu: JSON is YAML; direct autoinstall mapping (not cloud-init wrapper), fixed
HTTPS apt, refresh disabled, no snaps/driver/OEM extras, MAC-matched IPv4 config.
Runtime fragment must additionally enforce wget/debootstrap signature/redirect
policy, /usr/local/sbin/reinstall-early, and casper runtime hooks. Config hook
99-reinstall-config only carries private /reinstall payload into live root.
The caller must append EVERY string in plan['kernel_network_args'] (list[str])
to installer arguments. IPv6 explicitly disabled for installer AND target.

Target support: Debian12/13 Ubuntu22.04/24.04/26.04 BIOS amd64. Source support:
Debian12/13 Ubuntu22.04/24.04; one ext2/3/4 or XFS root (host adapter narrows to
ext4), one plain physical disk, one Ethernet NIC, one IPv4 subnet/default route.
Disk replacement uses MBR (<2TiB). DHCP preserves policy, not a stable lease.
Default key-only admin uses NOPASSWD sudo; explicit password mode requires a
SHA512-crypt hash. No root SSH, no disabling AppArmor/firewall or allowing all
ports. Existing distro firewall activation is preserved; ufw, if present, gets
only the chosen SSH allows. No cloud-security-group changes or end-to-end claim.
Actual material-size/RAM staging checks and all cleanup/rollback belong to parent.
"""

import copy
import ipaddress
import json
import re
import shlex


_REINSTALL_RELEASES = {
    ('debian', '12'): 'bookworm',
    ('debian', '13'): 'trixie',
    ('ubuntu', '22.04'): 'jammy',
    ('ubuntu', '24.04'): 'noble',
    ('ubuntu', '26.04'): 'resolute',
}
_REINSTALL_USER = re.compile(r'[a-z][a-z0-9_-]{0,30}\Z', re.ASCII)
_REINSTALL_RESERVED_USERS = frozenset((
    'sudo', 'adm', 'admin', 'users', 'nogroup', 'ubuntu', 'debian', 'root', 'daemon', 'bin', 'sys', 'sync', 'games', 'man', 'lp', 'mail',
    'news', 'uucp', 'proxy', 'www-data', 'backup', 'list', 'irc', '_apt',
    'nobody', 'systemd-network', 'systemd-timesync', 'messagebus', 'sshd',
    'syslog', 'pollinate', 'landscape', 'lxd', 'uuidd', 'tcpdump', 'tss',
    'usbmux', 'fwupd-refresh', 'dnsmasq', 'avahi', 'ntp', 'chrony',
    'debian-exim', 'postfix', 'redis', 'postgres', 'mysql', 'ftp', 'irc',
))


def _reinstall_error(reason):
    raise ValueError('无法安全生成重装配置：' + reason)


def _disk_bootloader_loaded_kernel(cmdline):
    """True when BOOT_IMAGE names an absolute path an on-disk bootloader loaded.

    Bootloader-agnostic: GRUB sets BOOT_IMAGE, syslinux does too. This only
    rules out a host direct-kernel boot; _grub() stays the GRUB authority.
    """
    if not isinstance(cmdline, str):
        return False
    return any(token.startswith('BOOT_IMAGE=/') and len(token) > len('BOOT_IMAGE=/')
               for token in cmdline.split())


def _reinstall_int(value, description, minimum=0, maximum=None):
    if type(value) is not int or value < minimum or (maximum is not None and value > maximum):
        _reinstall_error(description + ' 缺失或超出支持范围')
    return value


def _reinstall_ipv4(value, description):
    if not isinstance(value, str):
        _reinstall_error(description + ' 必须是明确的 IPv4 地址')
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        _reinstall_error(description + ' 不是有效 IP 地址')
    if address.version != 4:
        _reinstall_error(description + ' 使用 IPv6；首版不支持 IPv6 管理/安装网络')
    # Do not use is_global/is_private: private and documentation IPv4 ranges
    # are valid here; a public-address query is never substituted for local IP.
    if address.is_loopback or address.is_link_local or int(address) < 16777216 or int(address) >= 3758096384:
        _reinstall_error(description + ' 不是可用于此安装网络的单播 IPv4 地址（含本地DNS桩地址）')
    return address


def _reinstall_interface_names(interfaces):
    if not isinstance(interfaces, list):
        _reinstall_error('缺少完整网卡清单，不能猜测唯一网卡')
    names = []
    for item in interfaces:
        name = item.get('ifname', item.get('name')) if isinstance(item, dict) else item
        if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]{0,14}', name):
            _reinstall_error('网卡清单含未知、VLAN或特殊接口名')
        if isinstance(item, dict):
            kind = item.get('kind') or item.get('linkinfo', {}).get('info_kind')
            if kind or item.get('master'):
                _reinstall_error('不支持桥接、bond、VLAN、隧道或从属网卡')
            if item.get('link_type', 'ether' if name != 'lo' else 'loopback') not in ('ether', 'loopback'):
                _reinstall_error('只支持普通 Ethernet 网卡')
        if name != 'lo':
            names.append(name)
    if len(names) != 1:
        _reinstall_error('检测到多网卡或没有唯一网卡；必须先消除网络歧义')
    if re.match(r'(?:wl|br[0-9-]|virbr|docker|bond|team|tun|tap|wg|veth|zt)', names[0]):
        _reinstall_error('无线、桥接、bond或隧道网卡不在首版支持范围')
    return names


def _reinstall_validate_routes(routes, interface, subnet, local, gateway):
    if not isinstance(routes, list) or not routes:
        _reinstall_error('缺少完整路由证据，不能按地址猜测默认路由')
    allowed = {'dst', 'gateway', 'dev', 'protocol', 'scope', 'prefsrc', 'metric', 'flags', 'type', 'table', 'family'}
    defaults = connected = 0
    for route in routes:
        if not isinstance(route, dict) or set(route) - allowed:
            _reinstall_error('含特殊/未知路由字段（如多路径、源路由或策略路由）')
        if route.get('family') in ('inet6', 6):
            try:
                v6net = ipaddress.ip_network(route.get('dst'), strict=True)
            except (TypeError, ValueError):
                _reinstall_error('包含不支持的IPv6路由')
            if v6net.version == 6 and v6net.is_link_local and not route.get('gateway'):
                continue
            _reinstall_error('包含IPv6管理路由，首版仅支持IPv4')
        if route.get('family', 'inet') not in ('inet', 4):
            _reinstall_error('路由family不明确')
        if route.get('dev') != interface:
            _reinstall_error('路由指向其他网卡或缺少明确出口')
        if route.get('table', 'main') not in ('main', 254):
            _reinstall_error('只支持 main 路由表，不支持策略路由')
        if route.get('type', 'unicast') != 'unicast' or route.get('flags', []):
            _reinstall_error('不支持特殊类型/onlink路由')
        if route.get('protocol', 'static') not in ('kernel', 'dhcp', 'static', 'boot'):
            _reinstall_error('不支持动态路由协议或未知路由来源')
        if 'metric' in route:
            _reinstall_int(route['metric'], '路由 metric', 0, 4294967295)
        if route.get('prefsrc') is not None and _reinstall_ipv4(route['prefsrc'], '路由源地址') != local:
            _reinstall_error('路由首选源地址与唯一网卡地址不一致')
        dst = route.get('dst')
        if dst in ('default', '0.0.0.0/0'):
            defaults += 1
            if _reinstall_ipv4(route.get('gateway'), '默认路由网关') != gateway:
                _reinstall_error('实际默认路由与已报告网关不一致')
            if route.get('scope', 'global') != 'global':
                _reinstall_error('默认路由不是普通 global 单播路由')
        else:
            try:
                destination = ipaddress.ip_network(dst, strict=True)
            except (TypeError, ValueError):
                _reinstall_error('路由目的网段不是明确有效的 CIDR')
            if destination.version != 4:
                _reinstall_error('包含 IPv6 路由，首版不能可靠生成对应安装网络')
            if destination != subnet or route.get('gateway') is not None:
                _reinstall_error('含额外主机/专用网段路由，首版只支持直连网段和唯一默认路由')
            if route.get('scope', 'link') != 'link':
                _reinstall_error('直连路由的 scope 不是 link')
            connected += 1
    if defaults != 1 or connected != 1:
        _reinstall_error('必须恰有一个默认路由和一个对应直连路由；拒绝缺失/重复路由')


def validate_inventory(data, target):
    """Read no host state; return a validated, credential-free installation plan."""
    if not isinstance(data, dict) or not isinstance(target, dict):
        _reinstall_error('清单和目标必须为 JSON object')
    distro = target.get('distro')
    version = target.get('version')
    codename = _REINSTALL_RELEASES.get((distro, version)) if isinstance(distro, str) and isinstance(version, str) else None
    if not codename:
        _reinstall_error('目标只支持 Debian 12/13、Ubuntu 22.04/24.04/26.04；其他版本未实现而非自动降级')
    if target.get('codename') != codename:
        _reinstall_error('目标版本与发行代号不匹配')
    username = target.get('username', 'reinstalladmin')
    if not isinstance(username, str) or not _REINSTALL_USER.fullmatch(username) or username in _REINSTALL_RESERVED_USERS:
        _reinstall_error('管理员账号须为非系统普通账号：小写字母开头，随后仅小写字母/数字/_/-，最多31字符')
    hostname = target.get('hostname', 'reinstall')
    if not isinstance(hostname, str) or not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', hostname) or hostname == 'localhost':
        _reinstall_error('hostname 须为1至63字符的小写单标签主机名，不能为localhost')
    source_id, source_version = data.get('os_id'), data.get('os_version')
    source_ok = isinstance(source_version, str) and (
        (source_id == 'debian' and re.fullmatch(r'(?:12|13)(?:\.[0-9]+)*', source_version)) or
        (source_id == 'ubuntu' and re.fullmatch(r'(?:22\.04|24\.04)(?:\.[0-9]+)?', source_version))
    )
    if not source_ok:
        _reinstall_error('源系统只支持 Debian 12/13、Ubuntu 22.04/24.04')
    if data.get('arch') not in ('x86_64', 'amd64'):
        _reinstall_error('只支持 amd64/x86_64 架构')
    if data.get('firmware') != 'bios':
        _reinstall_error('UEFI或未知固件不支持；首版仅支持 BIOS')
    if data.get('grub') is not True:
        _reinstall_error('未确认存在可用的 GRUB BIOS 引导链')
    disk = data.get('disk')
    if not isinstance(disk, str) or not re.fullmatch(r'/dev/(?:sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+)', disk):
        _reinstall_error('目标不是受支持的明确物理整盘路径；LVM/RAID/加密/映射设备不支持')
    if data.get('disks') != [disk] or data.get('root_disk') != disk:
        _reinstall_error('多磁盘、目标磁盘歧义或根分区不在目标盘上')
    partition = data.get('root_partition')
    part_pattern = re.escape(disk) + (r'p[1-9][0-9]*' if 'nvme' in disk else r'[1-9][0-9]*')
    if not isinstance(partition, str) or not re.fullmatch(part_pattern, partition) or data.get('simple_layout') is not True:
        _reinstall_error('只支持单盘简单根分区；LVM、RAID、加密、独立/boot或复杂布局不能猜测处理')
    if (data.get('pttype') == 'gpt' and data.get('bios_embedding') is not True
            and not _disk_bootloader_loaded_kernel(data.get('boot_cmdline'))):
        _reinstall_error('GPT 磁盘没有 BIOS 引导分区，且 /proc/cmdline 无绝对路径 BOOT_IMAGE，'
                         '无法确认当前内核由磁盘引导器加载；拒绝在未知引导链上安排一次性启动')
    if data.get('root_fstype') not in ('ext2', 'ext3', 'ext4', 'xfs'):
        _reinstall_error('源根文件系统只支持 ext2/3/4、XFS；不支持子卷、加密和未知文件系统')
    gib = 1024 ** 3
    disk_bytes = _reinstall_int(data.get('disk_bytes'), '目标磁盘容量', (8 if distro == 'debian' else 16) * gib)
    if disk_bytes >= 2 * 1024 ** 4:
        _reinstall_error('BIOS首版使用MBR分区，拒绝2TiB及以上磁盘')
    memory_bytes = _reinstall_int(data.get('memory_bytes'), '内存（Debian至少1GiB、Ubuntu至少6GiB，ISO大小仍须独立校验）', (1 if distro == 'debian' else 6) * gib)
    boot_free_bytes = _reinstall_int(data.get('boot_free_bytes'), '/boot可用空间（至少512MiB，实际材料空间须另查）', 512 * 1024 ** 2)
    network = data.get('network')
    if not isinstance(network, dict):
        _reinstall_error('缺少实际网卡、地址、路由和DNS清单')
    interface = _reinstall_interface_names(network.get('interfaces'))[0]
    if network.get('interface') != interface:
        _reinstall_error('所选网卡与实际唯一网卡不一致')
    mac = network.get('mac')
    if not isinstance(mac, str) or not re.fullmatch(r'(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}', mac):
        _reinstall_error('必须提供唯一网卡的明确MAC地址，不能依赖源系统网卡名')
    mac = mac.lower()
    if int(mac[:2], 16) & 1 or mac == '00:00:00:00:00:00':
        _reinstall_error('网卡MAC不是有效单播地址')
    mode = network.get('mode')
    if mode not in ('dhcp', 'static'):
        _reinstall_error('未从实际配置确定 DHCP/静态模式，不能按地址猜测')
    if network.get('gateway6') not in (None, ''):
        _reinstall_error('存在 IPv6 默认网关；首版不支持 IPv6 管理网络')
    rules = network.get('rules', [])
    if not isinstance(rules, list):
        _reinstall_error('路由规则清单格式错误')
    for rule in rules:
        expected = {'local': 0, '255': 0, 'main': 32766, '254': 32766, 'default': 32767, '253': 32767}
        if (not isinstance(rule, dict) or set(rule) - {'priority', 'src', 'table', 'family', 'protocol'}
                or rule.get('src', 'all') != 'all' or rule.get('priority') != expected.get(str(rule.get('table')))
                or str(rule.get('table')) not in expected):
            _reinstall_error('存在非标准策略路由规则，首版不支持')
    addresses = network.get('addresses')
    if not isinstance(addresses, list):
        _reinstall_error('缺少接口实际地址/前缀')
    v4 = []
    ignored_link_local = False
    for item in addresses:
        if not isinstance(item, dict):
            _reinstall_error('接口地址清单格式错误')
        try:
            parsed = ipaddress.ip_address(item.get('address'))
        except (TypeError, ValueError):
            _reinstall_error('接口地址不是有效IP地址')
        if item.get('family') not in (parsed.version, 'inet' if parsed.version == 4 else 'inet6'):
            _reinstall_error('接口地址 family 与实际地址不一致')
        prefix = _reinstall_int(item.get('prefix'), '地址前缀', 0, 32 if parsed.version == 4 else 128)
        if parsed.version == 6:
            if not parsed.is_link_local:
                _reinstall_error('存在非link-local IPv6地址；首版不支持 IPv6 安装/管理网络')
            ignored_link_local = True
        else:
            v4.append((parsed, prefix))
    if len(v4) != 1:
        _reinstall_error('必须恰有一个实际IPv4地址，拒绝多地址/地址缺失')
    local, prefix = v4[0]
    _reinstall_ipv4(str(local), '本机接口地址')
    if not 1 <= prefix <= 30:
        _reinstall_error('首版不支持 /31、/32点到点、无前缀或特殊链路')
    subnet = ipaddress.IPv4Network((local, prefix), strict=False)
    if local in (subnet.network_address, subnet.broadcast_address):
        _reinstall_error('本地IP是网络地址或广播地址')
    gateway = _reinstall_ipv4(network.get('gateway4'), 'IPv4网关')
    if gateway not in subnet or gateway in (local, subnet.network_address, subnet.broadcast_address):
        _reinstall_error('网关不在本地明确子网内或不是可用独立主机；拒绝猜测/onlink特殊路由')
    _reinstall_validate_routes(network.get('routes'), interface, subnet, local, gateway)
    resolvers = network.get('dns')
    if not isinstance(resolvers, list) or not 1 <= len(resolvers) <= 3:
        _reinstall_error('必须提供1至3个明确上游IPv4 DNS，不得复制本机DNS桩或猜测公共DNS')
    dns = [str(_reinstall_ipv4(item, '上游DNS')) for item in resolvers]
    if len(set(dns)) != len(dns):
        _reinstall_error('DNS清单重复，需先核实实际配置')
    ssh_local = _reinstall_ipv4(network.get('ssh_local_address'), '当前SSH本地地址')
    peer = _reinstall_ipv4(network.get('ssh_peer_address'), '当前SSH客户端地址')
    if ssh_local != local:
        _reinstall_error('SSH本地地址不在接口地址清单中（不能把NAT公网查询结果当作本地IP）')
    if peer == local:
        _reinstall_error('SSH客户端与服务端本地地址相同，连接证据有歧义')
    ports = data.get('ssh_ports')
    if not isinstance(ports, list) or not 1 <= len(ports) <= 8:
        _reinstall_error('无法确定实际SSH管理端口或端口过多')
    for port in ports:
        _reinstall_int(port, 'SSH端口', 1, 65535)
    if len(set(ports)) != len(ports):
        _reinstall_error('SSH端口清单重复')
    iso_path = target.get('iso_path', '/boot/reinstall/install.iso')
    if not isinstance(iso_path, str) or not re.fullmatch(r'/boot/(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.iso', iso_path) or '..' in iso_path:
        _reinstall_error('ISO须为源根分区内明确的/boot/.../*.iso路径，禁止空格、路径穿越和shell元字符')
    iso_sha256 = target.get('iso_sha256')
    if iso_sha256 is not None and (not isinstance(iso_sha256, str) or not re.fullmatch(r'[a-fA-F0-9]{64}', iso_sha256)):
        _reinstall_error('ISO SHA256格式错误')
    normalized_target = {'distro': distro, 'version': version, 'codename': codename, 'username': username, 'hostname': hostname, 'iso_path': iso_path}
    if iso_sha256:
        normalized_target['iso_sha256'] = iso_sha256.lower()
    kernel_args = ['net.ifnames=0', 'biosdevname=0', 'ipv6.disable=1', 'BOOTIF=01-' + mac.replace(':', '-')]
    if mode == 'static':
        # ipconfig format: client:server:gateway:netmask:hostname:device:autoconf:dns0:dns1
        kernel_args.append('ip=' + ':'.join([str(local), '', str(gateway), str(subnet.netmask), hostname, 'eth0', 'none'] + dns[:2]))
    else:
        kernel_args.append('ip=:::::eth0:dhcp')
    warnings = [
        '仅隔离配置验证不等于真实重装验证；覆盖磁盘后不能自动还原。',
        '保持发行版防火墙启用状态；若有ufw则只补充已确认SSH端口规则，不开放所有端口，不修改云安全组。',
        '首版安装环境和目标系统明确禁用IPv6；如依赖IPv6请停止。',
    ]
    if mode == 'dhcp':
        warnings.append('DHCP将由同一MAC重新申请地址、默认路由和DNS；当前地址只是观测值，不承诺重装后租约/公网映射不变，请先核对租约保留和控制台。')
    if ignored_link_local:
        warnings.append('仅忽略源接口自动生成的IPv6 link-local地址；没有将其当作受支持IPv6网络。')
    return {
        'schema': 1, 'inventory': copy.deepcopy(data), 'target': normalized_target,
        'source': {'distro': source_id, 'version': source_version, 'arch': 'amd64'},
        'arch': 'amd64', 'firmware': 'bios', 'disk': disk, 'disk_bytes': disk_bytes,
        'root_partition': partition, 'memory_bytes': memory_bytes, 'boot_free_bytes': boot_free_bytes,
        'username': username, 'hostname': hostname, 'ssh_ports': list(ports),
        'ssh_port': network.get('ssh_local_port') if network.get('ssh_local_port') in ports else ports[0],
        'network': {'mode': mode, 'source_interface': interface, 'interface': 'eth0', 'mac': mac,
                    'address': str(local), 'prefix': prefix, 'netmask': str(subnet.netmask),
                    'subnet': str(subnet), 'gateway4': str(gateway), 'dns': dns,
                    'ssh_local_address': str(ssh_local), 'ssh_peer_address': str(peer),
                    'addresses': [{'address': str(local), 'prefix': prefix, 'family': 'inet'}]},
        'kernel_network_args': kernel_args, 'iso_path': iso_path,
        'iso_sha256': iso_sha256.lower() if iso_sha256 else None,
        'warnings': warnings,
    }


def _reinstall_password_hash(value):
    if value is None:
        return '*'
    if not isinstance(value, str):
        _reinstall_error('密码模式需要显式SHA512-crypt哈希，不接受明文/空密码')
    match = re.fullmatch(r'\$6\$(?:rounds=([0-9]{4,7})\$)?[./A-Za-z0-9]{1,16}\$[./A-Za-z0-9]{86}', value)
    if not match or (match[1] is not None and not 5000 <= int(match[1]) <= 1000000):
        _reinstall_error('只接受有效格式的SHA512-crypt哈希（$6$，5000至1000000轮）；不接受固定默认密码或账号锁标记')
    return value


def _reinstall_sshd_config(plan, password):
    return '\n'.join([
        '# Managed by the reviewed reinstall module; no conflicting cloud-init includes.',
        *('Port ' + str(port) for port in plan['ssh_ports']),
        'AddressFamily inet', 'PermitRootLogin no', 'PubkeyAuthentication yes',
        'PasswordAuthentication ' + ('yes' if password else 'no'),
        'KbdInteractiveAuthentication no', 'PermitEmptyPasswords no', 'UsePAM yes',
        'AuthorizedKeysFile .ssh/authorized_keys', 'StrictModes yes',
        'AllowUsers ' + plan['username'], 'X11Forwarding no', 'PrintMotd no',
        'AcceptEnv LANG LC_*', 'Subsystem sftp internal-sftp', '',
    ])


def _reinstall_target_script(plan, password):
    """The script reads credentials from private files, never shell arguments."""
    user = shlex.quote(plan['username'])
    ports = ' '.join(str(port) for port in plan['ssh_ports'])
    script = '''#!/bin/sh
set -eu
umask 077
# Intentionally no set -x, credential echo, public progress server or curl script.
private=/root/reinstall
chmod 0700 /root "$private"
chmod -R go-rwx "$private"
username=__USER__
if ! id "$username" >/dev/null 2>&1; then
    useradd --create-home --user-group --shell /bin/bash "$username"
fi
usermod --append --groups sudo "$username"
# chpasswd reads the hash on stdin; it never appears in argv/process listings.
chpasswd --encrypted < "$private/account-password"
chage --expiredate -1 --inactive -1 --maxdays -1 "$username"
home=$(getent passwd "$username" | cut -d: -f6)
[ "$home" = "/home/$username" ] || exit 1
group=$(id -gn "$username")
chmod 0750 "$home"
install -d -m 0700 -o "$username" -g "$group" "$home/.ssh"
install -m 0600 -o "$username" -g "$group" "$private/authorized_keys" "$home/.ssh/authorized_keys"
install -d -m 0755 /etc/sudoers.d
install -m 0440 "$private/sudoers" "/etc/sudoers.d/90-reinstall-admin"
visudo -cf /etc/sudoers >/dev/null
install -d -m 0755 /etc/default/grub.d
install -m 0644 "$private/grub.cfg" /etc/default/grub.d/90-reinstall.cfg
install -m 0644 "$private/apt-https.conf" /etc/apt/apt.conf.d/99reinstall-https
__DISTRO_SETUP__
install -m 0600 "$private/sshd_config" /etc/ssh/sshd_config
ssh-keygen -A >/dev/null
install -d -m 0755 /run/sshd
/usr/sbin/sshd -t
# Ubuntu 24.04 can default to socket activation; use the configured service ports.
if [ -e /lib/systemd/system/ssh.socket ] || [ -e /usr/lib/systemd/system/ssh.socket ]; then
    systemctl disable ssh.socket >/dev/null
    systemctl mask ssh.socket >/dev/null
fi
systemctl enable ssh.service >/dev/null
# Do not flush rules, disable a firewall/AppArmor, enable a new default policy,
# or change cloud rules. A clean distro with ufw gets only the required SSH allows.
if command -v ufw >/dev/null 2>&1; then
    for port in __PORTS__; do ufw allow "$port/tcp" >/dev/null; done
fi
update-grub >/dev/null
# Native installers can retain copies containing password hashes/public keys.
# Restrict diagnostics and delete known credential-bearing config copies.
if [ -d /var/log/installer ]; then
    chmod 0700 /var/log/installer
    chmod -R go-rwx /var/log/installer
    rm -f /var/log/installer/autoinstall-user-data /var/log/installer/autoinstall-user-data.txt
    rm -f /var/log/installer/curtin-install-cfg.yaml /var/log/installer/curtin-install.conf
    rm -f /var/log/installer/preseed.cfg /var/log/installer/cdebconf/questions.dat
    rm -f /var/log/installer/cdebconf/passwords.dat
fi
# Cloud-init's required first-boot seed is retained, but strictly root-private.
if [ -d /var/lib/cloud ]; then chmod -R go-rwx /var/lib/cloud; fi
if [ -d /etc/cloud/cloud.cfg.d ]; then chmod -R go-rwx /etc/cloud/cloud.cfg.d; fi
rm -rf "$private"
'''
    if plan['target']['distro'] == 'debian':
        distro_setup = '''# d-i uses the same explicit IPv4/DHCP policy as this target.
install -m 0644 "$private/interfaces" /etc/network/interfaces
if [ -f "$private/resolv.conf" ]; then
    rm -f /etc/resolv.conf
    install -m 0644 "$private/resolv.conf" /etc/resolv.conf
fi
# All native installer packages used the primary authenticated HTTPS mirror.
# Replace only this freshly installed target's APT sources, never the source OS.
rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources
install -m 0644 "$private/sources.list" /etc/apt/sources.list
[ -s /etc/ssl/certs/ca-certificates.crt ]
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confold upgrade'''
    else:
        distro_setup = '''# Subiquity applies the MAC-matched netplan during install and to the target.
# cloud-init is allowed to finish the same account/key/SSH policy on first boot.
if [ -d /etc/netplan ]; then chmod -R go-rwx /etc/netplan; fi
# Do not add background third-party/snap refresh or entropy reporting.
for unit in pollinate.service snapd.service snapd.socket snapd.seeded.service; do
    systemctl mask \"$unit\" >/dev/null
done'''
    return script.replace('__USER__', user).replace('__PORTS__', ports).replace('__DISTRO_SETUP__', distro_setup)


def _reinstall_debian_apt_hook():
    # Native base-installer pre-install hooks run AFTER debootstrap populated
    # /target, but BEFORE its first target apt update / kernel installation.
    return """#!/bin/sh
set -eu
umask 077
mkdir -p /target/etc/apt/apt.conf.d
cp /reinstall/apt-https.conf /target/etc/apt/apt.conf.d/99reinstall-https
chmod 0644 /target/etc/apt/apt.conf.d/99reinstall-https
/reinstall-runtime/target-policy /target
[ -s /target/etc/ssl/certs/ca-certificates.crt ]
"""


def _reinstall_debian_preseed(plan):
    n, t = plan['network'], plan['target']
    lines = [
        '# Injected privately into the authenticated netboot initrd; no remote preseed URL.',
        'd-i debian-installer/locale string en_US.UTF-8',
        'd-i keyboard-configuration/xkb-keymap select us',
        'd-i netcfg/choose_interface select eth0',
        'd-i netcfg/get_hostname string ' + plan['hostname'],
        'd-i netcfg/hostname string ' + plan['hostname'],
        'd-i netcfg/get_domain string localdomain',
        'd-i netcfg/wireless_wep string',
        'd-i netcfg/disable_autoconfig boolean ' + ('true' if n['mode'] == 'static' else 'false'),
    ]
    if n['mode'] == 'static':
        lines += [
            'd-i netcfg/get_ipaddress string ' + n['address'],
            'd-i netcfg/get_netmask string ' + n['netmask'],
            'd-i netcfg/get_gateway string ' + n['gateway4'],
            'd-i netcfg/get_nameservers string ' + ' '.join(n['dns']),
            'd-i netcfg/confirm_static boolean true',
        ]
    else:
        lines += ['d-i netcfg/dhcp_timeout string 60']
    lines += [
        'd-i clock-setup/utc boolean true', 'd-i time/zone string UTC',
        # Avoid unauthenticated installation-time NTP changing trust-validation time.
        'd-i clock-setup/ntp boolean false',
        'd-i passwd/root-login boolean false', 'd-i passwd/make-user boolean true',
        'd-i passwd/user-fullname string ' + plan['username'],
        'd-i passwd/username string ' + plan['username'],
        'd-i passwd/user-password-crypted password *',
        'd-i passwd/user-default-groups string sudo',
        'd-i mirror/protocol string https',
        'd-i mirror/country string manual',
        'd-i mirror/https/hostname string deb.debian.org',
        'd-i mirror/https/directory string /debian',
        'd-i mirror/https/proxy string',
        'd-i mirror/suite string ' + t['codename'],
        'd-i mirror/udeb/suite string ' + t['codename'],
        'd-i base-installer/includes string ca-certificates',
        # Security generator hardcodes http; use primary HTTPS during install,
        # then add the security pocket over HTTPS and upgrade in late_command.
        'd-i apt-setup/use_mirror boolean true', 'd-i apt-setup/services-select multiselect',
        'd-i apt-setup/enable-source-repositories boolean false',
        'd-i debian-installer/allow_unauthenticated boolean false',
        'd-i debian-installer/allow_unauthenticated_ssl boolean false',
        'd-i partman/early_command string /reinstall-runtime/debian-before-partman',
        'd-i apt-setup/early_command string /reinstall-runtime/target-policy /target',
        'd-i partman-auto/disk string ' + plan['disk'],
        'd-i partman-auto/method string regular',
        'd-i partman-partitioning/choose_label select msdos',
        'd-i partman-partitioning/default_label string msdos',
        'd-i partman-auto/expert_recipe string reinstall :: 1024 10000 -1 ext4 $primary{ } $bootable{ } method{ format } format{ } use_filesystem{ } filesystem{ ext4 } mountpoint{ / } .',
        'd-i partman-auto/choose_recipe select reinstall',
        'd-i partman-basicfilesystems/no_swap boolean false',
        'd-i partman-partitioning/confirm_write_new_label boolean true',
        'd-i partman/choose_partition select finish',
        'd-i partman/confirm boolean true', 'd-i partman/confirm_nooverwrite boolean true',
        'tasksel tasksel/first multiselect standard',
        'd-i pkgsel/include string sudo openssh-server ca-certificates',
        'd-i pkgsel/upgrade select none', 'popularity-contest popularity-contest/participate boolean false',
        'd-i grub-installer/only_debian boolean true',
        'd-i grub-installer/bootdev string ' + plan['disk'],
        'd-i cdrom-detect/eject boolean false',
        # No credentials are in this command. Files remain mode 0600 under /root.
        'd-i preseed/late_command string /reinstall-runtime/debian-late && mkdir -p /target/root/reinstall && chmod 0700 /target/root/reinstall && cp -a /reinstall/. /target/root/reinstall/ && in-target /bin/sh /root/reinstall/target.sh',
        'd-i finish-install/reboot_in_progress note',
    ]
    return '\n'.join(lines) + '\n'


def _reinstall_ubuntu_hook():
    return """#!/bin/sh
case "${1:-}" in prereqs) exit 0 ;; esac
set -eu
fatal() { echo 'reinstall: private config injection failed; stopped' >/dev/console; while :; do sleep 3600; done; }
trap fatal EXIT
umask 077
[ -d /root/etc ] && [ -d /reinstall ]
mkdir -p /root/reinstall
chmod 0700 /root/reinstall
cp -a /reinstall/. /root/reinstall/
chmod -R go-rwx /root/reinstall
mkdir -p /root/var/log/installer
chmod 0700 /root/var/log/installer
trap - EXIT
"""


def _reinstall_ubuntu_autoinstall(plan, key, password_hash, password):
    n, t = plan['network'], plan['target']
    crypted = _reinstall_password_hash(password_hash)
    ethernet = {'match': {'macaddress': n['mac']}, 'set-name': 'eth0',
                'dhcp4': n['mode'] == 'dhcp', 'dhcp6': False, 'accept-ra': False,
                'optional': False}
    if n['mode'] == 'static':
        ethernet.update({'addresses': [n['address'] + '/' + str(n['prefix'])],
                         'routes': [{'to': '0.0.0.0/0', 'via': n['gateway4']}],
                         'nameservers': {'addresses': n['dns']}})
    # Legacy primary/security format works with BOTH Jammy and Noble Subiquity.
    # No automatic country mirror, floating installer refresh or remote reporting.
    sources = '\n'.join([
        'deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://archive.ubuntu.com/ubuntu ' + t['codename'] + ' main restricted universe multiverse',
        'deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://archive.ubuntu.com/ubuntu ' + t['codename'] + '-updates main restricted universe multiverse',
        'deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://security.ubuntu.com/ubuntu ' + t['codename'] + '-security main restricted universe multiverse', '',
    ])
    cloud_user = {'name': plan['username'], 'gecos': plan['username'], 'shell': '/bin/bash',
                  'groups': ['adm', 'sudo'], 'lock_passwd': False, 'passwd': crypted,
                  'sudo': 'ALL=(ALL:ALL) ' + ('' if password else 'NOPASSWD: ') + 'ALL',
                  'ssh_authorized_keys': [key] if key else []}
    config = {'version': 1, 'locale': 'en_US.UTF-8', 'keyboard': {'layout': 'us'},
              'timezone': 'Etc/UTC', 'refresh-installer': {'update': False},
              'interactive-sections': [], 'snaps': [], 'drivers': {'install': False}, 'oem': {'install': False},
              'network': {'version': 2, 'ethernets': {'reinstall': ethernet}},
              'apt': {'preserve_sources_list': False, 'geoip': False,
                      'conf': _APT,
                      'primary': [{'arches': ['amd64'], 'uri': 'https://archive.ubuntu.com/ubuntu'}],
                      'security': [{'arches': ['amd64'], 'uri': 'https://security.ubuntu.com/ubuntu'}],
                      'sources_list': sources},
              'identity': {'hostname': plan['hostname'], 'username': plan['username'], 'password': crypted},
              'ssh': {'install-server': True, 'allow-pw': password, 'authorized-keys': [key] if key else []},
              'storage': {'swap': {'size': 0}, 'config': [
                  {'id': 'disk0', 'type': 'disk', 'path': plan['disk'], 'ptable': 'msdos',
                   'wipe': 'superblock-recursive', 'preserve': False, 'grub_device': True},
                  {'id': 'root-partition', 'type': 'partition', 'device': 'disk0', 'number': 1,
                   'size': -1, 'flag': 'boot', 'preserve': False},
                  {'id': 'root-format', 'type': 'format', 'volume': 'root-partition', 'fstype': 'ext4', 'preserve': False},
                  {'id': 'root-mount', 'type': 'mount', 'device': 'root-format', 'path': '/'},
              ]},
              'packages': ['sudo', 'openssh-server', 'ca-certificates'],
              'updates': 'security', 'shutdown': 'reboot',
              'reporting': {'builtin': {'type': 'print'}},
              'user-data': {'disable_root': True, 'ssh_pwauth': password, 'users': [cloud_user]},
              # Each command is an argv LIST: neither shell interpolation of
              # user data nor credentials in the command itself are needed.
              'early-commands': [
                  ['/usr/local/sbin/reinstall-early'],
                  ['sh', '-c', 'mkdir -p /etc/apt/apt.conf.d; cp /reinstall/apt-https.conf /etc/apt/apt.conf.d/99reinstall-https'],
                  ['sh', '-c', 'mkdir -p /target/etc/apt/apt.conf.d; cp /reinstall/apt-https.conf /target/etc/apt/apt.conf.d/99reinstall-https'],
                  ['sh', '-c', 'umask 077; mkdir -p /var/log/installer; chmod 0700 /var/log/installer; chmod -R go-rwx /var/log/installer; chmod 0600 /autoinstall.yaml; chmod -R go-rwx /reinstall'],
              ],
              'late-commands': [
                  ['/usr/local/lib/reinstall-runtime/target-policy', '/target'],
                  ['sh', '-c', 'mkdir -p /target/root/reinstall && chmod 0700 /target/root/reinstall && cp -a /reinstall/. /target/root/reinstall/'],
                  ['curtin', 'in-target', '--target=/target', '--', '/bin/sh', '/root/reinstall/target.sh'],
              ],
              'error-commands': [['sh', '-c', "printf '%s\\n' 'INSTALL FAILED: use the console; no automatic retry/reboot was requested.' >&2; chmod -R go-rwx /var/log/installer /reinstall 2>/dev/null || :"]],
              }
    # Direct /autoinstall.yaml is a bare autoinstall mapping, NOT cloud-config.
    # Wrapping {autoinstall: ...} is for cloud-init user-data transport instead.
    return json.dumps(config, ensure_ascii=True, indent=2) + '\n'


def _reinstall_render_text_configs(plan, key, password_hash, password):
    """Return private initrd files; callers must never log the returned mapping."""
    if not isinstance(plan, dict) or plan.get('schema') != 1:
        _reinstall_error('计划不是validate_inventory生成的受支持schema')
    # Revalidate stored inputs: no field used in a shell/config is trusted merely
    # because a caller claims it came from a plan. The only allowed post-plan
    # addition is the digest obtained by the parent's authenticated acquisition.
    checked = validate_inventory(plan.get('inventory'), plan.get('target'))
    for field in ('disk', 'root_partition', 'username', 'hostname', 'network', 'ssh_ports', 'kernel_network_args', 'iso_path'):
        if plan.get(field) != checked[field]:
            _reinstall_error('计划字段被修改，必须重新进行清单校验：' + field)
    checked['iso_sha256'] = plan.get('iso_sha256')
    if key is not None:
        if not isinstance(key, str) or not key.strip() or len(key) > 16384 or any(ord(c) < 32 or ord(c) == 127 for c in key):
            _reinstall_error('公钥必须是外部ssh-keygen已验证的单行文本，不得包含换行/控制字符')
        key = key.strip()
    if not password and not key:
        _reinstall_error('默认密钥方案没有已确认有效公钥；必须停止，不能暗中改成密码登录')
    crypted = _reinstall_password_hash(password_hash)
    p = checked
    files = {
        'reinstall/target.sh': _reinstall_target_script(p, password),
        'reinstall/authorized_keys': key + '\n' if key else '',
        'reinstall/account-password': p['username'] + ':' + crypted + '\n',
        'reinstall/sudoers': p['username'] + ' ALL=(ALL:ALL) ' + ('' if password else 'NOPASSWD: ') + 'ALL\n',
        'reinstall/sshd_config': _reinstall_sshd_config(p, password),
        'reinstall/apt-https.conf': _APT,
        'reinstall/grub.cfg': 'GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX:-} net.ifnames=0 biosdevname=0 ipv6.disable=1"\n',
    }
    if p['target']['distro'] == 'debian':
        n, codename = p['network'], p['target']['codename']
        files['preseed.cfg'] = _reinstall_debian_preseed(p)
        files['usr/lib/base-installer.d/00reinstall-https'] = _reinstall_debian_apt_hook()
        interfaces = 'auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet ' + ('dhcp' if n['mode'] == 'dhcp' else 'static') + '\n'
        if n['mode'] == 'static':
            interfaces += '    address ' + n['address'] + '/' + str(n['prefix']) + '\n    gateway ' + n['gateway4'] + '\n'
            files['reinstall/resolv.conf'] = ''.join('nameserver ' + address + '\n' for address in n['dns'])
        files['reinstall/interfaces'] = interfaces
        signed = 'deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] '
        files['reinstall/sources.list'] = '\n'.join([
            signed + 'https://deb.debian.org/debian ' + codename + ' main',
            signed + 'https://deb.debian.org/debian ' + codename + '-updates main',
            signed + 'https://security.debian.org/debian-security ' + codename + '-security main', '',
        ])
    else:
        files['autoinstall.yaml'] = _reinstall_ubuntu_autoinstall(p, key, crypted, password)
        files['scripts/casper-bottom/99-reinstall-config'] = _reinstall_ubuntu_hook()
    return files


def render_configs(plan, target):
    """Flow API: use the separately confirmed account; return text/mode pairs."""
    if not isinstance(plan, dict) or not isinstance(target, dict):
        _reinstall_error('缺少已校验计划和目标')
    for field in ('distro', 'version', 'codename'):
        if target.get(field) != plan.get('target', {}).get(field):
            _reinstall_error('渲染目标与已确认计划不一致')
    account = plan.get('account')
    if not isinstance(account, dict) or account.get('mode') not in ('key', 'password'):
        _reinstall_error('必须显式确认密钥/密码登录模式')
    actual_target = dict(plan['target'])
    actual_target['username'] = account.get('username')
    checked = validate_inventory(plan['inventory'], actual_target)
    key = account.get('key') or None
    # Password hash comes from the explicitly prompted secret or from a fresh
    # undisclosed random secret in key-only mode; neither is a fixed password.
    crypted = _reinstall_password_hash(account.get('password_hash'))
    if account.get('password_hash') is None:
        _reinstall_error('缺少本次生成的唯一密码哈希')
    password = account['mode'] == 'password'
    files = _reinstall_render_text_configs(checked, key, crypted, password)
    executable = {'scripts/casper-bottom/99-reinstall-config', 'usr/lib/base-installer.d/00reinstall-https'}
    return {'/' + name: (content, 0o755 if name in executable else 0o600)
            for name, content in files.items()}


"""Runtime policies for the authenticated native installers (stdlib only).

Concatenate after HostError and imports, or import with its own HostError.
API: runtime_hooks(target, plan) -> {absolute_path: (text, mode)}.

MANDATORY integration:
* Debian: use preserve_debian_wget(original_initrd) BEFORE modifying initrd;
  merge its bytes overlay with the encoded text overlay in prepare_payload.
* Debian preseed: partman/early_command MUST call
  /reinstall-runtime/debian-before-partman. Install an executable
  /usr/lib/base-installer.d/00reinstall-https hook calling
  /reinstall-runtime/target-policy /target (NOT post-base-installer.d, which
  runs after the first apt_update). Disable default services-select because
  91security hardcodes HTTP; late_command may call
  /reinstall-runtime/debian-late. Explicitly disable unauthenticated(_ssl).
* Ubuntu: config overlay /autoinstall.yaml; early-commands FIRST calls
  /usr/local/sbin/reinstall-early; late-commands call
  /usr/local/lib/reinstall-runtime/target-policy /target.
* Ubuntu: refresh-installer.update=false, no drivers/snaps, explicit HTTPS
  primary/security mirrors, geoip=false and explicit timezone.
* Supply static networking for the live environment separately. No URL boot.

These hooks have NOT been boot-tested. They are not a support declaration.
"""
import gzip
import re
import shlex
import stat


def preserve_debian_wget(original_initrd):
    """Return a binary newc-overlay member, extracted ONLY from verified initrd.

    Caller must authenticate original_initrd before calling this function.
    No extraction to filesystem, symlink following, or binary execution.
    The returned dict uses bytes, unlike runtime_hooks' text interface.
    """
    data = gzip.decompress(original_initrd)
    if len(data) > 512 * 1024**2:
        raise ValueError('Debian initrd expands beyond supported size')
    offset = 0
    candidates = []
    keyrings = []
    trailer = False
    while offset + 110 <= len(data):
        header = data[offset:offset + 110]
        if header[:6] != b'070701':
            raise ValueError('Expected newc authenticated Debian initrd')
        try:
            fields = [int(header[i:i + 8], 16) for i in range(6, 110, 8)]
        except ValueError as exc:
            raise ValueError('Invalid newc header') from exc
        mode, size, namesize = fields[1], fields[6], fields[11]
        if not 1 <= namesize <= 4096 or size > 128 * 1024**2:
            raise ValueError('Invalid newc member bounds')
        start = offset + 110
        end = start + namesize
        if end > len(data) or data[end - 1] != 0:
            raise ValueError('Truncated newc name')
        name = data[start:end - 1].decode('utf-8', 'strict')
        body = (end + 3) & ~3
        finish = body + size
        if finish > len(data):
            raise ValueError('Truncated newc payload')
        if name == 'TRAILER!!!':
            trailer = True
            break
        if name.removeprefix('./') == 'usr/bin/wget':
            value = data[body:finish]
            if not stat.S_ISREG(mode) or not mode & 0o111 or not value.startswith(b'\x7fELF'):
                raise ValueError('Authenticated initrd wget is not a native ELF executable')
            candidates.append(value)
        if name.removeprefix('./') in ('usr/share/keyrings/debian-archive-keyring.gpg',
                                          'usr/share/keyrings/debian-archive-keyring.pgp'):
            if stat.S_ISLNK(mode):
                if (name.removeprefix('./') != 'usr/share/keyrings/debian-archive-keyring.gpg'
                        or data[body:finish] != b'debian-archive-keyring.pgp'):
                    raise ValueError('Unexpected embedded archive keyring symlink')
            elif stat.S_ISREG(mode) and size:
                keyrings.append(data[body:finish])
            else:
                raise ValueError('Expected regular embedded Debian archive keyring')
        offset = (finish + 3) & ~3
    if not trailer or len(candidates) != 1 or len(keyrings) != 1:
        raise ValueError('Expected exactly one authenticated native wget and archive keyring')
    return {'/usr/bin/wget.real': (candidates[0], stat.S_IFREG | 0o755),
            '/reinstall-runtime/native-archive.gpg': (keyrings[0], stat.S_IFREG | 0o600)}


_WGET = r'''#!/bin/sh
# Repository policy wrapper; wget.real is from the authenticated original initrd.
set -eu
unset WGETRC http_proxy https_proxy ftp_proxy all_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY ALL_PROXY no_proxy NO_PROXY
next=0
url=0
for arg do
    if [ "$next" = 1 ]; then next=0; continue; fi
    case "$arg" in
        --version) [ "$#" = 1 ] || exit 64; exec /usr/bin/wget.real --no-config --version ;;
        -O|-U|--output-document|--user-agent) next=1 ;;
        -q|-nv|--quiet|--no-verbose|-c|--continue|--progress=dot|--progress=dot:mega|--progress=dot:giga) ;;
        https://deb.debian.org/debian/*|https://security.debian.org/debian-security/*) url=1 ;;
        *) echo 'reinstall: wget request rejected by HTTPS policy' >&2; exit 64 ;;
    esac
done
[ "$next" = 0 ] && [ "$url" = 1 ] || exit 64
exec /usr/bin/wget.real --no-config --no-proxy --max-redirect=0 \
    --check-certificate=on --ca-directory=/etc/ssl/certs --timeout=45 --tries=2 "$@"
'''

_DEBOOTSTRAP = r'''#!/bin/sh
# Executed by the native bootstrap-base, but never accept its HTTPS GPG bypass.
set -eu
[ -s /usr/share/keyrings/debian-archive-keyring.gpg ] || exit 1
cmp -s /reinstall-runtime/native-archive.gpg /usr/share/keyrings/debian-archive-keyring.gpg || exit 1
command -v gpgv >/dev/null 2>&1 || exit 1
count=$#
skip=0
while [ "$count" -gt 0 ]; do
    arg=$1; shift; count=$((count - 1))
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$arg" in
        --no-check-gpg|--force-check-gpg|--keyring=*) ;;
        --keyring) skip=1 ;;
        --no-check-certificate|--no-check-valid-until) echo 'reinstall: unsafe bootstrap option' >&2; exit 64 ;;
        *) set -- "$@" "$arg" ;;
    esac
done
[ "$skip" = 0 ] || exit 64
exec /reinstall-runtime/debootstrap.real --force-check-gpg \
    --keyring=/usr/share/keyrings/debian-archive-keyring.gpg "$@"
'''

_DEBIAN_BEFORE = r'''#!/bin/sh
# MUST run as partman/early_command, before any disk writes. Native anna uses
# the authenticated Release/Packages chain and our strict HTTPS wget wrapper.
set -eu
. /usr/share/debconf/confmodule
db_get mirror/protocol
[ "$RET" = https ] || exit 1
db_get mirror/https/hostname
[ "$RET" = deb.debian.org ] || exit 1
db_get mirror/https/directory
[ "$RET" = /debian ] || exit 1
db_get debian-installer/allow_unauthenticated
[ "$RET" != true ] || exit 1
db_get debian-installer/allow_unauthenticated_ssl
[ "$RET" != true ] || exit 1
[ -s /usr/share/keyrings/debian-archive-keyring.gpg ] || exit 1
command -v gpgv >/dev/null 2>&1 || exit 1
anna-install bootstrap-base
anna-install debootstrap-udeb
# Refuse the alternative implementation rather than leave a bypass branch.
! command -v cdebootstrap >/dev/null 2>&1 || exit 1
[ -x /usr/sbin/run-debootstrap ] || exit 1
[ -x /usr/sbin/debootstrap ] || exit 1
cmp -s /reinstall-runtime/native-archive.gpg /usr/share/keyrings/debian-archive-keyring.gpg || exit 1
[ ! -e /reinstall-runtime/debootstrap.real ] || exit 1
mv /usr/sbin/debootstrap /reinstall-runtime/debootstrap.real
cp /reinstall-runtime/run-debootstrap-policy /usr/sbin/debootstrap
chmod 755 /usr/sbin/debootstrap
'''

_APT = '''Acquire::https::Verify-Peer "true";
Acquire::https::Verify-Host "true";
Acquire::https::AllowRedirect "false";
Acquire::http::AllowRedirect "false";
Acquire::https::Proxy "DIRECT";
Acquire::http::Proxy "DIRECT";
Acquire::AllowInsecureRepositories "false";
Acquire::AllowDowngradeToInsecureRepositories "false";
APT::Get::AllowUnauthenticated "false";
Acquire::Retries "0";
'''

# Native APT HTTPS is the http-method ELF selected by argv[0]. Preserve the
# native method BEFORE replacing the HTTP pathname (https is often a symlink).
_TARGET_POLICY = r'''#!/bin/sh
set -eu
root=${1:-/target}
case "$root" in /target|/) ;; *) exit 64;; esac
mkdir -p "$root/etc/apt/apt.conf.d" "$root/usr/lib/apt/methods"
cat > "$root/etc/apt/apt.conf.d/99-reinstall-transport" <<'APT_POLICY'
''' + _APT + r'''APT_POLICY
methods="$root/usr/lib/apt/methods"
if [ ! -f "$methods/.reinstall-https-native" ]; then
    [ -x "$methods/https" ] || { echo 'reinstall: native APT HTTPS method absent' >&2; exit 1; }
    cp -L "$methods/https" "$methods/.https.reinstall"
    chmod 755 "$methods/.https.reinstall"
    mv -f "$methods/.https.reinstall" "$methods/https"
    : > "$methods/.reinstall-https-native"
fi
rm -f "$methods/http"
cat > "$methods/http" <<'HTTP_DISABLED'
#!/bin/sh
printf '400 URI Failure\nMessage: HTTP disabled by reinstall transport policy\n\n'
exit 1
HTTP_DISABLED
chmod 755 "$methods/http"
'''


def runtime_hooks(target, plan):
    """Generate local, credential-free policies; never perform host operations."""
    distro = target.get('distro')
    code = target.get('codename', '')
    valid_codes = {'debian': {'bookworm', 'trixie'},
                   'ubuntu': {'jammy', 'noble', 'resolute'}}
    if distro not in valid_codes or code not in valid_codes[distro]:
        raise ValueError('Unsupported runtime target')
    disk = plan.get('disk') or plan.get('root_disk')
    if not isinstance(disk, str) or not re.fullmatch(r'/dev/(?:sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+)', disk):
        raise ValueError('Unsupported runtime disk identifier')
    files = {'/reinstall-runtime/target-policy': (_TARGET_POLICY, 0o700)}
    if distro == 'debian':
        files['/usr/lib/base-installer.d/00reinstall-transport'] = (
            '#!/bin/sh\nset -eu\n/reinstall-runtime/target-policy /target\n', 0o755)
        files['/reinstall-runtime/run-debootstrap-policy'] = (_DEBOOTSTRAP, 0o755)
        files['/reinstall-runtime/debian-before-partman'] = (_DEBIAN_BEFORE, 0o700)
        # Both authenticated initrds put GNU wget in usr/bin. Never add a bin
        # directory: Trixie uses bin -> usr/bin, and replacing that link would
        # remove /bin/sh from the native startup chain.
        files['/usr/bin/wget'] = (_WGET, 0o755)
        files['/etc/wgetrc'] = ('check_certificate = on\nmax_redirect = 0\nuse_proxy = off\n', 0o644)
        files['/etc/apt/apt.conf.d/99-reinstall-transport'] = (_APT, 0o644)
        # Runs after base system; never allow the stock HTTP security generator
        # before this point. apt-setup/early_command applies target-policy first.
        files['/reinstall-runtime/debian-late'] = (
            '#!/bin/sh\nset -eu\n/reinstall-runtime/target-policy /target\n'
            'rm -f /target/etc/apt/sources.list.d/debian.sources\n'
            "cat > /target/etc/apt/sources.list <<'SOURCES'\n"
            f'deb https://deb.debian.org/debian {code} main non-free-firmware\n'
            f'deb https://deb.debian.org/debian {code}-updates main non-free-firmware\n'
            f'deb https://security.debian.org/debian-security {code}-security main non-free-firmware\n'
            'SOURCES\n', 0o700)
        return files

    early = r'''#!/bin/sh
# This MUST be the first Subiquity early-command, before disk probing/writes.
set -eu
fail() { echo 'reinstall: live medium still depends on target disk, or runtime policy failed; stop and use console' >&2; exit 1; }
[ "$(findmnt -n -M /cdrom -o FSTYPE)" = tmpfs ] || fail
# ISO loop is no longer used after successful toram. Only detach loops backed
# by the old ISO source directory, NEVER loops serving squashfs from /cdrom.
losetup --list --noheadings --output NAME,BACK-FILE | while read -r loop back; do
    case "$back" in /isodevice/*|/run/initramfs/isodevice/*)
        losetup -d "$loop" || exit 1 ;;
    esac
done || fail
for old in /isodevice /run/initramfs/isodevice; do
    if findmnt -n -M "$old" >/dev/null 2>&1; then umount "$old" || fail; fi
done
swapoff -a || fail
DISK=__DISK__
# lsblk enumerates disk and all child partitions. No mount or active swap may
# remain on ANY of them. No lazy/forced unmount is ever used.
[ -b "$DISK" ] || fail
lsblk -nr -o PATH "$DISK" | while read -r device; do
    if findmnt -rn -S "$device" | grep -q .; then exit 1; fi
    [ -e "/sys/class/block/${device##*/}/holders" ] || exit 1
    for holder in /sys/class/block/"${device##*/}"/holders/*; do
        [ ! -e "$holder" ] || exit 1
    done
done || fail
/usr/local/lib/reinstall-runtime/target-policy /
'''.replace('__DISK__', shlex.quote(disk))
    files['/reinstall-runtime/ubuntu-early'] = (early, 0o700)
    # run_scripts need not propagate errors, therefore fail closed by stopping
    # before switch_root rather than returning failure to Casper and continuing.
    casper = r'''#!/bin/sh
PREREQ=""
case "${1:-}" in prereqs) echo "$PREREQ"; exit 0;; esac
set -eu
fatal() {
    echo 'reinstall: cannot prepare verified live runtime; stopped before installation' >/dev/console
    while :; do sleep 3600; done
}
trap fatal EXIT
[ -s /autoinstall.yaml ] || fatal
[ -d /root/etc ] && [ -d /root/usr ] || fatal
mkdir -p /root/usr/local/lib/reinstall-runtime /root/usr/local/sbin /root/etc/apt/apt.conf.d /root/etc/systemd/system
cp /autoinstall.yaml /root/autoinstall.yaml
chmod 600 /root/autoinstall.yaml
cp /reinstall-runtime/target-policy /root/usr/local/lib/reinstall-runtime/target-policy
cp /reinstall-runtime/ubuntu-early /root/usr/local/sbin/reinstall-early
chmod 700 /root/usr/local/lib/reinstall-runtime/target-policy /root/usr/local/sbin/reinstall-early
# No cloud datasource discovery, NTP, crash reports, or snap refresh daemon.
# These masks are LIVE-ONLY and are not copied into the installed target.
for unit in cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service systemd-timesyncd.service apport.service whoopsie.service; do
    ln -sf /dev/null "/root/etc/systemd/system/$unit"
done
# Keep snapd's local UNIX API available for the stock installer snap, but deny
# its daemon IP sockets (including automatic store/refresh/reporting traffic).
mkdir -p /root/etc/systemd/system/snapd.service.d
cat > /root/etc/systemd/system/snapd.service.d/reinstall-no-network.conf <<'SNAP_POLICY'
[Service]
RestrictAddressFamilies=AF_UNIX AF_NETLINK
SNAP_POLICY
mkdir -p /root/etc/cloud
: > /root/etc/cloud/cloud-init.disabled
# geoip=false alone does not prevent Subiquity's independent HTTPS lookup.
# Resolve it locally so no outbound request can report this host's public IP.
printf '\n127.0.0.1 geoip.ubuntu.com\n::1 geoip.ubuntu.com\n' >> /root/etc/hosts
# Install APT policy before live system userspace can make APT requests.
chroot /root /usr/local/lib/reinstall-runtime/target-policy /
trap - EXIT
exit 0
'''
    files['/scripts/casper-bottom/99-reinstall-runtime'] = (casper, 0o755)
    return files


import contextlib
import fcntl
import getpass
import signal


class Console:
    def say(self, text):
        print(text, flush=True)

    def ask(self, prompt):
        return input(prompt + ' ')

    def secret(self, prompt):
        # Never fall back to echoing credentials into a redirected input stream.
        if not sys.stdin.isatty():
            raise HostError('凭据必须在交互终端输入')
        return getpass.getpass(prompt + ' ')


class InstallerHost(Host):
    LOCKDIR = Path('/run/kejilion-reinstall')

    @contextlib.contextmanager
    def lock(self):
        self.LOCKDIR.mkdir(mode=0o700, exist_ok=True)
        self._private_system_path(self.LOCKDIR)
        if stat.S_IMODE(self.LOCKDIR.stat().st_mode) != 0o700:
            raise HostError('重装锁目录权限不安全')
        descriptor = os.open(self.LOCKDIR / 'lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600:
                raise HostError('重装锁文件不安全')
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise HostError('已有重装准备正在运行，请勿并发重试') from exc
            yield
        finally:
            os.close(descriptor)

    def require(self, target):
        if os.geteuid() != 0:
            raise HostError('重装需要 root 权限')
        for name in ('curl', 'gpgv', 'openssl', 'ssh-keygen'):
            self._binary(name)
        if target['distro'] == 'ubuntu':
            self._binary('xorriso')

    def fetch(self, url, destination, *, limit):
        parsed = urlsplit(url)
        if (parsed.scheme != 'https' or parsed.hostname not in ('deb.debian.org', 'releases.ubuntu.com')
                or parsed.port not in (None, 443) or parsed.username or parsed.password
                or parsed.fragment or parsed.query):
            raise HostError('拒绝不在发行版白名单内的取内容地址')
        partial = Path(str(destination) + '.partial')
        space = os.statvfs(partial.parent)
        limit = min(limit, space.f_bavail * space.f_frsize - 256 * 1024**2)
        if limit <= 0:
            raise HostError('私有准备目录空间不足，保留至少 256 MiB 系统余量')
        # No --location: all redirects (including same-origin) are rejected.
        try:
            code = self.run(['curl', '--disable', '--fail', '--silent', '--show-error',
                             '--proto', '=https', '--proto-redir', '=https',
                             '--tlsv1.2', '--connect-timeout', '20', '--max-time', '1800',
                             '--max-filesize', str(limit), '--write-out', '%{http_code}',
                             '--output', str(partial), url], timeout=1810)
            if code != '200' or not partial.is_file() or partial.is_symlink() or not 0 < partial.stat().st_size <= limit:
                raise HostError('取内容未返回完整 HTTPS 200；不接受重定向或残留文件')
            partial.replace(destination)
        finally:
            partial.unlink(missing_ok=True)

    def password_hash(self, password):
        # stdin is private, neither the password nor its hash appears in argv.
        executable = self._binary('openssl')
        result = subprocess.run([executable, 'passwd', '-6', '-stdin'], input=password + '\n',
                                text=True, capture_output=True, timeout=30, cwd='/',
                                env={'PATH': ':'.join(self.TRUSTED_BIN_DIRS), 'LC_ALL': 'C'})
        value = result.stdout.strip()
        if result.returncode or not re.fullmatch(r'\$6\$[./A-Za-z0-9$]+', value):
            raise HostError('无法安全生成唯一密码指纹')
        return value


class BootTransaction:
    """Only this object may alter the host boot chain; backup before every write."""
    def __init__(self, host, work, inventory):
        self.host, self.work, self.inventory = host, work, inventory
        self.entry = host.ENTRY
        self.cfg = Path(inventory['grub_cfg'])
        self.env = Path(inventory['grub_env'])
        self.modified = False
        self.owned_entry = False
        self.ident = 'kejilion-install-' + secrets.token_hex(8)

    def commit(self, plan, target, hashes):
        for path in (self.cfg, self.env):
            self.host._private_system_path(path, regular=True)
        if os.path.lexists(self.entry):
            raise HostError('存在未知安装启动项，拒绝覆盖')
        if not re.fullmatch(r'[A-Fa-f0-9-]{8,64}', self.inventory['root_uuid']):
            raise HostError('非法根分区 UUID')
        if not re.fullmatch(r'/boot/kejilion-reinstall\.[A-Za-z0-9_-]+', str(self.work)) and self.host.BOOT == Path('/boot'):
            raise HostError('工作目录不属于本次重装')
        for name, expected in hashes.items():
            if digest(self.work / name) != expected:
                raise HostError('准备后的启动材料被修改')
        for source, name in ((self.cfg, 'grub.cfg.before'), (self.env, 'grubenv.before')):
            shutil.copy2(source, self.work / name)
            os.chmod(self.work / name, 0o600)
            with (self.work / name).open('rb') as stream:
                os.fsync(stream.fileno())
        uuid = self.inventory['root_uuid']
        kernel = str(self.work / 'linux')
        initrd = str(self.work / 'initrd')
        args = boot_arguments(target, plan, self.work)
        entry = (f"menuentry 'Debian/Ubuntu authenticated reinstall' --id '{self.ident}' {{\n"
                 f" search --no-floppy --fs-uuid --set=root {uuid}\n"
                 f" linux {kernel} {args}\n initrd {initrd}\n}}\n")
        self.modified = True
        descriptor = os.open(self.entry, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o700)
        self.owned_entry = True
        with os.fdopen(descriptor, 'w') as stream:
            stream.write("#!/bin/sh\nexec cat <<'KJ_REINSTALL_ENTRY'\n" + entry + 'KJ_REINSTALL_ENTRY\n')
            stream.flush()
            os.fsync(stream.fileno())
        self.host.run(['update-grub'], timeout=180)
        self.host.run(['grub-script-check', str(self.cfg)])
        if self.cfg.read_text().count(self.ident) != 1:
            raise HostError('生成的 GRUB 配置没有唯一安装启动项')
        self.host.run(['grub-reboot', self.ident])
        values = self.host.run(['grub-editenv', str(self.env), 'list']).splitlines()
        if 'next_entry=' + self.ident not in values:
            raise HostError('一次性启动未成功提交')
        os.sync()

    def rollback(self):
        if not self.modified:
            return
        # Restore exact previous cfg/env, rather than regenerating defaults.
        for destination, backup in ((self.cfg, 'grub.cfg.before'), (self.env, 'grubenv.before')):
            self.host._private_system_path(destination, regular=True)
            temporary = destination.with_name(destination.name + '.kejilion-restore')
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            with os.fdopen(descriptor, 'wb') as stream:
                stream.write((self.work / backup).read_bytes())
                stream.flush()
                os.fsync(stream.fileno())
            shutil.copymode(destination, temporary)
            temporary.replace(destination)
        if self.owned_entry:
            self.entry.unlink()
        os.sync()
        self.modified = False


def boot_arguments(target, plan, work):
    if target['distro'] == 'debian':
        return 'auto=true priority=critical preseed/file=/preseed.cfg ' + ' '.join(plan['kernel_network_args']) + ' console=tty0 console=ttyS0,115200n8 panic=0'
    return (f'boot=casper iso-scan/filename={work}/install.iso toram autoinstall '
            'cloud-init=disabled subiquity.autoinstallpath=autoinstall.yaml '
            + ' '.join(plan['kernel_network_args']) + ' console=tty0 console=ttyS0,115200n8 panic=0')


def credentials(host, console, work):
    username = console.ask('普通管理账号（输入小写用户名，不使用 root）:').strip()
    if not re.fullmatch('[a-z][a-z0-9_-]{0,30}', username) or username in ('root', 'daemon', 'bin', 'sys', 'nobody', 'sshd', 'ubuntu', 'debian'):
        raise HostError('管理账号无效或与系统保留账号冲突')
    mode = console.ask('认证方式：输入 KEY 使用公钥；必须兼容密码时输入 PASSWORD:').strip()
    if mode == 'KEY':
        key = console.secret('粘贴单个 SSH 公钥（不要私钥；不支持 authorized_keys 选项）:').strip()
        if not re.fullmatch(r'(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521)) [A-Za-z0-9+/]+={0,3}(?: [^\r\n]*)?', key):
            raise HostError('缺少或无效公钥；不会禁用密码后留下无钥账号')
        public = work / 'login.pub'
        public.write_text(key + '\n')
        os.chmod(public, 0o600)
        fingerprint = host.run(['ssh-keygen', '-l', '-f', str(public)]).strip()
        parts = fingerprint.split()
        if len(fingerprint.splitlines()) != 1 or len(parts) < 2 or not parts[0].isdigit() or not parts[1].startswith('SHA256:'):
            raise HostError('公钥无法验证')
        if int(parts[0]) < (3072 if key.startswith('ssh-rsa ') else 256):
            raise HostError('公钥强度不足：RSA 至少 3072 位，其他受支持类型至少 256 位')
        console.say('请核对公钥指纹：' + ' '.join(fingerprint.split()[:2]))
        if console.ask('确认你持有对应私钥，输入 KEY:').strip() != 'KEY':
            raise HostError('未确认可用私钥，已停止')
        # An unguessable, undisclosed hash keeps the account unlocked for SSH;
        # sshd denies password auth. NOPASSWD sudo is scoped to this administrator.
        hashed = host.password_hash(secrets.token_urlsafe(48))
        return {'username': username, 'mode': 'key', 'key': key, 'password_hash': hashed}
    if mode == 'PASSWORD':
        password = console.secret('设置唯一密码（至少 16 字符，不会写入命令行或日志）:')
        if len(password) < 16 or len(password) > 128 or any(c in password for c in '\r\n\x00'):
            raise HostError('密码长度须 16–128 字符且不能含换行')
        if console.secret('再次输入密码:') != password:
            raise HostError('两次密码不一致')
        return {'username': username, 'mode': 'password', 'key': '', 'password_hash': host.password_hash(password)}
    raise HostError('未明确选择认证方式')


def run(host, console, distro, version, ssh_ports):
    target = CATALOG.get((distro, version))
    if target is None:
        console.say(f'{distro} {version} 不可用：未收录符合本路径的可信材料与维护方案；不切换归档或商业维护源。')
        return 1
    target = dict(target)
    work = None
    transaction = None
    submitted = False
    previous_handlers = {}
    def interrupted(signum, frame):
        raise HostError('收到中断信号，停止准备')
    try:
        for name in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            previous_handlers[name] = signal.signal(name, interrupted)
        with host.lock():
            try:
                host.require(target)
                inventory = host.inventory(ssh_ports)
                plan = validate_inventory(inventory, target)
                material_version = target.get('release_version') or target['iso']
                console.say(f"目标：{distro} {version} / amd64 / BIOS；{target['status']}；固定材料 {material_version}")
                console.say(f"将覆盖整盘 {plan['disk']}，包括原系统分区 {inventory['root_partition']}。")
                work = host.prepare_work()
                account = credentials(host, console, work)
                plan['account'] = account
                authenticate(host, work, target)
                if target['distro'] == 'ubuntu':
                    size = (work / 'install.iso').stat().st_size
                    if inventory['memory_bytes'] < size + 3 * 1024**3:
                        raise HostError('内存不足以完整复制安装 ISO 到 RAM 并运行安装环境')
                if sum(p.stat().st_size for p in work.iterdir() if p.is_file()) + 512 * 1024**2 > inventory['boot_free_bytes']:
                    raise HostError('启动分区空间不足以安全完成准备')
                files = render_configs(plan, target)
                files.update(runtime_hooks(target, plan))
                hashes = prepare_payload(host, work, target, files)
                transaction = BootTransaction(host, work, inventory)
                net = plan['network']
                console.say(f"网络：{net['interface']} / {net['mac']} / {net['mode']}；地址 " +
                            ', '.join(f"{a['address']}/{a['prefix']}" for a in net['addresses']))
                console.say(f"默认路由：{net.get('gateway4') or net.get('gateway6')}；DNS：" + ', '.join(net['dns']))
                port = plan['ssh_port']
                console.say(f"重装后连接：ssh -p {port} {account['username']}@{net['ssh_local_address']}；认证：{account['mode']}；具有 sudo 管理权限。")
                console.say('安装期间当前 SSH 会断开；安装环境不开放临时密码、进度网页或 SSH。请使用云控制台查看诊断。')
                console.say('若地址位于 NAT 后，请核对自己的公网映射；不会把公网查询结果替代本机地址。不会修改云安全组。')
                for warning in plan.get('warnings', []):
                    console.say('限制：' + warning)
                console.say('请先备份全部数据，确认控制台/救援可用。覆盖磁盘后不能自动还原。隔离测试不等于已证明真实重装不会失联。')
                # Require an independent exact destructive confirmation after all preparation.
                if console.ask('最终确认：输入 ERASE ' + plan['disk'] + ' 才提交重启安装:').strip() != 'ERASE ' + plan['disk']:
                    console.say('已取消；未提交安装启动。')
                    return 1
                # Re-read actual facts immediately before commit; stale plans cannot proceed.
                current = host.inventory(ssh_ports)
                stable = ('os_id', 'os_version', 'arch', 'firmware', 'disk', 'disk_bytes',
                          'root_partition', 'root_uuid', 'root_fstype', 'network', 'ssh_ports', 'grub_cfg', 'grub_env',
                          'pttype', 'bios_embedding', 'boot_cmdline')
                if any(current.get(key) != inventory.get(key) for key in stable):
                    raise HostError('预检后主机配置发生变化，请重新核对')
                transaction.commit(plan, target, hashes)
                host.run(['reboot'])
                submitted = True
                console.say('已提交一次性安装启动并请求重启；尚未验证目标系统安装及远端登录。')
                return 0
            finally:
                if not submitted:
                    if transaction:
                        try:
                            transaction.rollback()
                        except Exception:
                            console.say('危险：撤销启动改动失败，不要重启！使用控制台恢复：')
                            console.say(f'cp -- {work}/grub.cfg.before {transaction.cfg}; cp -- {work}/grubenv.before {transaction.env}; rm -- {transaction.entry}')
                            console.say('保留了本次私有目录及备份；确认恢复前不要删除。')
                            work = None  # Preserve recovery material, never claim cancellation succeeded.
                            raise HostError('需要人工恢复启动配置')
                    if work:
                        try:
                            shutil.rmtree(work)
                        except OSError:
                            console.say(f'警告：私有材料清理失败；请在控制台检查并删除 {work}（含认证配置）。')
                            raise HostError('清理未完成')
    except (HostError, EOFError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        # Do not print subprocess output or credentials; errors have bounded messages.
        reason = str(exc) if isinstance(exc, HostError) or (isinstance(exc, ValueError) and str(exc).startswith('无法安全生成重装配置：')) else '输入结束或必需操作失败'
        console.say('已停止：' + reason + '。未宣称安装完成。')
        return 1
    finally:
        for name, handler in previous_handlers.items():
            signal.signal(name, handler)


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Debian/Ubuntu 认证重装；请从 k dd 菜单进入')
    parser.add_argument('--distro', choices=('debian', 'ubuntu'), required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--ssh-ports', required=True)
    args = parser.parse_args()
    try:
        ports = [int(port) for port in args.ssh_ports.split(',')]
    except ValueError:
        parser.error('SSH ports must be comma-separated integers')
    os.umask(0o077)
    return run(InstallerHost(), Console(), args.distro, args.version, ports)


if __name__ == '__main__':
    sys.exit(main())
