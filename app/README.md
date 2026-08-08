# Application — OWASP NodeGoat

[OWASP NodeGoat](https://github.com/OWASP/NodeGoat): a deliberately vulnerable Node.js + MongoDB application built to teach the OWASP Top 10. Chosen over the sample todo app so the **container and dependency scans produce genuine findings** — see `../docs/decisions.md` (D3).

- Listens on **:4000**
- Reads **`MONGODB_URI`** from the environment (set in the Kubernetes deployment)

## Build
```bash
docker build -t <REGION>-docker.pkg.dev/<PROJECT>/app/nodegoat:v1 .
```
The source is cloned inside the build (multi-stage), so the build is self-contained and reproducible in CI with no pre-step.

## `wizexercise.txt` — how it gets in, and how to prove it
**How:** a `COPY wizexercise.txt /app/wizexercise.txt` instruction in the runtime stage of the Dockerfile bakes it into the image as its own layer. It is *not* mounted at runtime, so it exists in the image itself.

**Prove it in the running container (do this live in the demo):**
```bash
kubectl exec deploy/nodegoat -- cat /app/wizexercise.txt
```
Show it is genuinely a layer of the image, not a mount:
```bash
docker history <IMAGE> | grep wizexercise      # the COPY layer
kubectl get pod -l app=nodegoat -o jsonpath='{.items[0].spec.containers[0].volumeMounts}' | jq
```

## Seeding
NodeGoat ships a seed script that creates its collections and demo users:
```bash
kubectl apply -f ../k8s/40-seed-job.yaml     # runs: npm run db:seed
```
Then prove the data landed in MongoDB (SSH to the VM):
```bash
mongosh -u app -p "$MONGO_PW" --authenticationDatabase admin \
  --eval 'db.getSiblingDB("todos").getCollectionNames()'
```

## Note on scan findings
The base image is intentionally EOL and NodeGoat's dependencies are intentionally vulnerable. Trivy/`npm audit` output is **the point** — it is what the CI pipeline gates on and what the Wiz Code narrative refers to. Do not "fix" it.
