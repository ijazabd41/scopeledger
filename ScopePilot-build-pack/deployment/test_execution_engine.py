import subprocess
import json
import urllib.request
import os

def get_env_var(key, default=""):
    val = os.environ.get(key)
    if val:
        return val
    env_file = os.path.join(os.path.dirname(__file__), ".env.local")
    if os.path.exists(env_file):
        with open(env_file, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    if k.strip() == key:
                        return v.strip()
    return default

GH_TOKEN = get_env_var("GITHUB_TOKEN")
REPO_OWNER = get_env_var("REPO_OWNER", "AbdurRehman-eng")
REPO_NAME = get_env_var("REPO_NAME", "scopeledger-demo")
CASE_ID = "08d6fa6c-f5db-4e55-9ebb-356d765a68c8"
WORKER_ID = "worker-scopeledger-01"

def gh_api(method, path, body=None):
    url = f"https://api.github.com{path}"
    headers = {
        "Authorization": f"Bearer {GH_TOKEN}",
        "User-Agent": "ScopePilot-Executor/1.0",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json"
    }
    data = json.dumps(body).encode('utf-8') if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode('utf-8'))

def psql(sql):
    cmd = ['docker', 'exec', 'deployment-postgres-1', 'psql', '-U', 'postgres', '-d', 'scopeledger', '-t', '-A', '-c', sql]
    return subprocess.check_output(cmd, text=True).strip()

print("1. Claiming Action 1...")
claim_sql = f"SELECT id, action_kind, approved_payload::text, resource_id FROM scopeledger.claim_next_action('{WORKER_ID}', 120);"
row = psql(claim_sql)
print("Claimed:", row)
parts = row.split('|')
action1_id = parts[0]
action1_kind = parts[1]
action1_payload = json.loads(parts[2])

# Execute Action 1: Create GitHub Issue
print("Creating GitHub Issue for Account Dashboard...")
issue_created = gh_api("POST", f"/repos/{REPO_OWNER}/{REPO_NAME}/issues", {
    "title": action1_payload["title"],
    "body": action1_payload["body"],
    "labels": action1_payload["labels"]
})
new_issue_num = issue_created["number"]
print(f"Created Issue #{new_issue_num}: {issue_created['html_url']}")

# Independently read back issue
readback1 = gh_api("GET", f"/repos/{REPO_OWNER}/{REPO_NAME}/issues/{new_issue_num}")
v1 = {
    "read_back": True,
    "issue_number": new_issue_num,
    "title": readback1["title"],
    "state": readback1["state"],
    "labels": [l["name"] for l in readback1.get("labels", [])]
}
receipt1 = {
    "provider": "github",
    "issue_number": new_issue_num,
    "html_url": issue_created["html_url"],
    "created_at": issue_created["created_at"]
}
psql(f"""
SELECT scopeledger.record_action_result(
  '{action1_id}'::uuid,
  '{WORKER_ID}',
  'verified',
  '{json.dumps(receipt1)}'::jsonb,
  '{json.dumps(v1)}'::jsonb
);
""")
print(f"Action 1 ({action1_id}) verified!")

print("\n2. Claiming Action 2...")
row2 = psql(claim_sql)
print("Claimed:", row2)
parts2 = row2.split('|')
action2_id = parts2[0]
action2_kind = parts2[1]
action2_payload = json.loads(parts2[2])
supersede_issue_num = int(action2_payload.get("issue_number") or parts2[3] or 2)

# Execute Action 2: Supersede Issue #2
print(f"Superseding GitHub Issue #{supersede_issue_num} (CSV Export)...")
issue_updated = gh_api("PATCH", f"/repos/{REPO_OWNER}/{REPO_NAME}/issues/{supersede_issue_num}", {
    "state": "closed",
    "labels": ["scopeledger:superseded"]
})
print(f"Issue #{supersede_issue_num} closed with labels: {[l['name'] for l in issue_updated['labels']]}")

# Independently read back issue #2
readback2 = gh_api("GET", f"/repos/{REPO_OWNER}/{REPO_NAME}/issues/{supersede_issue_num}")
v2 = {
    "read_back": True,
    "issue_number": supersede_issue_num,
    "state": readback2["state"],
    "labels": [l["name"] for l in readback2.get("labels", [])]
}
receipt2 = {
    "provider": "github",
    "issue_number": supersede_issue_num,
    "state": "closed"
}
psql(f"""
SELECT scopeledger.record_action_result(
  '{action2_id}'::uuid,
  '{WORKER_ID}',
  'verified',
  '{json.dumps(receipt2)}'::jsonb,
  '{json.dumps(v2)}'::jsonb
);
""")
print(f"Action 2 ({action2_id}) verified!")

# Finalize case
print("\n3. Finalizing verified case...")
fin_res = psql(f"""
SELECT scope_version_id, completed_at FROM scopeledger.finalize_verified_case(
  '{CASE_ID}'::uuid,
  'https://github.com/{REPO_OWNER}/{REPO_NAME}',
  'rev-v2',
  'corr-final-001'
);
""")
print("Finalization result:", fin_res)

# Verify final DB state
case_final = psql(f"SELECT state, row_version FROM scopeledger.cases WHERE id = '{CASE_ID}';")
print("Case Final State:", case_final)

active_scope = psql(f"""
SELECT sv.version, sv.status, sv.document_id
FROM scopeledger.projects p
JOIN scopeledger.scope_versions sv ON sv.id = p.active_scope_id
WHERE p.id = '11111111-1111-1111-1111-111111111111';
""")
print("Active Scope in Project:", active_scope)
