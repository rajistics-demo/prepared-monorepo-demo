#!/bin/bash
# Run node/warm-config.sh on the Replicated VM through SSM, with the official runtime-api-configs CLI
# pinned by commit and sha256. Output is the script's non-secret stdout only.
#
#   INSTANCE_ID=i-... AWS_REGION=us-west-2 env/rajistics/ssm-run.sh snapshot
#   ... ssm-run.sh precheck ghcr.io/org/pkg@sha256:...
#   ... ssm-run.sh save     ghcr.io/org/pkg@sha256:... 1
#   ... ssm-run.sh delete
set -euo pipefail
: "${INSTANCE_ID:?}" "${AWS_REGION:?}"
EXT_COMMIT=f1919e4e3e02c0bab65c2417761aee775f1ffbaa
CLI_SHA256=a06b30f1ad521e219224b6732297a25adb4cc4e7c4860db51b3713a52db87063
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -sfL "https://raw.githubusercontent.com/OpenHands/extensions/$EXT_COMMIT/plugins/runtime-api-configs/scripts/warm_runtime_configs.py" -o "$tmp/cli.py"
echo "$CLI_SHA256  $tmp/cli.py" | shasum -a 256 -c - >/dev/null
args="$(printf '%q ' "$@")"
cat > "$tmp/payload.sh" <<EOF
#!/bin/bash
export WORK=\$(mktemp -d /root/oh-demo.XXXXXX); chmod 700 "\$WORK"; trap 'rm -rf "\$WORK"' EXIT
echo '$(base64 < "$tmp/cli.py" | tr -d '\n')' | base64 -d > "\$WORK/cli.py"
echo '$CLI_SHA256  '"\$WORK/cli.py" | sha256sum -c - >/dev/null || { echo "FAIL cli checksum"; exit 2; }
echo '$(base64 < "$here/node/warm-config.sh" | tr -d '\n')' | base64 -d > "\$WORK/warm-config.sh"
export CLI="\$WORK/cli.py"
bash "\$WORK/warm-config.sh" $args
EOF
params="$(python3 -c "import json,sys;print(json.dumps({'commands':[open(sys.argv[1]).read()],'executionTimeout':['300']}))" "$tmp/payload.sh")"
cid="$(aws ssm send-command --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" --document-name AWS-RunShellScript \
  --comment "prepared-monorepo demo: warm-config $1" --timeout-seconds 60 --parameters "$params" \
  --query Command.CommandId --output text)"
echo "ssm_command_id=$cid" >&2
for _ in $(seq 1 40); do
  st="$(aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$cid" --instance-id "$INSTANCE_ID" --query Status --output text 2>/dev/null || true)"
  case "$st" in Success|Failed|TimedOut|Cancelled) break ;; esac; sleep 8
done
echo "ssm_status=$st" >&2
aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$cid" --instance-id "$INSTANCE_ID" \
  --query StandardOutputContent --output text
[ "$st" = Success ]
