# SPDX-License-Identifier: MIT
# Executed by Entropy's native Python trigger sandbox.
from entropy.const import etpConst
import os
from pathlib import Path
import subprocess

my_ext_status = 0
if etpConst['systemroot'] not in ('', '/'):
    my_ext_status = 1
elif stage in ('postinstall', 'postremove'):
    upgrading = False
    if stage == 'postremove':
        pid = os.getpid()
        seen = set()
        while pid > 1 and pid not in seen:
            seen.add(pid)
            try:
                command = Path('/proc/%s/cmdline' % pid).read_bytes().split(b'\0')
                names = [os.fsdecode(arg) for arg in command if arg]
                native_client = False
                for arg in names[:3]:
                    if Path(arg).name in ('equo', 'equo.py'):
                        native_client = True
                if native_client:
                    for arg in names[1:]:
                        if arg in ('install', 'upgrade', 'i', 'u'):
                            upgrading = True
                    break
                pid = int(Path('/proc/%s/stat' % pid).read_text().rsplit(')', 1)[1].split()[1])
            except (OSError, ValueError, IndexError):
                break
    if not upgrading and Path('/usr/sbin/entropy-impurifier-activate').is_file():
        my_ext_status = subprocess.call(['/usr/sbin/entropy-impurifier-activate'])
