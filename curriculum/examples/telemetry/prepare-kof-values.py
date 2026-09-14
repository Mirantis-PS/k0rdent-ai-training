#!/usr/bin/env python3
"""Prepare KOF 1.6 values from installed values; never changes a cluster."""
import argparse
import copy
import json
from pathlib import Path
from urllib.parse import urlparse
import yaml

TLS = {'ca_file': '/etc/otel/ingest/ca.crt', 'cert_file': '/etc/otel/ingest/tls.crt', 'key_file': '/etc/otel/ingest/tls.key'}

def merge(left, right):
    result = copy.deepcopy(left)
    for key, value in right.items():
        result[key] = merge(result.get(key, {}), value) if isinstance(value, dict) else copy.deepcopy(value)
    return result

def named_append(items, addition):
    return [x for x in items if x['name'] != addition['name']] + [addition]

def prepare(values, existing, mode, endpoint=None, collector=None):
    stack = values['opentelemetry-kube-stack']
    overrides = {}
    selected = ['daemon'] if mode == 'external' else list(stack['collectors'])
    for name in selected:
        source = merge(stack['collectors'][name], existing.get('opentelemetry-kube-stack', {}).get('collectors', {}).get(name, {}))
        if source.get('enabled') is False:
            continue
        entry = {}
        tls = {key: value.replace('/ingest/', '/external/') for key, value in TLS.items()} if mode == 'external' else TLS
        volume_name = 'external-tls' if mode == 'external' else 'ingest-tls'
        secret_name = 'kof-external-client' if mode == 'external' else 'kof-ingest-client'
        mount_path = '/etc/otel/external' if mode == 'external' else '/etc/otel/ingest'
        # Copy chart-input lists, not rendered CR lists (which contain preset mounts).
        for field, item in [('volumes', {'name': volume_name, 'secret': {'secretName': secret_name}}),
                            ('volumeMounts', {'name': volume_name, 'mountPath': mount_path, 'readOnly': True})]:
            items = source.get(field, stack.get('defaultCRConfig', {}).get(field, []))
            entry[field] = named_append(items or [], item)
        if mode == 'storage':
            entry['config'] = {'exporters': {key: {'tls': tls} for key in ['prometheusremotewrite', 'otlphttp/logs']}}
        else:
            if not endpoint or urlparse(endpoint).scheme != 'https':
                raise ValueError('external endpoint must be an https OTLP/HTTP base URL')
            if not collector or collector['metadata']['name'] != 'kof-collectors-daemon':
                raise ValueError('supply the installed kof-collectors-daemon CR JSON')
            config = collector['spec']['config']
            if isinstance(config, str):
                config = yaml.safe_load(config)
            pipelines = {}
            for key, pipeline in config['service']['pipelines'].items():
                if key.endswith('/external') or key.split('/')[0] not in ('logs', 'metrics', 'traces'):
                    continue
                for receiver in pipeline.get('receivers', []):
                    if receiver not in config.get('receivers', {}):
                        raise ValueError(f'undefined receiver: {receiver}')
                for processor in pipeline.get('processors', []):
                    if processor not in config.get('processors', {}):
                        raise ValueError(f'undefined processor: {processor}')
                p = copy.deepcopy(pipeline)
                p['exporters'] = ['otlphttp/external']
                p['processors'] = [x for x in p.get('processors', []) if x.split('/')[0] != 'batch'] + ['batch/external']
                pipelines[key + '/external'] = p
            if not {'logs', 'metrics'}.issubset({key.split('/')[0] for key in pipelines}):
                raise ValueError('daemon must have active logs and metrics pipelines')
            entry['volumes'] = named_append(entry['volumes'], {'name': 'external-queue', 'hostPath': {'path': '/var/lib/otelcol/external-queue', 'type': 'DirectoryOrCreate'}})
            entry['volumeMounts'] = named_append(entry['volumeMounts'], {'name': 'external-queue', 'mountPath': '/var/lib/otelcol/external-queue'})
            extensions = list(config.get('service', {}).get('extensions', []))
            if 'file_storage/external' not in extensions:
                extensions.append('file_storage/external')
            entry['config'] = {
                'extensions': {'file_storage/external': {'directory': '/var/lib/otelcol/external-queue'}},
                'exporters': {'otlphttp/external': {'endpoint': endpoint.rstrip('/'), 'tls': tls,
                    'sending_queue': {'enabled': True, 'storage': 'file_storage/external', 'num_consumers': 4, 'queue_size': 5000},
                    'retry_on_failure': {'enabled': True, 'initial_interval': '1s', 'max_interval': '30s', 'max_elapsed_time': '3600s'}}},
                'processors': {'batch/external': {'timeout': '5s', 'send_batch_size': 1000, 'send_batch_max_size': 1500}},
                'service': {'extensions': extensions, 'pipelines': pipelines}}
        overrides[name] = entry
    return merge(existing, {'opentelemetry-kube-stack': {'collectors': overrides}})

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--values', required=True, type=Path, help='helm get values --all -o json')
    p.add_argument('--existing', type=Path, help='existing CAPI annotation YAML, saved before editing')
    p.add_argument('--mode', required=True, choices=['storage', 'external'])
    p.add_argument('--endpoint')
    p.add_argument('--collector', type=Path, help='installed daemon OpenTelemetryCollector JSON')
    args = p.parse_args()
    try:
        result = prepare(json.loads(args.values.read_text()), yaml.safe_load(args.existing.read_text()) or {} if args.existing else {},
                         args.mode, args.endpoint, json.loads(args.collector.read_text()) if args.collector else None)
        print(yaml.safe_dump(result, sort_keys=False), end='')
    except (ValueError, KeyError) as exc:
        p.exit(2, f'Invalid KOF input: {exc}\n')
if __name__ == '__main__':
    main()
