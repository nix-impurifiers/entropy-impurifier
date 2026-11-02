# SPDX-License-Identifier: MIT
{ pkgs }:
let
  source = pkgs.fetchFromGitHub {
    owner = "Sabayon";
    repo = "entropy";
    rev = "aeff7dd466be6e0218709d32b03f3aa35cb2b4d8";
    hash = "sha256-ho0nN6hEYYdTRmGKJVXZJpCZZ1qodox6EgW+RZriBlo=";
  };
  python = pkgs.python312;
  package = pkgs.runCommand "native-entropy" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    mkdir -p $out/bin $out/share/licenses/entropy $out/lib/python/_entropy $out/lib/entropy/client $out/lib/entropy/lib/entropy
    cp -r ${source}/lib/entropy $out/lib/python/
    cp -r ${source}/client/solo $out/lib/python/_entropy/
    touch $out/lib/python/_entropy/__init__.py
    chmod -R u+w $out/lib/python
    # Preserve native behavior using current Python API spellings.
    ${python}/bin/python3 - "$out/lib/python" <<'PY'
    from pathlib import Path
    import sys
    for path in Path(sys.argv[1]).rglob('*.py'):
        text = path.read_text()
        updated = text.replace('.isAlive()', '.is_alive()').replace('"rU"', '"r"').replace("'rU'", "'r'")
        if updated != text:
            path.write_text(updated)
    plugin = Path(sys.argv[1]) / 'entropy/spm/plugins/interfaces/portage_plugin/__init__.py'
    text = plugin.read_text()
    start = text.index('    class _PortageVdbLocker(object):')
    end = text.index('    class _PortageWorldSetLocker(object):', start)
    replacement = Path('${../src/portage-vdb-lock.py.inc}').read_text()
    updated = text[:start] + replacement + text[end:]
    updated = updated.replace('import os\n', 'import os\nimport threading\nfrom entropy_impurifier_portage_compat import counter_tick\n', 1)
    old = 'vartree.dbapi.counter_tick(\n                        root, mycpv = package)'
    assert old in updated
    updated = updated.replace(old, 'counter_tick(vartree.dbapi, root, package)')
    plugin.write_text(updated)
    PY
    cp ${../src/portage-compat.py} $out/lib/python/entropy_impurifier_portage_compat.py
    substituteInPlace $out/lib/python/entropy/const.py --replace-fail "'installdir': '/usr/lib/entropy'" "'installdir': '$out/lib/entropy'"
    cp ${source}/client/equo.py $out/lib/entropy/client/equo.py
    cp ${source}/client/revision $out/lib/entropy/client/revision
    cp ${source}/lib/entropy/revision $out/lib/entropy/lib/entropy/revision
    install -m644 ${source}/COPYING $out/share/licenses/entropy/COPYING
    makeWrapper ${python}/bin/python3 $out/bin/equo --add-flags $out/lib/entropy/client/equo.py --prefix PYTHONPATH : $out/lib/python
  '';
in
{
  inherit source python package;
}
