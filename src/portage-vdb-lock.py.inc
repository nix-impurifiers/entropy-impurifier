    # Replacement lock wrapper supplied by nix-impurifiers. Original patch: MIT.
    # Keep one native lock per VDB path, shared across nested wrapper instances.
    class _PortageVdbLocker(object):
        _gate = threading.RLock()
        _held = {}

        def __init__(self, parent, root=None):
            self._path = parent._get_vdb_path(root=root)
            self._parent = parent
            self._root = root

        def __enter__(self):
            cls = type(self)
            cls._gate.acquire()
            try:
                current = cls._held.get(self._path)
                if current is None:
                    dbapi = self._parent._get_portage_vartree(self._root).dbapi
                    if hasattr(dbapi, "lock") and hasattr(dbapi, "unlock"):
                        dbapi.lock()
                        token = ("dbapi", dbapi)
                    else:
                        token = ("legacy", self._parent._portage.locks.lockdir(self._path))
                    cls._held[self._path] = (token, 1)
                else:
                    token, depth = current
                    cls._held[self._path] = (token, depth + 1)
            except BaseException:
                cls._gate.release()
                raise
            return self

        def __exit__(self, exc_type, exc_value, traceback):
            cls = type(self)
            try:
                token, depth = cls._held[self._path]
                if depth == 1:
                    try:
                        if token[0] == "dbapi":
                            token[1].unlock()
                        else:
                            self._parent._portage.locks.unlockdir(token[1])
                    finally:
                        del cls._held[self._path]
                else:
                    cls._held[self._path] = (token, depth - 1)
            finally:
                cls._gate.release()

