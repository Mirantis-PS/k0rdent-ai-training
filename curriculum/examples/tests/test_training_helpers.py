"""Exercise helper boundaries without a GPU cluster or external network."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]

class TrainingHelpersTests(unittest.TestCase):
    def test_rank_mapping_reaches_child_process(self):
        env = dict(os.environ, OMPI_COMM_WORLD_RANK='9', OMPI_COMM_WORLD_LOCAL_RANK='1',
                   OMPI_COMM_WORLD_SIZE='16', MASTER_ADDR='worker-0')
        result = subprocess.run(['bash', str(ROOT/'distributed-training/run.sh'), 'bash', '-c',
                                 'printf "%s %s %s %s %s" "$RANK" "$LOCAL_RANK" "$WORLD_SIZE" "$MASTER_ADDR" "$MASTER_PORT"'],
                                env=env, capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout, '9 1 16 worker-0 29500')

    def test_missing_rank_fails_before_training(self):
        env = {k:v for k,v in os.environ.items() if not k.startswith('OMPI_')}
        result = subprocess.run(['bash', str(ROOT/'distributed-training/run.sh'), 'echo', 'training-started'],
                                env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('training-started', result.stdout)

    def test_committed_adapter_matches_executed_scripts(self):
        config = yaml.safe_load((ROOT/'distributed-training/mpi-adapters.yaml').read_text())
        for name, content in config['data'].items():
            self.assertEqual(content, (ROOT/'distributed-training'/name).read_text(), name)

    def query(self, responses):
        # Mock only the HTTP boundary. The actual Bash script handles status,
        # plaintext IDs, URL encoding arguments, polling and output persistence.
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            (temp/'responses.json').write_text(json.dumps(responses))
            (temp/'curl').write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p=Path(os.environ['MOCK_HTTP_DIR'])
a=sys.argv[1:]
with (p/'calls.jsonl').open('a') as f: f.write(json.dumps(a)+'\\n')
r=json.loads((p/'responses.json').read_text())
status, body=r.pop(0)
(p/'responses.json').write_text(json.dumps(r))
Path(a[a.index('-o')+1]).write_text(body)
print(status,end='')
''')
            (temp/'sleep').write_text('#!/bin/sh\nexit 0\n')
            for name in ('curl','sleep'):
                (temp/name).chmod(0o755)
            output = temp/'result.txt'
            result = subprocess.run(['bash', str(ROOT/'topology/query-topology.sh'), 'http://fixture', str(output)],
                                    env=dict(os.environ, PATH=str(temp)+os.pathsep+os.environ['PATH'], MOCK_HTTP_DIR=str(temp)),
                                    capture_output=True, text=True, timeout=10)
            calls = [json.loads(line) for line in (temp/'calls.jsonl').read_text().splitlines()]
            return result, output.read_text() if output.exists() else None, calls

    def test_topology_polls_plaintext_uid_and_saves_text(self):
        result, body, calls = self.query([(202, 'request-123'), (202, 'pending'), (200, 'topology generated')])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(body, 'topology generated')
        self.assertEqual(len(calls), 3)
        self.assertIn('uid=request-123', calls[1])
        self.assertIn('--data-urlencode', calls[1])

    def test_topology_rejects_generation_error(self):
        result, body, calls = self.query([(403, 'denied')])
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(body)
        self.assertEqual(len(calls), 1)

    def test_topology_rejects_empty_uid(self):
        result, body, calls = self.query([(202, '')])
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(body)
        self.assertEqual(len(calls), 1)

    def test_topology_rejects_poll_error(self):
        result, body, _ = self.query([(202, 'request-123'), (500, 'generation failed')])
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(body)

if __name__ == '__main__':
    unittest.main()
