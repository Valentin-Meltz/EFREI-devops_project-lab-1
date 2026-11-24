# "Remote-like" backend for dev: the state lives in a folder shared by every
# user of this Mac, outside the repository, like a team bucket or network drive.
# The local backend locks the state file while an operation runs.
#   terraform -chdir=infra/envs/dev init -migrate-state -backend-config=shared.backend.hcl
path = "/Users/Shared/terraform-state/efrei-devops-lab/dev/terraform.tfstate"
