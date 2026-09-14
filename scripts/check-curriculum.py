#!/usr/bin/env python3
"""Check curriculum code fences, local file targets and committed lab fixtures."""
import ast
import re
import subprocess
import sys
import textwrap
from pathlib import Path
from urllib.parse import unquote
import yaml

ROOT = Path(__file__).resolve().parents[1]

def blocks(text):
    current = None
    for number, raw in enumerate(text.splitlines(), 1):
        line = re.sub(r'^(?:\s*> ?)+', '', raw)
        match = re.match(r'^\s*(`{3,}|~{3,})(.*)$', line)
        if match:
            if current is None:
                current = (number, match[1][0], match[2].strip(), [])
            elif match[1][0] == current[1]:
                yield current[0], current[2], textwrap.dedent('\n'.join(current[3]))
                current = None
        elif current:
            current[3].append(line)
    if current:
        raise ValueError(f'unclosed fence at line {current[0]}')

def check_object(obj):
    """Target known API constraints; does not replace versioned CRD validation."""
    if isinstance(obj, dict):
        if 'topologySpreadConstraints' in obj:
            for constraint in obj['topologySpreadConstraints'] or []:
                if isinstance(constraint.get('maxSkew'), int) and constraint['maxSkew'] <= 0:
                    raise ValueError('topologySpreadConstraints.maxSkew must be positive')
        for child in obj.values():
            check_object(child)
    elif isinstance(obj, list):
        for child in obj:
            check_object(child)

def check(path):
    errors = []
    if path.suffix == '.md':
        text = path.read_text()
        try:
            for line, language, code in blocks(text):
                try:
                    if language in ('yaml', 'yml'):
                        list(yaml.safe_load_all(code))
                    elif language == 'python':
                        ast.parse(code)
                    elif language in ('bash', 'sh'):
                        # Validate YAML documents embedded in complete shell heredocs.
                        for m in re.finditer(r'<<-?\s*[\'\"]?([A-Z][A-Z0-9_]*)[\'\"]?[^\n]*\n(.*?)^\s*\1\s*$', code, re.M | re.S):
                            body = textwrap.dedent(m[2])
                            if re.match(r'\s*(?:#.*\n\s*)*apiVersion:', body):
                                list(yaml.safe_load_all(body))
                except (SyntaxError, yaml.YAMLError) as exc:
                    errors.append(f'{path}:{line}: {exc}')
        except ValueError as exc:
            errors.append(f'{path}: {exc}')
        prose = re.sub(r'^\s*(```|~~~).*?^\s*\1\s*$', '', text, flags=re.M | re.S)
        for target in re.findall(r'\]\(([^)]+)\)', prose):
            target = target.split('#')[0].strip('<>')
            if not target or re.match(r'\w+:', target) or target.startswith('/') or '${' in target:
                continue
            if not (path.parent / unquote(target)).exists():
                errors.append(f'{path}: missing local link: {target}')
    elif path.suffix in ('.yaml', '.yml'):
        try:
            for obj in yaml.safe_load_all(path.read_text()):
                check_object(obj)
        except (ValueError, yaml.YAMLError) as exc:
            errors.append(f'{path}: {exc}')
    elif path.suffix == '.py':
        try:
            ast.parse(path.read_text())
        except SyntaxError as exc:
            errors.append(f'{path}: {exc}')
    elif path.suffix == '.sh':
        result = subprocess.run(['bash', '-n', str(path)], capture_output=True, text=True)
        if result.returncode:
            errors.append(result.stderr)
    return errors

def main():
    paths = [Path(p) for p in sys.argv[1:]] or [ROOT/'curriculum/week-1-foundations', ROOT/'curriculum/week-5-ai-workloads', ROOT/'curriculum/examples']
    files = sorted({f for p in paths if p.exists() for f in (p.rglob('*') if p.is_dir() else [p]) if f.is_file()})
    errors = [error for f in files for error in check(f)]
    for error in errors:
        print(error, file=sys.stderr)
    print(f'Checked {len(files)} files; {len(errors)} errors. Live cluster and full CRD validation are separate.')
    return bool(errors)
if __name__ == '__main__':
    sys.exit(main())
