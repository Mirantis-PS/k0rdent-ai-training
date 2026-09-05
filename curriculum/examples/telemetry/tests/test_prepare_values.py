import copy
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'prepare-kof-values.py'
spec = importlib.util.spec_from_file_location('prepare_values', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class CollectorValuesTests(unittest.TestCase):
    def setUp(self):
        self.values = {'opentelemetry-kube-stack': {'collectors': {'daemon': {
            'volumes': [{'name': 'audit', 'hostPath': {'path': '/var/log/kubernetes'}}],
            'volumeMounts': [{'name': 'audit', 'mountPath': '/var/log/kubernetes'}]}}}}
        self.cr = {'metadata': {'name': 'kof-collectors-daemon'}, 'spec': {'config': {
            'receivers': {'otlp': {}, 'filelog/k8s_audit': {}},
            'processors': {'transform/audit': {}, 'batch': {}},
            'service': {'extensions': ['file_storage/audit'], 'pipelines': {
                'logs': {'receivers': ['filelog/k8s_audit'], 'processors': ['transform/audit', 'batch'], 'exporters': ['otlphttp/logs']},
                'metrics': {'receivers': ['otlp'], 'processors': ['batch'], 'exporters': ['prometheusremotewrite']}}}}}}

    def build(self, existing=None):
        return module.prepare(self.values, existing or {}, 'external', 'https://example.com:4318', self.cr)

    def test_preserves_inputs_existing_settings_and_log_transform(self):
        original = copy.deepcopy(self.cr)
        result = self.build({'unrelated': {'keep': True}})
        daemon = result['opentelemetry-kube-stack']['collectors']['daemon']
        self.assertTrue(result['unrelated']['keep'])
        self.assertIn('audit', [v['name'] for v in daemon['volumes']])
        self.assertEqual(daemon['config']['service']['pipelines']['logs/external']['processors'], ['transform/audit', 'batch/external'])
        self.assertEqual(self.cr, original)
        self.assertNotIn('logs', daemon['config']['service']['pipelines'])

    def test_restart_storage_and_credentials_are_separate(self):
        daemon = self.build()['opentelemetry-kube-stack']['collectors']['daemon']
        exporter = daemon['config']['exporters']['otlphttp/external']
        self.assertEqual(exporter['sending_queue']['storage'], 'file_storage/external')
        self.assertEqual(exporter['tls']['key_file'], '/etc/otel/external/tls.key')
        self.assertIn('file_storage/audit', daemon['config']['service']['extensions'])
        self.assertEqual(next(v['secret']['secretName'] for v in daemon['volumes'] if v['name']=='external-tls'), 'kof-external-client')

    def test_rejects_missing_receiver(self):
        del self.cr['spec']['config']['receivers']['filelog/k8s_audit']
        with self.assertRaisesRegex(ValueError, 'undefined receiver'):
            self.build()

    def test_rejects_missing_processor(self):
        del self.cr['spec']['config']['processors']['transform/audit']
        with self.assertRaisesRegex(ValueError, 'undefined processor'):
            self.build()

    def test_rejects_insecure_endpoint(self):
        with self.assertRaisesRegex(ValueError, 'https'):
            module.prepare(self.values, {}, 'external', 'http://example.com', self.cr)

    def test_regeneration_does_not_duplicate_external_pipelines(self):
        existing = self.build()
        self.cr['spec']['config']['service']['pipelines']['logs/external'] = {'receivers':['otlp']}
        result = self.build(existing)
        self.assertNotIn('logs/external/external', result['opentelemetry-kube-stack']['collectors']['daemon']['config']['service']['pipelines'])

    def test_storage_mode_preserves_external_settings(self):
        external = self.build()
        result = module.prepare(self.values, external, 'storage')
        daemon = result['opentelemetry-kube-stack']['collectors']['daemon']
        self.assertEqual({v['name'] for v in daemon['volumes']}, {'audit', 'external-tls', 'external-queue', 'ingest-tls'})
        self.assertEqual({v['name'] for v in daemon['volumeMounts']}, {'audit', 'external-tls', 'external-queue', 'ingest-tls'})
        self.assertIn('otlphttp/external', result['opentelemetry-kube-stack']['collectors']['daemon']['config']['exporters'])

if __name__ == '__main__':
    unittest.main()
