"""Register Swift sources while preserving existing signing, targets and schemes."""
import hashlib
import os
import plistlib
import subprocess
from pathlib import Path

os.chdir(Path(__file__).resolve().parent.parent)
project = Path('NotesApp.xcodeproj/project.pbxproj')
data = plistlib.loads(subprocess.check_output(['plutil', '-convert', 'xml1', '-o', '-', str(project)]))
objects = data['objects']
main = next(v for v in objects.values() if v['isa'] == 'PBXProject')['mainGroup']
uid = lambda value: hashlib.sha1(value.encode()).hexdigest()[:24].upper()
for directory, target_name in [('NotesApp', 'NotesApp'), ('NotesAppDeviceTests', 'NotesAppDeviceTests')]:
    target = next(v for v in objects.values() if v['isa'] == 'PBXNativeTarget' and v['name'] == target_name)
    phase = next(objects[key] for key in target['buildPhases'] if objects[key]['isa'] == 'PBXSourcesBuildPhase')
    for file in sorted(Path(directory).rglob('*.swift')):
        path = str(file)
        ref = next((k for k, v in objects.items() if v['isa'] == 'PBXFileReference' and v.get('path') == path), None)
        if ref is None:
            ref = uid(path)
            objects[ref] = dict(isa='PBXFileReference', lastKnownFileType='sourcecode.swift', path=path, sourceTree='SOURCE_ROOT')
            objects[main]['children'].append(ref)
        build = next((k for k, v in objects.items() if v['isa'] == 'PBXBuildFile' and v.get('fileRef') == ref), None)
        if build is None:
            build = uid(path + 'build')
            objects[build] = dict(isa='PBXBuildFile', fileRef=ref)
        # A source belongs to its intended target, regardless of PBX dictionary ordering.
        for value in objects.values():
            if value['isa'] == 'PBXSourcesBuildPhase' and value is not phase:
                value['files'] = [key for key in value['files'] if key != build]
        if build not in phase['files']:
            phase['files'].append(build)
# Register the bundled cover atlas as a real compiled asset catalog.
app = next(v for v in objects.values() if v['isa'] == 'PBXNativeTarget' and v['name'] == 'NotesApp')
resources = next(objects[key] for key in app['buildPhases'] if objects[key]['isa'] == 'PBXResourcesBuildPhase')
path = 'NotesApp/Resources/Assets.xcassets'
ref = next((k for k, v in objects.items() if v['isa'] == 'PBXFileReference' and v.get('path') == path), None)
if ref is None:
    ref = uid(path)
    objects[ref] = dict(isa='PBXFileReference', lastKnownFileType='folder.assetcatalog', path=path, sourceTree='SOURCE_ROOT')
    objects[main]['children'].append(ref)
build = next((k for k, v in objects.items() if v['isa'] == 'PBXBuildFile' and v.get('fileRef') == ref), None)
if build is None:
    build = uid(path + 'build')
    objects[build] = dict(isa='PBXBuildFile', fileRef=ref)
if build not in resources['files']:
    resources['files'].append(build)
project.write_bytes(plistlib.dumps(data, sort_keys=False))
