"""Backport Flutter's official simulator log-reader race fix to the pinned SDK.

Upstream: flutter/flutter#193142, commit c3ed85ef987759ee54a6bce275490cde2a238dc1.
Only test-tool discovery is patched; the app and Flutter engine are unchanged.
"""
import hashlib,pathlib,subprocess,sys

sdk=pathlib.Path(sys.argv[1]).resolve()
patch=pathlib.Path(__file__).with_name('flutter-ios-log-reader.patch').resolve()
# Normalize Git's Windows checkout line endings, then verify the audited patch.
content=patch.read_bytes().replace(b'\r\n',b'\n')
assert hashlib.sha256(content).hexdigest()=='2d735c5820914dce7c74a64abeea121fa30e614772edfd9aea32e002c7c5a9c9'
patch.write_bytes(content)
command=['git','-C',str(sdk),'apply','--include=packages/flutter_tools/lib/src/ios/simulators.dart']
subprocess.run([*command,'--check',str(patch)],check=True)
subprocess.run([*command,str(patch)],check=True)
for name in ('flutter_tools.snapshot','flutter_tools.stamp'):
    path=sdk/'bin/cache'/name
    assert path.resolve().is_relative_to(sdk)
    path.unlink(missing_ok=True)
print('Applied upstream iOS simulator log-reader fix; the tool snapshot will be rebuilt.')
