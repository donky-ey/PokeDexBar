#!/usr/bin/env python3
"""Exercise release packaging failures without Apple credentials or network access."""
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
MOCK = r'''#!/bin/bash
set -eu
tool=$(basename "$0")
echo "$tool $*" >> "$EVENTS"
case "$tool" in
  codesign) [[ "$FAIL_AT" != signature ]] ;;
  xcrun)
    if [[ "$1 $2" == 'notarytool submit' ]]; then
      [[ "$FAIL_AT" != network ]] || exit 1
      status=Accepted
      [[ "$FAIL_AT" != rejected ]] || status=Invalid
      printf '<?xml version="1.0"?><plist version="1.0"><dict><key>status</key><string>%s</string></dict></plist>\n' "$status"
    elif [[ "$1 $2" == 'stapler staple' ]]; then
      [[ "$FAIL_AT" != staple ]] || exit 1
    else
      [[ "$FAIL_AT" != ticket ]] || exit 1
    fi ;;
  spctl)
    [[ "$FAIL_AT" != gatekeeper ]] || exit 1
    if [[ "$*" == *extracted* ]]; then
      [[ "$FAIL_AT" != archive ]] || exit 1
    fi ;;
  ditto)
    if [[ "$1" == '-c' ]]; then
      touch "${@: -1}"
    else
      mkdir -p "${@: -1}/PokeDexBar.app"
    fi ;;
esac
'''


class NotarizationTests(unittest.TestCase):
    def test_apple_tool_accepts_the_requirement_expression(self):
        # Unlike mocked commands, Apple's parser catches a missing '=' prefix.
        script = (ROOT / 'scripts/notarize-app.sh').read_text()
        line = next(line for line in script.splitlines() if ' -R ' in line)
        args = shlex.split(line)
        requirement = args[args.index('-R') + 1]
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                ['/usr/bin/csreq', '-r', requirement, '-b', f'{directory}/requirement'],
                capture_output=True, text=True,
            )
        self.assertEqual(result.returncode, 0, result.stderr)

    def run_pipeline(self, failure):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            (root / 'build/PokeDexBar.app').mkdir(parents=True)
            (root / 'bin').mkdir()
            archive = root / 'build/PokeDexBar.zip'
            archive.write_text('stale unnotarized archive')
            shutil.copy2(ROOT / 'scripts/notarize-app.sh', root / 'scripts')
            for name in ('codesign', 'xcrun', 'spctl', 'ditto'):
                path = root / 'bin' / name
                path.write_text(MOCK)
                path.chmod(0o755)
            events = root / 'events'
            result = subprocess.run(
                ['bash', str(root / 'scripts/notarize-app.sh')],
                env={**os.environ, 'PATH': f'{root}/bin:/usr/bin:/bin',
                     'FAIL_AT': failure, 'EVENTS': str(events)},
                capture_output=True, text=True,
            )
            return result, archive.exists(), events.read_text()

    def test_each_failure_removes_stale_archive_and_stops_packaging(self):
        for stage in ('signature', 'network', 'rejected', 'staple', 'ticket',
                      'gatekeeper', 'archive'):
            with self.subTest(stage=stage):
                result, exists, _ = self.run_pipeline(stage)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(exists)

    def test_success_packages_after_stapling_and_checks_extracted_app(self):
        result, exists, events = self.run_pipeline('none')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(exists)
        self.assertLess(events.index('stapler staple'), events.index('/release.zip'))
        self.assertIn('spctl --assess --type execute --verbose=4', events)
        self.assertIn('/extracted/PokeDexBar.app', events)


if __name__ == '__main__':
    unittest.main()
