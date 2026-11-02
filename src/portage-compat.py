# SPDX-License-Identifier: MIT
"""Keep Entropy's UID assignment on the installed Portage counter API."""
import inspect


def counter_tick(dbapi, root, package):
    method = dbapi.counter_tick
    parameters = inspect.signature(method).parameters
    kwargs = {}
    if 'myroot' in parameters:
        kwargs['myroot'] = root
    elif 'root' in parameters:
        kwargs['root'] = root
    if 'mycpv' in parameters:
        kwargs['mycpv'] = package
    return method(**kwargs)
