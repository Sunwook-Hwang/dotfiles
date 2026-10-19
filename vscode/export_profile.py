#!/usr/bin/env python3
"""Build an importable VS Code profile from repository files and portable UI state."""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
PROFILE = ROOT / 'FLASH.code-profile'
PINNED = {
    'workbench.activity.pinnedViewlets2',
    'workbench.auxiliarybar.pinnedPanels',
    'workbench.panel.pinnedPanels',
}
LAYOUT = {
    'workbench.sideBar.position', 'workbench.sideBar.size',
    'workbench.panel.alignment', 'workbench.panel.size',
    'workbench.panel.lastNonMaximizedHeight', 'workbench.panel.lastNonMaximizedWidth',
    'workbench.activityBar.hidden', 'workbench.activityBar.location',
}
ID = re.compile(r'^[\w.:-]+$', re.ASCII)
VIEW_STATE = re.compile(r'^workbench\.(?:view\.[\w.-]+|views\.service\.sidebar\.[\w.-]+|explorer\.views|scm\.views)\.state\.hidden$')


def user_dir():
    if os.environ.get('VSCODE_USER_DIR'):
        return Path(os.environ['VSCODE_USER_DIR']).expanduser()
    if sys.platform == 'darwin':
        return Path.home() / 'Library/Application Support/Code/User'
    if sys.platform == 'win32':
        return Path(os.environ['APPDATA']) / 'Code/User'
    return Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'Code/User'


def safe_id(value):
    return isinstance(value, str) and bool(ID.fullmatch(value)) and not value.startswith('status.workspaceTrust.')


def portable(key, value):
    """Whitelist fields as well as keys; remote authority IDs and paths are excluded."""
    if key == 'workbench.statusbar.hidden':
        if not isinstance(value, list):
            raise ValueError('Invalid status bar visibility list.')
        return [item for item in value if safe_id(item)]
    if key in PINNED or VIEW_STATE.fullmatch(key):
        if not isinstance(value, list):
            raise ValueError(f'Invalid view list: {key}')
        fields = ('id', 'pinned', 'visible', 'order') if key in PINNED else ('id', 'isHidden')
        return [{field: item[field] for field in fields if field in item and
                 (field == 'id' or type(item[field]) is (int if field == 'order' else bool))}
                for item in value if isinstance(item, dict) and safe_id(item.get('id'))]
    if key == 'views.customizations':
        return {name: {k: v for k, v in value.get(name, {}).items()
                       if safe_id(k) and (safe_id(v) if isinstance(v, str) else type(v) in (int, bool))}
                for name in ('viewContainerLocations', 'viewLocations', 'viewContainerBadgeEnablementStates')}
    if key in LAYOUT and (type(value) in (int, float, bool) or value in ('left', 'right', 'top', 'bottom', 'center', 'justify', 'default', 'hidden')):
        return value
    raise ValueError(f'Unsupported UI state: {key}')


def read_db(path):
    with closing(sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True)) as db:
        return dict(db.execute('SELECT key, value FROM ItemTable'))


def export_profile(directory, output):
    database = directory / 'globalStorage/state.vscdb'
    if not database.is_file():
        raise ValueError(f'No VS Code UI state at {database}; existing profile preserved.')
    values = read_db(database)
    targets = json.loads(values.get('__$__targetStorageMarker', '{}'))
    storage = {}
    for key, raw in sorted(values.items()):
        # Match the native profile export: only profile-scoped, user-target state.
        if targets.get(key) != 0:
            continue
        if key in PINNED | LAYOUT | {'views.customizations', 'workbench.statusbar.hidden'} or VIEW_STATE.fullmatch(key):
            try:
                value = json.loads(raw)
            except json.JSONDecodeError:
                value = raw
            clean = portable(key, value)
            storage[key] = clean if isinstance(clean, str) else json.dumps(clean, separators=(',', ':'))
    if not {'views.customizations', 'workbench.statusbar.hidden'} <= storage.keys():
        raise ValueError('Missing view layout or status bar UI state; existing profile preserved.')
    profile = {
        'name': 'FLASH',
        'settings': json.dumps({'settings': (ROOT / 'user/settings.json').read_text(encoding='utf-8')}),
        'keybindings': json.dumps({'keybindings': (ROOT / 'user/keybindings.json').read_text(encoding='utf-8')}),
        'snippets': json.dumps({'snippets': {p.name: p.read_text(encoding='utf-8')
                                           for p in sorted((ROOT / 'user/snippets').glob('*')) if p.is_file()}}),
        'extensions': json.dumps([{'identifier': {'id': line.strip()}}
                                  for line in (ROOT / 'extensions.txt').read_text().splitlines()
                                  if line.strip() and not line.startswith('#')]),
        'globalState': json.dumps({'storage': storage}),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=output.parent, prefix='.code-profile-')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(profile, stream, indent=2, ensure_ascii=False)
            stream.write('\n')
        os.chmod(temporary, 0o644)
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f'VS Code profile exported: {output} ({len(storage)} UI preferences)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--user-dir', type=Path, default=user_dir())
    parser.add_argument('--output', type=Path, default=PROFILE)
    args = parser.parse_args()
    try:
        export_profile(args.user_dir, args.output)
    except (OSError, ValueError, TypeError, sqlite3.Error) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
