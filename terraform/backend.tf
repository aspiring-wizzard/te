# Remote state in GCS — partial configuration, supplied at init time.
#
# Why this matters: OpenTofu writes RESOLVED values into state in plaintext,
# including the generated Mongo password. No secret enters this repository at
# all, but state is a different problem — and without a remote backend, CI state
# would live on an ephemeral runner with the password in it.
#
# The bucket is created out-of-band by scripts/bootstrap-state.sh (it cannot
# live in the state it stores), with versioning on and public access ENFORCED.
#
#   local:  tofu init -backend-config=backend.hcl
#   CI:     tofu init -backend-config="bucket=$TF_STATE_BUCKET" -backend-config="prefix=wizex"
#   lint:   tofu init -backend=false          # validate/fmt need no state
terraform {
  backend "gcs" {}
}
