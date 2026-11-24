#!/usr/bin/env bash
# Evidence 12 (Lab 3, part 5): the terraform workflow on PR #12. A passing run,
# a failing run (deliberate misconfiguration caught by Checkov, 5.5) and the
# passing run after the revert (5.6). Read-only: gh and git queries only.
NO_KUBE=1
source "$(dirname "$0")/lib.sh"
REPO=Valentin-Meltz/EFREI-devops_project-lab-1
RUN_OK=45376225146    # 5f88cc5 workflow added
RUN_FAIL=45376412695  # d1f5323 deliberate misconfiguration
RUN_FIXED=45376602767 # cab99bd revert of the misconfiguration
DL=$(mktemp -d)
# Failed-job log lines are "job<TAB>step<TAB>timestamp text": keep the text.
LOG_TEXT="cut -f3- | sed -E 's/^\xEF\xBB\xBF//; s/^[0-9TZ:.-]+ //'"

start_log evidence/12-terraform-ci/ci.txt "12 - Terraform CI: validate, plan, security scan"

note "The workflow: Pull Requests touching infra/** only, read-only token, actions pinned to commit SHAs"
run cat .github/workflows/terraform.yml
note "5.4 Every terraform command the workflow runs: fmt, init, validate, plan, show; never apply"
run "grep -nE 'run: .*terraform|^ +terraform ' .github/workflows/terraform.yml"
run "grep -nE 'terraform .*apply' .github/workflows/terraform.yml || echo 'no terraform apply in the workflow'"
note "5.3 Security policy used by the workflow (and by a local checkov run)"
run cat .checkov.yaml

note "Runs of the terraform workflow on PR #12, oldest last"
run gh run list --repo $REPO --workflow terraform.yml --branch feature/lab3-terraform --limit 10

note "Run 1, workflow added (5f88cc5): passes"
run gh run view --repo $REPO $RUN_OK

note "Run 2, 5.5 deliberate misconfiguration (d1f5323): a privileged container allowed to escalate privileges"
run "git show --format='%h %s' d1f5323 -- infra/preview/main.tf"
run gh run view --repo $REPO $RUN_FAIL
note "Checkov output of the failed job: the two high-severity checks fail the build"
run "gh run view --repo $REPO $RUN_FAIL --log-failed | $LOG_TEXT | sed -n '/running checkov on directory/,\$p' | grep -vE '^BC_'"

note "Run 3, 5.6 revert (cab99bd): passes again"
run "git show --stat --format='%h %s' cab99bd"
run gh run view --repo $REPO $RUN_FIXED

note "5.2 The plan of each environment is uploaded as an artifact (text only, kept 7 days)"
run "gh api repos/$REPO/actions/runs/$RUN_FIXED/artifacts --jq '.artifacts[] | \"\\(.name)  \\(.size_in_bytes) bytes  expires \\(.expires_at)\"'"
run "gh run download --repo $REPO $RUN_FIXED -n plan-dev -D $DL && cat $DL/plan-dev.txt"

note "Checks on the head of PR #12"
run gh pr checks 12 --repo $REPO
rm -rf "$DL"
