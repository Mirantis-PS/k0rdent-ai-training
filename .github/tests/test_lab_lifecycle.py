"""Offline lifecycle regression tests. No real cloud executable is reachable."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "lab-infrastructure/scripts"

class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        # Deliberate allowlist: no installed AWS CLI, curl, SSH or Terraform.
        for name in ("jq", "dirname", "pwd", "sort", "grep", "cut", "date", "tr", "seq", "wc"):
            target = shutil.which(name)
            if not target:
                self.fail(f"Missing local dependency: {name}")
            (self.bin / name).symlink_to(target)
        for name in ("aws", "curl", "ssh", "terraform"):
            p = self.bin / name
            p.write_text('#!/bin/bash\necho "UNEXPECTED external command" >&2\nexit 99\n')
            p.chmod(0o755)
        self.env = {"PATH": str(self.bin), "HOME": str(self.work), "NO_COLOR": "1"}

    def shell(self, script, body, rc=0):
        source = (SCRIPTS / script).read_text()
        markers = {"lab-destroy.sh": "# Load config if exists", "lab-provision.sh": "# Default values", "lab-reap.sh": "# --- argument parsing"}
        source = source.split(markers[script])[0]
        module = self.work / "module.sh"
        module.write_text(source)
        result = subprocess.run(['/bin/bash', '-c', 'source "$1"\nREGION=test-region\n' + body, 'test', str(module)], env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, rc, result.stdout + result.stderr)
        self.assertNotIn('UNEXPECTED', result.stderr)
        return result.stdout

    def test_approval_flags_preserve_warning(self):
        for flags in ('FORCE=true; AUTO_APPROVE=false', 'FORCE=false; AUTO_APPROVE=true'):
            with self.subTest(flags=flags):
                out = self.shell('lab-destroy.sh', flags + '\nconfirm_orphan_risk example')
                self.assertIn('WARNING', out)
                self.assertIn('Proceeding without prompting', out)

    def test_noninteractive_without_flag_stops(self):
        self.shell('lab-destroy.sh', 'FORCE=false; AUTO_APPROVE=false\nconfirm_orphan_risk example', 1)

    def test_failed_capa_query_blocks_even_auto_approve(self):
        self.shell('lab-destroy.sh', 'FORCE=true; AUTO_APPROVE=true\naws() { return 42; }\nhandle_unreachable_managed_clusters offline student', 1)

    def test_unknown_ownership_requires_gate(self):
        out = self.shell('lab-destroy.sh', 'FORCE=false; AUTO_APPROVE=false\ndetect_managed_cluster_resources() { echo "unknown|vpc vpc-test"; }\nconfirm_orphan_risk() { echo GATED; }\nhandle_unreachable_managed_clusters offline student')
        self.assertIn('unresolved ownership', out)
        self.assertIn('GATED', out)
        self.assertNotIn('nothing of yours', out)

    def test_empty_capa_inventory_does_not_prompt(self):
        self.shell('lab-destroy.sh', 'detect_managed_cluster_resources() { :; }\nconfirm_orphan_risk() { return 44; }\nhandle_unreachable_managed_clusters offline student')

    def test_sg_query_failure_is_not_deletion_success(self):
        body = '''get_state_output() { echo vpc-test; }
aws() {
    case "$2" in
        describe-load-balancers) : ;;
        describe-security-groups)
            if [[ "$*" == *group-name* ]]; then echo sg-test; else return 42; fi ;;
        delete-security-group) return 42 ;;
        *) return 99 ;;
    esac
}
cleanup_orphan_aws_resources bucket student'''
        self.shell('lab-destroy.sh', body, 1)

    def test_sg_retry_waits_for_confirmed_absence(self):
        body = '''get_state_output() { echo vpc-test; }
aws() {
    case "$2" in
        describe-load-balancers) : ;;
        describe-security-groups)
            if [[ "$*" == *group-name* ]]; then echo sg-test; else echo None; fi ;;
        delete-security-group) return 42 ;;
        *) return 99 ;;
    esac
}
cleanup_orphan_aws_resources bucket student'''
        self.assertIn('Deleted orphan SG', self.shell('lab-destroy.sh', body).replace('Deleted orphan k8s-elb SG', 'Deleted orphan SG'))

    def test_ambiguous_vpc_fallback_blocks(self):
        self.shell('lab-destroy.sh', 'get_state_output() { :; }\naws() { printf "vpc-a\\tvpc-b\\n"; }\ncleanup_orphan_aws_resources bucket student', 1)

    def test_ip_refresh_union_and_auto(self):
        out = self.shell('lab-provision.sh', 'SSH_CIDRS=""; ALLOWED_SSH_CIDRS=""; LAB_LAST_SSH_CIDRS=192.0.2.1/32\ndetect_public_ip() { echo 192.0.2.2; }\nresolve_ssh_cidrs\necho "RESULT=$SSH_CIDRS"\nSSH_CIDRS=auto\nresolve_ssh_cidrs\necho "AUTO=$SSH_CIDRS"')
        self.assertIn('RESULT=192.0.2.1/32,192.0.2.2/32', out)
        self.assertIn('AUTO=192.0.2.2/32', out)

    def test_explicit_override(self):
        out = self.shell('lab-provision.sh', 'SSH_CIDRS=""; ALLOWED_SSH_CIDRS=192.0.2.9/32\nresolve_ssh_cidrs\necho "$SSH_CIDRS"')
        self.assertIn('192.0.2.9/32', out)

    def test_failed_detection_never_opens_world(self):
        out = self.shell('lab-provision.sh', 'SSH_CIDRS=""; ALLOWED_SSH_CIDRS=""; LAB_LAST_SSH_CIDRS=""\ndetect_public_ip() { :; }\nresolve_ssh_cidrs', 1)
        self.assertNotIn('0.0.0.0/0', out)
        self.shell('lab-provision.sh', 'SSH_CIDRS=auto\ndetect_public_ip() { :; }\nresolve_ssh_cidrs', 1)

    def test_failed_detection_can_reuse_saved_range(self):
        out = self.shell('lab-provision.sh', 'SSH_CIDRS=""; ALLOWED_SSH_CIDRS=""; LAB_LAST_SSH_CIDRS=192.0.2.1/32\ndetect_public_ip() { :; }\nresolve_ssh_cidrs\necho "$SSH_CIDRS"')
        self.assertIn('192.0.2.1/32', out)

    def test_scan_query_failure_propagates(self):
        self.shell('lab-reap.sh', 'aws() { return 42; }\ncollect_region test-region', 1)
        self.shell('lab-reap.sh', 'aws() { return 42; }\ndiscover_regions', 1)

    def test_all_enabled_regions_are_scanned(self):
        out = self.shell('lab-reap.sh', 'aws() { [[ "$2" == describe-regions ]] || return 99; printf "region-a\\tregion-b\\n"; }\ndiscover_regions')
        self.assertEqual(out.split(), ['region-a', 'region-b'])

    def test_transitional_instances_are_not_orphans(self):
        for state in ('pending', 'running', 'stopping', 'stopped'):
            with self.subTest(state=state):
                data = {'region':'test', 'instances':[{'id':'i-test','state':state,'type':'t3.large','owner':'student','launch':'2026-10-13T00:00:00Z'}], 'nats':[{'id':'nat-test','owner':'student','created':'2026-10-13T00:00:00Z'}], 'eips':[], 'vpcs':[], 'volumes':[]}
                fixture=self.work/'fixture.json'; fixture.write_text(json.dumps(data))
                out=self.shell('lab-reap.sh', 'data=$(<"' + str(fixture) + '")\nanalyse_region "$data" 2026-10-14T00:00:00Z 0.045 7')
                self.assertFalse(json.loads(out)[0]['orphaned'])

    def test_eip_without_vpc_is_flagged(self):
        data={'region':'test','instances':[], 'nats':[], 'vpcs':[], 'volumes':[], 'eips':[{'owner':'student','alloc':'eip-test'}]}
        fixture=self.work/'fixture.json'; fixture.write_text(json.dumps(data))
        out=self.shell('lab-reap.sh', 'data=$(<"' + str(fixture) + '")\nanalyse_region "$data" 2026-10-14T00:00:00Z 0.045 7')
        self.assertTrue(json.loads(out)[0]['flagged'])

    def test_scanner_rejects_delete_before_external_commands(self):
        for flag in ('--delete', '--force'):
            result=subprocess.run(['/bin/bash', str(SCRIPTS/'lab-reap.sh'),flag], env=self.env, capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,1)
            self.assertIn('report-only',result.stderr)
            self.assertNotIn('UNEXPECTED',result.stderr)


    def test_old_config_migration_and_exported_override(self):
        source=(SCRIPTS/'lab-provision.sh').read_text()
        migration=source.split('# Capture a genuinely exported override')[1].split('# Resolve region')[0]
        migration='# Capture a genuinely exported override'+migration
        config=self.work/'lab-config.env'
        config.write_text('ALLOWED_SSH_CIDRS="192.0.2.1/32"\n')
        for exported, expected in [('', '192.0.2.1/32,192.0.2.2/32'), ('192.0.2.9/32','192.0.2.9/32')]:
            with self.subTest(exported=exported):
                body='CONFIG_DIR="'+str(self.work)+'"\nSSH_CIDRS=""\nALLOWED_SSH_CIDRS="'+exported+'"\n'+migration+'\ndetect_public_ip() { echo 192.0.2.2; }\nresolve_ssh_cidrs\necho "RESULT=$SSH_CIDRS"'
                self.assertIn('RESULT='+expected,self.shell('lab-provision.sh',body))

    def test_each_inventory_query_can_fail(self):
        for query in ('describe-instances','describe-nat-gateways','describe-addresses','describe-vpcs','describe-volumes'):
            with self.subTest(query=query):
                self.shell('lab-reap.sh','aws() { if [[ "$2" == '+query+' ]]; then return 42; else echo "[]"; fi; }\ncollect_region test-region',1)

    def test_capa_tag_attribution(self):
        fixture=self.work/'capa.json'
        fixture.write_text(json.dumps([{'id':'vpc-mine','tags':[{'Key':'sigs.k8s.io/cluster-api-provider-aws/cluster/c1','Value':'owned'},{'Key':'Owner','Value':'student'}]}, {'id':'vpc-unknown','tags':[{'Key':'sigs.k8s.io/cluster-api-provider-aws/cluster/c2','Value':'owned'}]}, {'id':'vpc-mgmt','tags':None}]))
        body='aws() { if [[ "$2" == describe-vpcs ]]; then echo "$(<\"'+str(fixture)+'\")"; else echo "[]"; fi; }\ndetect_managed_cluster_resources student'
        out=self.shell('lab-destroy.sh',body)
        self.assertIn('mine|vpc vpc-mine',out)
        self.assertIn('unknown|vpc vpc-unknown',out)
        self.assertNotIn('vpc-mgmt',out)


    def test_scanner_cli_exit_codes_and_json(self):
        # Exercise the complete CLI with a fake executable, never the AWS CLI.
        stub = self.bin/'aws'
        stub.write_text('''#!/bin/bash
case "$1:$2" in
  sts:get-caller-identity) echo '{}' ;;
  ec2:describe-instances)
    if [[ "$SCAN_MODE" == error ]]; then echo 'fixture denial' >&2; exit 42; fi
    echo '[]' ;;
  ec2:describe-addresses)
    if [[ "$SCAN_MODE" == flagged ]]; then
      echo '[{"owner":"student","alloc":"eip-fixture"}]'
    else echo '[]'; fi ;;
  ec2:describe-nat-gateways|ec2:describe-vpcs|ec2:describe-volumes) echo '[]' ;;
  *) echo 'UNEXPECTED command' >&2; exit 99 ;;
esac
''')
        for mode, rc in [('empty',0),('flagged',2),('error',1)]:
            with self.subTest(mode=mode):
                result=subprocess.run(['/bin/bash',str(SCRIPTS/'lab-reap.sh'),'--region','fixture-region','--json'],env=dict(self.env,SCAN_MODE=mode),capture_output=True,text=True,timeout=10)
                self.assertEqual(result.returncode,rc,result.stdout+result.stderr)
                self.assertNotIn('UNEXPECTED',result.stderr)
                if mode=='error':
                    self.assertEqual(result.stdout,'')
                    self.assertIn('incomplete',result.stderr)
                else:
                    self.assertEqual(json.loads(result.stdout)['flagged_count'],int(mode=='flagged'))

if __name__ == '__main__':
    unittest.main()
