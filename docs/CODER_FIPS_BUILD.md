# Building Coder with FIPS 140-3 Support

## Background

Coder is written in Go. Go's standard crypto library is **not** FIPS 140
validated by default. There are two approaches to FIPS compliance:

| Approach | Go Version | Mechanism | Status |
|---|---|---|---|
| `GOEXPERIMENT=boringcrypto` | 1.19 – 1.23 | cgo + BoringSSL | **Deprecated.** Being removed once Google migrates. Never officially supported. |
| **Native FIPS 140-3 module** | **1.24+** | Pure Go `crypto/internal/fips140/...` | **Recommended.** No cgo, no FFI overhead, cross-compiles normally. |

**We use the native Go 1.24+ approach.**

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

## Build Steps

### Prerequisites

- Go 1.24+ (check with `go version`)
- Node.js 20+ (for the frontend build)
- Make
- Docker (for container image build)
- Git

### 1. Clone the Coder repo at the target RC tag

```bash
# Use the latest RC release tag
CODER_VERSION="v2.x.y-rc.z"  # Replace with actual RC tag
git clone --branch "${CODER_VERSION}" --depth 1 https://github.com/coder/coder.git
cd coder
```

### 2. Build the FIPS binary

```bash
# Build the "fat" binary (frontend embedded) with FIPS mode baked in
GOFIPS140=latest make build/coder_linux_amd64

# Verify FIPS is embedded
go version -m build/coder_linux_amd64 | grep fips
# Should show: build GOFIPS140=latest
```

The Coder Makefile supports these key targets:
- `build-fat` — all fat binaries (frontend embedded) for all architectures
- `build-slim` — slim binaries (no frontend) for all architectures
- `build/coder_linux_amd64` — single fat binary for linux/amd64
- `build/coder_${version}_linux_amd64.tag` — Docker image

### 3. Build the FIPS container image

```bash
# Build the Docker image with FIPS binary
GOFIPS140=latest make build/coder_${CODER_VERSION}_linux_amd64.tag

# Tag for ECR
ECR_REGISTRY="<account>.dkr.ecr.us-west-2.amazonaws.com"
docker tag "ghcr.io/coder/coder:${CODER_VERSION}" \
  "${ECR_REGISTRY}/coder:${CODER_VERSION}-fips"
docker tag "ghcr.io/coder/coder:${CODER_VERSION}" \
  "${ECR_REGISTRY}/coder:latest-fips"
```

### 4. Push to ECR

```bash
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# Create repo if it doesn't exist
aws ecr create-repository --repository-name coder \
  --image-scanning-configuration scanOnPush=true \
  --region us-west-2 2>/dev/null || true

docker push "${ECR_REGISTRY}/coder:${CODER_VERSION}-fips"
docker push "${ECR_REGISTRY}/coder:latest-fips"
```

### 5. Deploy with Helm

In the Coder Helm values (managed by FluxCD):

```yaml
coder:
  image:
    repo: "<account>.dkr.ecr.us-west-2.amazonaws.com/coder"
    tag: "latest-fips"
```

## Runtime Verification

Once deployed, verify FIPS mode is active:

```bash
# Exec into the coder pod
kubectl exec -it deploy/coder -n coder -- /bin/sh

# Check the binary
go version -m /opt/coder  # or wherever the binary lives

# Check GODEBUG
env | grep GODEBUG
# Should show fips140=on (or fips140=latest)
```

## GitLab CI Integration

Add a job to `images/build.gitlab-ci.yml` to automate this:

```yaml
build-coder-fips:
  stage: build
  image: golang:1.24
  services:
    - docker:27-dind
  variables:
    GOFIPS140: "latest"
    CODER_VERSION: "v2.x.y-rc.z"  # Pin to specific RC
  script:
    - git clone --branch ${CODER_VERSION} --depth 1 https://github.com/coder/coder.git
    - cd coder
    - apt-get update && apt-get install -y nodejs npm
    - GOFIPS140=latest make build/coder_linux_amd64
    - docker build -t ${ECR_REGISTRY}/coder:${CODER_VERSION}-fips .
    - docker push ${ECR_REGISTRY}/coder:${CODER_VERSION}-fips
  rules:
    - when: manual
```

## Notes

- The FIPS 140-3 Go Cryptographic Module v1.0.0 is included in Go 1.24.
  CMVP validation is in progress (no completed validations yet as of March 2025).
- `GOEXPERIMENT=boringcrypto` still works in Go 1.24 but is deprecated and
  will be removed. Do not use it for new builds.
- The `GOFIPS140=latest` approach requires no special toolchain, no cgo,
  and produces a statically-linked binary that cross-compiles normally.
