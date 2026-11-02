#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Run native Entropy transactions using writable local package copies."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def main():
    if os.geteuid() != 0:
        raise ValueError('native Entropy requires root')
    for key in ('ROOT', 'DESTDIR', 'ETP_ROOT'):
        if os.environ.get(key, '/') not in ('', '/'):
            raise ValueError('native Entropy requires the live host root')
    args = sys.argv[1:]
    status = 0
    if args and args[0] == 'install' and len(args) > 1:
        with tempfile.TemporaryDirectory(prefix='entropy-impurifier-') as directory:
            copies = []
            for index, value in enumerate(args[1:]):
                source = Path(value).resolve(strict=True)
                if not source.is_file() or not source.name.endswith('.tbz2'):
                    raise ValueError('install requires native .tbz2 archive paths')
                target = Path(directory) / str(index) / source.name
                target.parent.mkdir()
                shutil.copyfile(source, target)
                copies.append(str(target))
            status = subprocess.run(['equo', 'install', *copies], stdin=subprocess.DEVNULL).returncode
    elif args and args[0] == 'remove' and len(args) > 1:
        if any(not re.fullmatch(r'[a-z0-9+._-]+/[a-z0-9+._-]+', value) for value in args[1:]):
            raise ValueError('remove requires category/package identities')
        status = subprocess.run(['equo', 'remove', *args[1:]], stdin=subprocess.DEVNULL).returncode
    elif args != ['reconcile']:
        raise ValueError('use install ARCHIVE...; remove CATEGORY/PACKAGE...; or reconcile')
    activation = subprocess.run(['/usr/sbin/entropy-impurifier-activate']).returncode
    return status or activation


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print('entropy-impurifier: ' + str(error), file=sys.stderr)
        sys.exit(1)
