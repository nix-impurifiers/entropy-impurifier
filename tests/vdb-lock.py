# SPDX-License-Identifier: MIT
"""Exercise native Portage locks across nesting and process boundaries."""
import os
import subprocess
import sys

from entropy.client.interfaces import Client

client = Client()
spm = client.Spm()
probe = '''
import os
import sys
import portage.locks
from portage.exception import TryAgain
try:
    token = portage.locks.lockdir(sys.argv[1], flags=os.O_NONBLOCK)
except TryAgain:
    sys.exit(73)
else:
    portage.locks.unlockdir(token)
'''

def check(expected):
    result = subprocess.run(
        [sys.executable, '-c', probe, spm._get_vdb_path()],
        env=os.environ.copy(), timeout=15,
    )
    assert result.returncode == expected, (result.returncode, expected)

with spm._PortageVdbLocker(spm):
    check(73)
    with spm._PortageVdbLocker(spm):
        check(73)
    check(73)
check(0)
client.shutdown()
