"""Build locally from an owned DSH archive; never downloads or installs anything."""
import argparse
import copy
import hashlib
import json
import pathlib
import struct

ROOT = pathlib.Path(__file__).resolve().parent.parent


def leaves(tree, prefix=''):
    for name, entry in tree['files'].items():
        path = prefix + name
        if 'files' in entry:
            yield from leaves(entry, path + '/')
        else:
            yield path, entry


def build(source, output):
    if source.resolve() == output.resolve():
        raise ValueError('Never overwrite the source archive while building')
    spec = json.loads((ROOT / 'adapter/changes.json').read_text(encoding='utf8'))
    with source.open('rb') as src:
        _, header_size, _, json_size = struct.unpack('<4I', src.read(16))
        header = json.loads(src.read(json_size))
        old_entries = dict(leaves(copy.deepcopy(header)))

        def read_entry(path):
            e = old_entries[path]
            src.seek(8 + header_size + int(e['offset']))
            data = src.read(e['size'])
            if len(data) != e['size']:
                raise EOFError(path)
            return data

        if json.loads(read_entry('package.json'))['version'] != spec['desktopVersion']:
            raise ValueError('Unsupported desktop version; no archive written')
        replacements = {}
        for change in spec['changes']:
            data = read_entry(change['path'])
            if hashlib.sha256(data).hexdigest() != change['sha256']:
                raise ValueError('Unsupported or already patched file: ' + change['path'])
            text = data.decode('utf8')
            for edit in change['edits']:
                if text.count(edit['old']) != 1:
                    raise ValueError('Patch context not unique: ' + change['path'])
                text = text.replace(edit['old'], edit['new'], 1)
            patched = text.encode('utf8')
            if hashlib.sha256(patched).hexdigest() != change['resultSha256']:
                raise ValueError('Result hash mismatch: ' + change['path'])
            replacements[change['path']] = patched
        replacements['lib/conversation-windows.mjs'] = (ROOT / 'adapter/conversation-windows.mjs').read_bytes()
        header['files']['lib']['files']['conversation-windows.mjs'] = {}
        offset = 0
        for path, entry in leaves(header):
            if entry.get('unpacked') or 'link' in entry:
                continue
            if path in replacements:
                data = replacements[path]
                block_size = 4194304
                entry['size'] = len(data)
                entry['integrity'] = {
                    'algorithm': 'SHA256', 'hash': hashlib.sha256(data).hexdigest(),
                    'blockSize': block_size,
                    'blocks': [hashlib.sha256(data[i:i+block_size]).hexdigest() for i in range(0, len(data), block_size)]}
            entry['offset'] = str(offset)
            offset += entry['size']
        encoded = json.dumps(header, separators=(',', ':'), ensure_ascii=False).encode('utf8')
        packed = struct.pack('<II', 4 + len(encoded) + (-len(encoded)) % 4, len(encoded)) + encoded + b'\0' * ((-len(encoded)) % 4)
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open('wb') as dst:
            dst.write(struct.pack('<II', 4, len(packed)))
            dst.write(packed)
            for path, entry in leaves(header):
                if entry.get('unpacked') or 'link' in entry:
                    continue
                if path in replacements:
                    dst.write(replacements[path])
                else:
                    old = old_entries[path]
                    src.seek(8 + header_size + int(old['offset']))
                    remaining = old['size']
                    while remaining:
                        chunk = src.read(min(remaining, 4194304))
                        if not chunk:
                            raise EOFError(path)
                        dst.write(chunk)
                        remaining -= len(chunk)
    # Ignored local test artifact, never distributed in the repository.
    (ROOT / 'build').mkdir(exist_ok=True)
    (ROOT / 'build/workspace-client.js').write_bytes(replacements['dsh/node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js'])
    print('Built locally: ' + str(output))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'build/app.conversation-window.asar')
    args = parser.parse_args()
    build(args.source, args.output)
