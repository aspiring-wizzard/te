# Wiz technical exercise — operational recipes.
# Typing `just demo-proof` in front of a panel beats recalling four commands.

set shell := ["bash", "-uc"]

project := env_var_or_default("GCP_PROJECT", "clgcporg10-152")
region   := env_var_or_default("GCP_REGION", "europe-west1")
zone     := region + "-b"
prefix   := env_var_or_default("TF_VAR_prefix", "wizex")
cluster  := prefix + "-gke"

default:
    @just --list

# ---- setup ---------------------------------------------------------------

# One-shot preflight: creds, capability probe, tfvars, state bucket
setup:
    ./scripts/setup-lab.sh {{project}} {{region}}

# Point kubectl at the cluster
creds:
    gcloud container clusters get-credentials {{cluster}} --zone {{zone}} --project {{project}}

# ---- infrastructure ------------------------------------------------------

init:
    cd terraform && tofu init -backend-config=backend.hcl

# Plan to a file, so the plan you review is the plan you apply
plan:
    cd terraform && tofu plan -out=tfplan -lock-timeout=5m
    @printf '\n▸ review it:  just review     ▸ then:  just apply\n'

# Human-readable review of the saved plan
review:
    cd terraform && tofu show tfplan

# Just the resource actions, no noise — the 10-second sanity check
review-short:
    cd terraform && tofu show -json tfplan \
      | jq -r '.resource_changes[] | select(.change.actions != ["no-op"]) | "\(.change.actions|join(","))  \(.address)"' \
      | sort

# Apply the REVIEWED plan. Refuses if there isn't one.
apply:
    #!/usr/bin/env bash
    set -euo pipefail
    cd terraform
    if [ ! -f tfplan ]; then
      echo "no saved plan — run 'just plan' first (so you apply what you reviewed)" >&2
      exit 1
    fi
    tofu apply -lock-timeout=5m tfplan
    rm -f tfplan          # a consumed plan is stale; never re-apply it

# Escape hatch: plan and apply in one step, no review. Use knowingly.
apply-now:
    cd terraform && tofu apply -lock-timeout=5m

# Has anything drifted? exit 0 = clean, 2 = changes pending
drift:
    cd terraform && tofu plan -detailed-exitcode -lock-timeout=5m

# Validate without touching state or the cloud
check:
    cd terraform && tofu fmt -check -recursive && tofu init -backend=false >/dev/null && tofu validate

fmt:
    cd terraform && tofu fmt -recursive

output *ARGS:
    cd terraform && tofu output {{ARGS}}

state-list:
    cd terraform && tofu state list

destroy:
    cd terraform && tofu plan -destroy -out=tfdestroy && tofu show tfdestroy
    @printf '\n▸ to confirm:  cd terraform && tofu apply tfdestroy\n'

# ---- application ---------------------------------------------------------

# wizexercise.txt is GENERATED here, not committed: it carries a real name, which
# belongs in the image but not in a public repository. Fails closed — building
# with the placeholder would satisfy the Dockerfile and fail the exercise.
#
# NOTE ON COMMENTS IN THIS FILE: `just --list` takes the LAST comment line above
# a recipe as its description, so rationale must sit above a blank line and the
# one-line description directly above the recipe. Otherwise the self-documenting
# listing fills up with sentence fragments.

# Build the app image (linux/amd64 — nodes are amd64, this Mac is not)
build tag="v1":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${WIZ_EXERCISE_NAME:-}" ]; then
      echo "WIZ_EXERCISE_NAME is unset — the image would ship a placeholder." >&2
      echo "  echo 'export WIZ_EXERCISE_NAME=\"Your Name\"' >> .envrc.local && direnv allow" >&2
      exit 1
    fi
    printf '%s\nWiz Technical Exercise — Principal Solutions Engineer, Application Security (Germany)\n' \
      "$WIZ_EXERCISE_NAME" > app/wizexercise.txt
    cd app && docker build --platform linux/amd64 \
      -t {{region}}-docker.pkg.dev/{{project}}/app/nodegoat:{{tag}} .

push tag="v1":
    gcloud auth configure-docker {{region}}-docker.pkg.dev --quiet
    docker push {{region}}-docker.pkg.dev/{{project}}/app/nodegoat:{{tag}}

deploy tag="v1":
    sed -i '' "s|REGION-docker.pkg.dev/PROJECT/app/nodegoat:v1|{{region}}-docker.pkg.dev/{{project}}/app/nodegoat:{{tag}}|g" k8s/*.yaml
    kubectl apply -f k8s/00-rbac.yaml -f k8s/10-deployment.yaml -f k8s/20-service-ingress.yaml
    kubectl rollout status deploy/nodegoat --timeout=180s

# Never hand-typed, so it cannot drift from the database it points at.
# Re-run after any Mongo rebuild — the address is reserved, the password is not.

# (Re)create the Kubernetes Secret from Secret Manager
k8s-secret:
    #!/usr/bin/env bash
    set -euo pipefail
    URI="$(gcloud secrets versions access latest \
             --secret={{prefix}}-mongo-uri --project={{project}})"
    kubectl create secret generic mongo-credentials \
      --from-literal=uri="$URI" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "▸ mongo-credentials synced from Secret Manager → ${URI%%://*}://***@${URI##*@}"

# The Job's own exit code is NOT proof — grunt swallows the child error and
# exits 0, so this greps the log for the failure grunt hid.

# Seed the database, and verify it actually worked
seed:
    #!/usr/bin/env bash
    set -euo pipefail
    kubectl delete job nodegoat-seed --ignore-not-found=true
    kubectl apply -f k8s/40-seed-job.yaml
    kubectl wait --for=condition=complete job/nodegoat-seed --timeout=240s
    LOG="$(kubectl logs job/nodegoat-seed)"
    echo "$LOG"
    if echo "$LOG" | grep -qiE 'error|failed'; then
      echo "✗ seed reported success but the log contains an error — see above" >&2
      exit 1
    fi
    echo "✓ seed completed cleanly"

# Install Gatekeeper and the preventative constraint.
#
# REQUIRED before `just demo-prevent` means anything. Without it the privileged
# pod is admitted happily and the demo proves the opposite of its point — which
# is exactly how it was found: the manifest existed, the admission controller
# did not.
#
# The two-pass apply is not a mistake. 90-preventative-gatekeeper.yaml holds a
# ConstraintTemplate AND the constraint that depends on it, but the constraint's
# CRD is GENERATED by Gatekeeper from the template — so on a first apply the
# kind does not exist yet and the file half-fails with "no matches for kind
# K8sDenyPrivileged". Apply, wait for the CRD, apply again.

# Install Gatekeeper + the preventative constraint (REQUIRED before demo-prevent)
gatekeeper:
    #!/usr/bin/env bash
    set -euo pipefail
    kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.16/deploy/gatekeeper.yaml
    kubectl wait --for=condition=available --timeout=300s \
      deploy/gatekeeper-controller-manager -n gatekeeper-system
    # Gatekeeper ships HA defaults: 3 controller replicas + audit = 400m CPU and
    # 2Gi across a cluster deliberately sized to a $200 cap (2 x e2-medium).
    # Installing it at stock size pushed both nodes past 90% CPU REQUESTS and
    # left the application Pending — the security control evicted the workload
    # it was there to protect. One replica is ample for a single-constraint demo.
    kubectl scale deploy gatekeeper-controller-manager -n gatekeeper-system --replicas=1
    kubectl rollout status deploy/gatekeeper-controller-manager -n gatekeeper-system --timeout=180s
    kubectl apply -f k8s/90-preventative-gatekeeper.yaml || true   # constraint CRD not born yet
    for _ in $(seq 1 20); do
      kubectl get crd k8sdenyprivileged.constraints.gatekeeper.sh >/dev/null 2>&1 && break
      sleep 6
    done
    kubectl apply -f k8s/90-preventative-gatekeeper.yaml
    echo "▸ verify with: just demo-prevent   (it must be REJECTED)"

# ---- slides --------------------------------------------------------------

# Rebuild slides/slides.md from slides/parts/. Edit the parts, never slides.md.
#
# slides.md is generated and gitignored for the same reason as
# app/wizexercise.txt: the title slide carries a real name, which belongs in the
# rendered deck but not in a public repository. The parts hold a PRESENTER
# placeholder, substituted here from WIZ_EXERCISE_NAME (see .envrc.local).
#
# Unlike `just build`, this does NOT fail closed when the name is unset — an
# unsubstituted title slide is obvious the moment you look at it, whereas a
# placeholder buried inside a container image is not.

# Rebuild slides/slides.md from slides/parts/ — edit the parts, never slides.md
slides:
    #!/usr/bin/env bash
    set -euo pipefail
    cd slides
    { for f in parts/*.md; do cat "$f"; printf '\n'; done; } > .slides.tmp
    if [ -n "${WIZ_EXERCISE_NAME:-}" ]; then
      # perl, not sed: sed's delimiter handling makes an arbitrary user-supplied
      # string a hazard.
      #
      # Deliberately NO -CSD. That flag decodes I/O as UTF-8, but %ENV values
      # are raw bytes and are NOT decoded with it — so any non-ASCII character
      # arrives as its UTF-8 bytes (U+00E4 = C3 A4), is treated as two Latin-1
      # characters, and is re-encoded on output as the classic two-character
      # mojibake. The flag added to handle non-ASCII is exactly what corrupts
      # it. Plain byte-level substitution passes UTF-8 through untouched, and
      # the pattern is pure ASCII, so byte matching is still correct.
      PRESENTER="$WIZ_EXERCISE_NAME" \
        perl -pe 's/__PRESENTER__/$ENV{PRESENTER}/g' .slides.tmp > slides.md
      who="$WIZ_EXERCISE_NAME"
    else
      mv .slides.tmp slides.md
      who="UNSET — title slide shows the raw placeholder"
      echo "warning: WIZ_EXERCISE_NAME is not set" >&2
    fi
    rm -f .slides.tmp
    echo "▸ slides/slides.md — $(ls parts/*.md | wc -l | tr -d ' ') parts, presenter: ${who}"

# Serve the deck with hot reload. THIS is what you present from.
slides-dev: slides
    #!/usr/bin/env bash
    set -euo pipefail
    cd slides
    [ -d node_modules ] || yarn install --frozen-lockfile
    yarn dev

# ⚠️ Present from `just slides-dev`, not from this PDF. slidev's export renders
# Mermaid unreliably — the same diagram exports correctly at one scale and blank
# at another, and --wait/--wait-until do not help. The dev server is consistent.

# Export the deck to PDF (check the diagrams — see warning above)
slides-export: slides
    #!/usr/bin/env bash
    set -euo pipefail
    cd slides
    [ -d node_modules ] || yarn install --frozen-lockfile
    yarn export
    echo "▸ slides/wiz-technical-exercise.pdf — CHECK THE DIAGRAMS before relying on it"

# ---- the demo ------------------------------------------------------------

# Environment is healthy and the required file is in the running container
demo-proof:
    @echo "── pods / service / ingress ──"
    kubectl get pods,svc,ingress
    @printf '\n── wizexercise.txt, inside the running container ──\n'
    kubectl exec deploy/nodegoat -- cat /app/wizexercise.txt
    @printf '\n── the cluster-admin binding ──\n'
    kubectl get clusterrolebinding nodegoat-cluster-admin -o jsonpath='{.roleRef.name}{"\n"}'

# The blast radius: one pod's token reads every Secret in the cluster
demo-blast:
    kubectl exec deploy/nodegoat -- sh -c \
      'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); \
       curl -sk -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api/v1/secrets \
       | head -40'

# The backup bucket is readable by anyone, with no credentials at all
demo-public-bucket:
    @echo "── anonymous listing (no auth) ──"
    curl -s "https://storage.googleapis.com/storage/v1/b/wizex-backups-{{project}}/o" | head -30

# Asks a different question from every scanner: not "is there a known
# vulnerability" but "will this ever receive another fix". All three pins here
# are deliberately past end of life.

# Every pinned platform version, against vendor support dates
demo-eol:
    @python3 scripts/check-eol.py

# The preventative control rejects a NEW privileged pod
demo-prevent:
    -kubectl apply -f k8s/99-privileged-pod-DENYME.yaml
    @printf '\n(expected: rejected by the Gatekeeper constraint)\n'

# The load balancer address to open in a browser
url:
    @kubectl get ingress nodegoat -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'

# ---- housekeeping --------------------------------------------------------

# Current spend against the $200 sandbox cap
cost:
    @echo "Billing → Reports, filtered to {{project}}:"
    @echo "https://console.cloud.google.com/billing/reports?project={{project}}"

# Does admin_cidr still match your public IP? RUN THIS ON THE MORNING OF THE PANEL.
myip:
    #!/usr/bin/env bash
    set -uo pipefail
    # api.ipify.org first: verified reachable from this network. The others are
    # currently blocked by the local egress policy but kept as fallbacks.
    now=""
    for u in https://api.ipify.org https://ifconfig.me https://icanhazip.com; do
      now="$(curl -fsS --max-time 8 "$u" 2>/dev/null | tr -d '[:space:]')" && [ -n "$now" ] && break
    done
    if [ -z "${now:-}" ]; then echo "could not detect public IP" >&2; exit 1; fi
    cfg="$(grep -E '^\s*admin_cidr' terraform/terraform.tfvars 2>/dev/null | sed 's/.*"\(.*\)".*/\1/')"
    echo "  public IP  : ${now}"
    echo "  admin_cidr : ${cfg:-<unset>}"
    if [ "${cfg}" = "${now}/32" ]; then
      echo "  ✓ match — kubectl will reach the control plane"
    else
      echo "  ✗ MISMATCH — kubectl is locked out until you fix this:"
      echo "      sed -i '' 's|admin_cidr = .*|admin_cidr = \"${now}/32\"|' terraform/terraform.tfvars"
      echo "      just plan && just apply"
      exit 1
    fi
    # Precedence note: terraform.tfvars BEATS TF_VAR_* from direnv, so editing
    # tfvars is what actually takes effect. ADMIN_CIDR in .envrc.local is ignored
    # while tfvars defines it.
