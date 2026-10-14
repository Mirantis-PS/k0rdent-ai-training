#!/usr/bin/env python3
"""Read-only P0/P1 preservation and local navigation checks. No provisioning."""
import hashlib
import json
import re
import subprocess
import sys
import unicodedata
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def prose(text):
    result, fence = [], None
    for line in text.splitlines():
        clean = re.sub(r'^(?:\s*> ?)+', '', line)
        match = re.match(r'^\s*(\x60{3,}|~{3,})', clean)
        if match:
            marker = match[1][0]
            if fence is None:
                fence = marker
            elif fence == marker:
                fence = None
            result.append('')
        else:
            result.append('' if fence else line)
    return '\n'.join(result)


def anchors(text):
    result, counts = set(), {}
    for line in prose(text).splitlines():
        match = re.match(r'^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$', line)
        if not match:
            continue
        title = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', match[1])
        title = re.sub(r'<[^>]+>', '', title).lower()
        slug = ''.join(c for c in title if c in '_- ' or unicodedata.category(c)[0] in 'LNM').replace(' ', '-')
        count = counts.get(slug, 0)
        result.add(slug + (f'-{count}' if count else ''))
        counts[slug] = count + 1
    result.update(re.findall(r'\b(?:id|name)=[\"\x27]([^\"\x27]+)[\"\x27]', text))
    return result


def code_blocks(text):
    blocks, current, marker = [], None, None
    for line in text.splitlines():
        clean = re.sub(r'^(?:\s*> ?)+', '', line)
        match = re.match(r'^\s*(\x60{3,}|~{3,})(.*)$', clean)
        if match:
            if current is None:
                marker, current = match[1][0], [match[2]]
            elif marker == match[1][0]:
                blocks.append('\n'.join(current))
                current, marker = None, None
        elif current is not None:
            current.append(clean)
    return blocks


def main():
    inventory = json.loads((ROOT/'curriculum/migration/source-inventory.json').read_text())
    rows, errors = inventory['files'], []
    baseline = inventory['source_commit']
    original = set(git('ls-tree', '-r', '--name-only', '-z', baseline).decode().split('\0')) - {''}
    recorded = [r['source_path'] for r in rows]
    if set(recorded) != original or len(recorded) != len(original):
        errors.append('Source inventory is not a one-to-one account of the baseline tree')
    destinations = [r['destination_path'] for r in rows]
    if len(destinations) != len(set(destinations)):
        errors.append('Duplicate canonical destinations')
    path_changes = sorted(((r['source_path'], r['destination_path']) for r in rows
                           if r['source_path'] != r['destination_path'] and '/' in r['source_path']),
                          key=lambda pair: -len(pair[0]))
    code_count = 0
    for row in rows:
        src, dst = row['source_path'], row['destination_path']
        try:
            old = git('show', f'{baseline}:{src}')
            moved = git('show', f"{row['relocation_commit']}:{dst}")
            current = (ROOT/dst).read_bytes()
            if sha(old) != row['source_digest'] or moved != old:
                errors.append(f'{dst}: source/relocation digest mismatch')
            if sha(current) != row['current_digest']:
                errors.append(f'{dst}: differs from reviewed P1 digest')
            if src.endswith('.md') and src != 'scripts/README.md':
                # Runtime snippets must be identical except explicit repository-path repairs.
                expected = old.decode()
                for before, after in path_changes:
                    expected = expected.replace(before, after)
                before_blocks, after_blocks = code_blocks(expected), code_blocks(current.decode())
                code_count += len(before_blocks)
                if before_blocks != after_blocks:
                    errors.append(f'{dst}: code fences changed beyond repository paths')
        except (OSError, subprocess.CalledProcessError) as exc:
            errors.append(f'{dst}: {exc}')
    ids = {r['historical_id'] for r in rows}
    required = {f'1.{n}' for n in range(1, 10)} | {f'5.{n}' for n in range(1, 20)}
    if not required <= ids:
        errors.append('Missing historical Week 1/5 lab ID')
    files = [p for p in git('ls-files', '-z').decode().split('\0') if p.endswith('.md')]
    links = remote_paths = 0
    for filename in files:
        text = (ROOT/filename).read_text()
        # Archived design input retains its historical remote references byte-for-byte.
        if filename.startswith('docs/curriculum-v2/reference/') or filename.startswith('docs/curriculum-v2/handoff/'):
            continue
        for target in re.findall(r'\]\(([^\n)]+)\)', prose(text)):
            target = target.strip('<>')
            if re.match(r'[a-zA-Z][\w+.-]*:', target) or '$' + '{' in target:
                continue
            filepart, _, fragment = target.partition('#')
            dest = ROOT/filepart.lstrip('/') if filepart.startswith('/') else ROOT/Path(filename).parent/unquote(filepart)
            if not filepart:
                dest = ROOT/filename
            links += 1
            if not dest.exists():
                errors.append(f'{filename}: missing local target {target}')
            elif fragment and dest.is_file() and dest.suffix == '.md':
                if unquote(fragment) not in anchors(dest.read_text()):
                    errors.append(f'{filename}: missing heading target {target}')
        # Inspect repository URLs inside commands too; do not imply remote availability.
        for match in re.finditer(r'https://(?:raw\.githubusercontent\.com/Mirantis-PS/k0rdent-ai-training/[^/]+/|github\.com/Mirantis-PS/k0rdent-ai-training/(?:blob|tree)/[^/]+/)([^\s\"\x27<>\x60)]+)', text):
            target = unquote(match[1].split('#')[0].split('?')[0])
            remote_paths += 1
            if not (ROOT/target).exists():
                errors.append(f'{filename}: repository URL has missing local path {target}')
    matrix = (ROOT/'docs/curriculum-v2/COVERAGE-MATRIX.md').read_text()
    if len(re.findall(r'^\| C\d\d \|', matrix, re.M)) != 40:
        errors.append('Coverage matrix must retain all 40 requirements')
    for error in errors:
        print(error, file=sys.stderr)
    print(f'{len(rows)} sources preserved; {code_count} source code fences checked; '
          f'{links} local links/images/anchors; {remote_paths} repository URL paths; {len(errors)} errors.')
    print('Static evidence only. External URL availability, product compatibility and live GPU execution are separate.')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
