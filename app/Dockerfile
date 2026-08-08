# OWASP NodeGoat — deliberately vulnerable Node.js + MongoDB app.
#
# Two deliberate choices that serve the exercise:
#   1. Base image node:16-bullseye is EOL. That is intentional: the container scan
#      (Trivy) surfaces real OS + dependency CVEs, so the pipeline demonstrates
#      *catching* something rather than reporting "all clear".
#   2. wizexercise.txt is added as its own layer via COPY (see README for how this
#      is proven inside the running container). It is GENERATED, not committed —
#      it carries a real name, which belongs in the image but not in a public
#      repository. `just build` writes it from WIZ_EXERCISE_NAME; CI writes it
#      from the repository SECRET of the same name (a secret, not a variable —
#      variables are printed unmasked in public Actions logs). Building by hand
#      with a bare `docker build` will fail on this COPY until the file exists.

# NOTE: build for linux/amd64 explicitly on an Apple Silicon machine —
#   docker build --platform linux/amd64 ...
# GKE nodes here are amd64; an arm64 image pulls successfully and then fails with
# "exec format error" at startup. CI builds on amd64 runners, so it only bites locally.

# ---- source stage: fetch NodeGoat ----------------------------------------
FROM node:16-bullseye AS source
ARG NODEGOAT_REF=master
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${NODEGOAT_REF}" https://github.com/OWASP/NodeGoat.git /src

# ---- runtime stage -------------------------------------------------------
FROM node:16-bullseye
WORKDIR /app

COPY --from=source /src /app
RUN npm install --unsafe-perm --no-audit --no-fund

# Exercise requirement: a file named wizexercise.txt containing my name,
# baked into the image (not mounted at runtime).
COPY wizexercise.txt /app/wizexercise.txt

ENV PORT=4000
EXPOSE 4000

# NodeGoat reads MONGODB_URI from the environment (set via Kubernetes).
CMD ["npm", "start"]
