#!/usr/bin/env python3
"""Check catalog parity, source coverage and printf/interpolation placeholders."""
from pathlib import Path
import subprocess, json, re
root = Path(__file__).resolve().parent.parent
catalogs = {}
for lang in ('en', 'zh-Hans', 'zh-Hant'):
    path = root / 'Sources/CECCore/Resources' / (lang + '.lproj/Localizable.strings')
    catalogs[lang] = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))
base = catalogs['zh-Hans']
pattern = r'%(?:@|(?:0?\d*)[dXu])'
for lang, strings in catalogs.items():
    assert strings.keys() == base.keys(), f'{lang}: mismatched keys'
    for key, value in strings.items():
        assert value.strip(), f'{lang}: empty translation for {key}'
        assert re.findall(pattern, key) == re.findall(pattern, value), f'{lang}: placeholder mismatch: {key}'
for directory in ('App', 'Sources', 'CLI'):
    for path in (root / directory).rglob('*.swift'):
        for quoted in re.findall(r'\bL\(("(?:\\.|[^"\\])*")', path.read_text()):
            key = json.loads(quoted)
            assert key in base, f'Missing key in {path}: {key}'
print(f'PASS: {len(base)} keys in all three languages; source coverage and placeholders match')
