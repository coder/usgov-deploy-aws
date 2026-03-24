# Building Coder with FIPS 140-3 Support

## Background

Coder is written in Go. Go's standard crypto library is **not** FIPS 140
validated by default. There are two approaches to FIPS compliance:

| Approach | Go Version | Mechanism | Status |
|---|---|---|---|
| `GOEXPERIMENT=boringcrypto` | 1.19 – 1.23 | cgo + BoringSSL | **Deprecated.** Being removed once Google migrates. Never officially supported. |
| **Native FIPS 140-3 module** | **1.24+** | Pure Go `crypto/internal/fips140/...` | **Recommended.** No cgo, no FFI overhead, cross-compiles normally. |

**We use the native Go 1.24+ approach.**

## Why `GOFIPS140=latest` Over `GOEXPERIMENT=boringcrypto`

This is the most important design decision in this pipeline. Here's why:

| | `GOFIPS140=latest` (Go 1.24+) | `GOEXPERIMENT=boringcrypto` |
|---|---|---|
| **Mechanism** | Pure Go FIPS 140-3 module in stdlib | BoringSSL via cgo FFI |
| **Requires cgo?** | ❌ No — `CGO_ENABLED=0` works | ✅ Yes — `CGO_ENABLED=1` + C compiler |
| **Cross-compile?** | ✅ Normal `GOOS/GOARCH` | ❌ Needs cross-compiler toolchain |
| **Binary type** | Statically linked | Dynamically linked (glibc) |
| **Coder source mods?** | None — works with vanilla Coder | None — but Coder's `build_go.sh` uses this path |
| **FIPS validation** | CMVP in progress (Go 1.24 module) | BoringCrypto has CMVP cert, but Go shim doesn't |
| **Future** | Long-term path for Go ecosystem | Deprecated, will be removed |
| **Alpine support?** | ✅ Static binary runs anywhere | ❌ Needs glibc (no Alpine) |

**Bottom line:** `GOFIPS140=latest` produces a static, cross-compilable binary
with FIPS baked in. No C toolchain, no source modifications, no Alpine
compatibility issues. It's the path forward for Go FIPS.

## How It Works

Starting with Go 1.24, every Go program already uses the FIPS 140-3 Go
Cryptographic Module for all approved algorithms. The module is just the
`crypto/internal/fips140/...` packages of the standard library.

FIPS mode is controlled by the `fips140` GODEBUG setting:

- **`GOFIPS140=latest`** (build time) — bakes `GODEBUG=fips140=on` into the
  binary as the default. The binary starts in FIPS mode without any env var.
- **`GODEBUG=fips140=on`** (runtime) — enables FIPS mode via environment
  variable. Useful if you want the same binary to run FIPS or non-FIPS.
- **`GODEBUG=fips140=only`** (runtime) — same as `on`, but panics if a
  non-FIPS algorithm is used. Strictest mode.

When FIPS mode is enabled:
- Integrity self-check at init time (compares build-time checksum with loaded symbols)
- All algorithms perform known-answer self-tests (at init or first use)
- `crypto/rand.Reader` uses NIST SP 800-90A DRBG
- `crypto/tls` only negotiates FIPS-approved versions, cipher suites, and algorithms
- No cgo required — cross-compiles like any Go program

## CI/CD Pipeline (Automated)

The FIPS build is automated via **GitHub Actions**. The workflow lives in
`.github/workflows/coder-fips.yml`.

### Pipeline Architecture

```
.github/workflows/
├── terraform.yml              # Terraform validation (fmt, validate, tflint, trivy)
├── coder-fips.yml             # Coder FIPS build ← THIS
└── images.yml                 # Workspace images (base-fips, desktop-fips)
```

> **Note:** `images/build.gitlab-ci.yml` is kept as a reference for optional
> GitLab-side builds on the deployed GitLab at `gitlab.coder4gov.com`
> (used for workspace image builds triggered from GitLab directly).

### Workflow Jobs

| Job | Description |
|---|---|
| `build` | Clone Coder source, build frontend, compile binary with `GOFIPS140=latest` |
| `image` | Package binary into Alpine container image |
| `push` | Authenticate to ECR via OIDC, push versioned + latest-fips tags |

### How to Trigger a Build for a New Version

#### Option 1: GitHub UI

1. Go to **GitHub → Actions → "Coder FIPS Build" → Run workflow**
2. Set the inputs:
   - **coder_version:** `v2.32.0` (the release tag to build)
   - **push_to_ecr:** ✅ checked (to push to ECR after build)
3. Click **Run workflow**
4. The workflow will: clone → build frontend → compile FIPS binary → package image → push to ECR

#### Option 2: GitHub CLI

```bash
# Build and push a specific version
gh workflow run coder-fips.yml \
  -f coder_version=v2.32.0 \
  -f push_to_ecr=true

# Build only (no push) — useful for testing
gh workflow run coder-fips.yml \
  -f coder_version=v2.32.0 \
  -f push_to_ecr=false

# Build a release candidate
gh workflow run coder-fips.yml \
  -f coder_version=v2.32.0-rc.1 \
  -f push_to_ecr=true
```

#### Option 3: Auto-trigger on Push

Any push to `main` that changes files under `images/coder-fips/` will
automatically trigger a build **and push** (the push job runs on main pushes).

### How to Build for the v2.32 Agents EA Release

When the `v2.32.0` tag is published on [github.com/coder/coder](https://github.com/coder/coder):

```bash
gh workflow run coder-fips.yml -f coder_version=v2.32.0 -f push_to_ecr=true
```

Or use the GitHub UI: **Actions → "Coder FIPS Build" → Run workflow** → set
`coder_version` to `v2.32.0` and check `push_to_ecr`.

### Scheduled Builds

To automatically rebuild on a schedule (e.g., weekly security refreshes), add a
`schedule` trigger to `.github/workflows/coder-fips.yml`:

```yaml
on:
  schedule:
    # Monday 06:00 UTC — weekly rebuild with default version
    - cron: '0 6 * * 1'
```

Or use GitHub's API to trigger `workflow_dispatch` from an external scheduler.

## Manual Build Steps

If you need to build locally (debugging, testing, or one-off builds):

### Prerequisites

- Go 1.24+ (check with `go version`)
- Node.js 20+ (for the frontend build)
- Make
- Docker (for container image build)
- Git

### 1. Clone the Coder repo at the target tag

```bash
# Use the latest release tag
CODER_VERSION="v2.31.5"
git clone --branch "${CODER_VERSION}" --depth 1 https://github.com/coder/coder.git
cd coder
```

### 2. Build the FIPS binary

```bash
# Build the frontend first (embeds web UI)
make site/out

# Build the enterprise binary with FIPS mode baked in
GOFIPS140=latest CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -tags enterprise \
    -trimpath \
    -ldflags "-s -w -X github.com/coder/coder/v2/buildinfo.tag=${CODER_VERSION}" \
    -o build/coder-fips \
    ./enterprise/cmd/coder

# Verify FIPS is embedded
go version -m build/coder-fips | grep fips
# Should show: build GOFIPS140=latest
```

### 3. Build the FIPS container image

```bash
# Copy binary into the Dockerfile context
cp build/coder-fips images/coder-fips/coder-fips

# Build
docker build -t coder:${CODER_VERSION}-fips images/coder-fips/

# Verify
docker run --rm coder:${CODER_VERSION}-fips /opt/coder version
```

### 4. Push to ECR

```bash
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"

aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# Ensure repo exists
aws ecr create-repository --repository-name coder \
  --image-scanning-configuration scanOnPush=true \
  --region "${AWS_DEFAULT_REGION}" 2>/dev/null || true

docker tag "coder:${CODER_VERSION}-fips" "${ECR_REGISTRY}/coder:${CODER_VERSION}-fips"
docker tag "coder:${CODER_VERSION}-fips" "${ECR_REGISTRY}/coder:latest-fips"
docker push "${ECR_REGISTRY}/coder:${CODER_VERSION}-fips"
docker push "${ECR_REGISTRY}/coder:latest-fips"
```

### 5. Deploy with Helm

In the Coder Helm values (managed by FluxCD in `clusters/gov-demo/apps/coder-server/`):

```yaml
coder:
  image:
    repo: "<account>.dkr.ecr.us-gov-west-1.amazonaws.com/coder"
    tag: "v2.31.5-fips"  # or "latest-fips" for rolling updates
```

## Verifying FIPS Compliance

### At Build Time

After building the binary, confirm FIPS is embedded:

```bash
# Check Go build info for FIPS flag
go version -m build/coder-fips | grep -i fips
# Expected output includes: build GOFIPS140=latest

# Check that GODEBUG defaults include fips140=on
go version -m build/coder-fips | grep GODEBUG
# Expected: build GODEBUG=fips140=on
```

### At Runtime (in the container)

```bash
# Run the container and check version
docker run --rm <ecr-registry>/coder:v2.31.5-fips /opt/coder version

# For Coder v2.32+, check the JSON output for FIPS field
docker run --rm <ecr-registry>/coder:v2.32.0-fips \
  /opt/coder version --json | jq '.fips'
```

### In Kubernetes (after deployment)

```bash
# Exec into the coder pod
kubectl exec -it deploy/coder -n coder -- /bin/sh

# Check the binary's build info
/opt/coder version

# Verify GODEBUG (should show fips140=on)
env | grep GODEBUG

# Verify TLS only uses FIPS cipher suites (from another pod)
openssl s_client -connect coder.coder.svc:443 -tls1_3 2>&1 | grep Cipher
```

### What to Look For

| Check | Expected | Meaning |
|---|---|---|
| `go version -m` shows `GOFIPS140=latest` | ✅ | FIPS module was selected at build time |
| `go version -m` shows `GODEBUG=fips140=on` | ✅ | FIPS mode is the default runtime behavior |
| Binary starts without crash | ✅ | Integrity self-check passed |
| `crypto/rand` uses DRBG | ✅ | NIST SP 800-90A compliant RNG |
| TLS negotiates FIPS suites only | ✅ | Non-FIPS cipher suites are rejected |

## Key Design Decisions

### Enterprise Build (`-tags enterprise`)

We use `-tags enterprise` and the enterprise entrypoint (`./enterprise/cmd/coder`)
to get Premium features: external provisioners, workspace proxies, AI Bridge,
RBAC, audit logging. This requires a **Coder license at runtime** (injected via
Kubernetes secret), not at build time.

### Frontend Included (`make site/out`)

The build includes `make site/out` to embed the web UI into the binary. Without
this, you get a "slim" binary that requires a separate frontend deployment. We
want a single, self-contained artifact.

### Alpine Base Image

The container uses Alpine 3.19 (not RHEL UBI) because:
- The Coder binary is statically linked (`CGO_ENABLED=0`) — no glibc needed
- Alpine is ~5MB vs ~200MB for UBI — faster pulls, smaller attack surface
- Matches Coder's official image pattern
- Only runtime deps are needed: ca-certificates, curl, git, openssh-client, tini

### Non-Root User (UID 1000)

The container runs as user `coder` (UID 1000), matching Coder's official images
and standard Kubernetes security contexts. The Coder process needs no root
privileges.

## Notes

- The FIPS 140-3 Go Cryptographic Module v1.0.0 is included in Go 1.24.
  CMVP validation is in progress (no completed validations yet as of March 2025).
- `GOEXPERIMENT=boringcrypto` still works in Go 1.24 but is deprecated and
  will be removed. Do not use it for new builds.
- The `GOFIPS140=latest` approach requires no special toolchain, no cgo,
  and produces a statically-linked binary that cross-compiles normally.
- The CI pipeline is defined in `.github/workflows/coder-fips.yml` and runs on
  GitHub Actions (not GitLab CI). The deployed GitLab at `gitlab.coder4gov.com`
  is used only as a FluxCD pull source.
