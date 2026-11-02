# SPDX-License-Identifier: MIT
"""Initialize an empty fixture database using the native installed repository."""
from pathlib import Path
from entropy.const import etpConst
from entropy.client.interfaces.db import InstalledPackagesRepository

path = Path(etpConst['etpdatabaseclientfilepath'])
path.parent.mkdir(parents=True, exist_ok=True)
repository = InstalledPackagesRepository(dbFile=str(path), direct=True)
repository.initializeRepository()
repository.commit()
repository.close()
