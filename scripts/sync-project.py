"""Add new source/resource references without modifying any Xcode build/signing settings."""
from pathlib import Path
import hashlib, re
root = Path(__file__).resolve().parent.parent
project = root / 'LifePreserver.xcodeproj/project.pbxproj'
text = project.read_text()
before_settings = text[text.index('/* Begin XCBuildConfiguration section */'):]
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def insert(section, value):
    global text
    marker = f'/* End {section} section */'
    text = text.replace(marker, value + marker, 1)
for path in sorted((root/'Sources').rglob('*.swift')) + [root/'Sources/LifePreserver/Assets']:
    name = str(path.relative_to(root))
    if f'path = {name};' in text: continue
    kind = 'Resources' if path.is_dir() else 'Sources'
    ref, build = uid('file:'+name), uid('build:'+name)
    filetype = 'folder' if path.is_dir() else 'sourcecode.swift'
    insert('PBXBuildFile', f'\t\t{build} /* {name} in {kind} */ = {{isa = PBXBuildFile; fileRef = {ref}; }};\n')
    insert('PBXFileReference', f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {filetype}; path = {name}; sourceTree = "<group>"; }};\n')
    text = re.sub(r'(isa = PBXGroup;\s*children = \()', lambda m: m[0]+f'\n\t\t\t\t{ref} /* {name} */,', text, count=1)
    text = re.sub(r'(isa = PBX'+kind+r'BuildPhase;.*?files = \()', lambda m: m[0]+f'\n\t\t\t\t{build} /* {name} in {kind} */,', text, count=1, flags=re.S)
assert before_settings == text[text.index('/* Begin XCBuildConfiguration section */'):]
project.write_text(text)
print('Project sources synchronized; all build and signing settings preserved.')
