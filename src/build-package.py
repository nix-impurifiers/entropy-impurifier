#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Emit native Entropy tar/XPAK/SQLite packages using upstream format APIs."""
import bz2
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tarfile

from entropy.const import etpConst
from entropy.db.sqlite import EntropySQLiteRepository
from entropy.dep import create_package_relative_path
from entropy.spm.plugins.interfaces.portage_plugin import xpak
from entropy.tools import aggregate_entropy_metadata


def build(payload, output, spec):
    name, version = spec['name'], spec['version']
    category = spec.get('category', 'app-impurifiers')
    revision = spec.get('revision', 0)
    filename = create_package_relative_path(category, name, version, '', revision=revision)
    target = output / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    content = {}
    safety = {}
    with tarfile.open(target, 'w:bz2', format=tarfile.PAX_FORMAT) as archive:
        for path in sorted(payload.rglob('*')):
            relative = str(path.relative_to(payload))
            native = '/' + relative
            info = archive.gettarinfo(str(path), relative)
            info.uid = info.gid = 0
            info.uname = info.gname = ''
            info.mtime = 1
            if path.is_symlink():
                content[native] = 'sym'
            elif path.is_dir():
                content[native] = 'dir'
                info.mode = 0o755
            elif path.is_file():
                content[native] = 'obj'
                info.mode |= stat.S_IWUSR
                safety[native] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'mtime': 1.0}
            else:
                raise ValueError('unsupported native payload entry: ' + native)
            if info.isfile():
                with path.open('rb') as stream:
                    archive.addfile(info, stream)
            else:
                archive.addfile(info)
    dependencies = spec.get('dependencies', [])
    xdata = {
        'CATEGORY': category, 'PF': name + '-' + version, 'PN': name,
        'PV': version, 'PVR': version, 'PR': 'r0', 'SLOT': '0',
        'EAPI': '8', 'DEFINED_PHASES': '-', 'CHOST': 'x86_64-pc-linux-gnu',
        'LICENSE': spec.get('license', 'MIT'), 'KEYWORDS': 'amd64',
        'RDEPEND': ' '.join(dependencies), 'DEPEND': '', 'BDEPEND': '',
        'BUILD_TIME': '1', 'COUNTER': '0', 'repository': 'impurifiers',
        'IUSE': '', 'USE': '', 'DESCRIPTION': spec.get('description', name),
    }
    encoded = {key.encode(): (value + '\n').encode() for key, value in xdata.items()}
    encoded[b'environment.bz2'] = bz2.compress(b'EAPI=8\n')
    xpak.tbz2(str(target)).recompose_mem(xpak.xpak_mem(encoded))
    metadata = {
        'category': category, 'name': name, 'version': version, 'revision': revision,
        'versiontag': '', 'slot': '0', 'branch': 'impurifiers',
        'license': spec.get('license', 'MIT'), 'licensedata': {},
        'description': spec.get('description', name),
        'homepage': 'https://github.com/nix-impurifiers/entropy-impurifier',
        'download': filename,
        'chost': 'x86_64-pc-linux-gnu', 'cflags': '', 'cxxflags': '',
        'config_protect': '/etc', 'config_protect_mask': '',
        'trigger': spec.get('trigger', '').encode('utf-8'), 'etpapi': int(etpConst['etpapi']),
        'pkg_dependencies': tuple((dep, etpConst['dependency_type_ids']['rdepend_id']) for dep in dependencies),
        'conflicts': set(spec.get('conflicts', [])), 'provide_extended': set(),
        'sources': set(), 'useflags': set(), 'keywords': {'amd64'},
        'mirrorlinks': [], 'needed_libs': [], 'provided_libs': [],
        'content': content, 'content_safety': safety, 'counter': -1,
        'injected': False, 'systempackage': False, 'spm_phases': '',
        'spm_repository': 'impurifiers', 'signatures': {},
        'digest': hashlib.md5(target.read_bytes()).hexdigest(),
        'size': target.stat().st_size, 'datecreation': '1',
        'disksize': sum(path.stat().st_size for path in payload.rglob('*') if path.is_file() and not path.is_symlink()),
    }
    database = output / 'package.db'
    repo = EntropySQLiteRepository(dbFile=str(database), name='impurifiers', direct=True)
    repo.initializeRepository()
    package_id = repo.addPackage(metadata)
    repo.commit()
    # Exercise the native metadata reader before embedding the database.
    assert repo.retrieveName(package_id) == name
    assert repo.retrieveVersion(package_id) == version
    repo.close()
    aggregate_entropy_metadata(str(target), str(database))
    database.unlink()
    print(target)


if __name__ == '__main__':
    build(Path(sys.argv[1]), Path(sys.argv[2]), json.loads(Path(sys.argv[3]).read_text()))
