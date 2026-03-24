# =============================================================================
# FIPS-Compliant Base Image for gov.demo.coder.com
# =============================================================================
#
# This is the foundational workspace image for FedRAMP / FIPS-compliant Coder
# deployments. It mirrors the functionality of codercom/enterprise-base but
# runs on RHEL 9 UBI with FIPS 140-2/140-3 cryptographic policy enforced.
#
# Base OS:   Red Hat Universal Base Image 9 (UBI9)
# FIPS:      Enforced via crypto-policies (FIPS profile)
# Packages:  Equivalent to enterprise-base (git, Docker, build tools, etc.)
# User:      coder (UID 1000), passwordless sudo
#
# Usage:
#   docker build -t coder-enterprise-fips:latest .
#
# =============================================================================

FROM registry.access.redhat.com/ubi9/ubi:latest

LABEL maintainer="platform-team@gov.demo.coder.com" \
      description="FIPS-compliant base workspace image for gov.demo.coder.com (RHEL 9 UBI)" \
      org.opencontainers.image.title="coder-enterprise-fips" \
      org.opencontainers.image.description="FedRAMP/FIPS base image for Coder workspaces on RHEL 9 UBI" \
      org.opencontainers.image.vendor="gov.demo.coder.com"

SHELL ["/bin/bash", "-c"]

# ---------------------------------------------------------------------------
# FIPS Cryptographic Policy
# ---------------------------------------------------------------------------
# Enforce FIPS 140-2/140-3 crypto policy system-wide. This configures OpenSSL,
# GnuTLS, NSS, and all RHEL crypto libraries to only use FIPS-approved
# algorithms and key lengths.
# ---------------------------------------------------------------------------
RUN dnf install -y --nodocs \
        crypto-policies \
        crypto-policies-scripts && \
    update-crypto-policies --set FIPS && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Verify FIPS policy is active
RUN update-crypto-policies --show | grep -q FIPS

# ---------------------------------------------------------------------------
# Core Packages
# ---------------------------------------------------------------------------
# Install baseline development and operational tooling equivalent to the
# Ubuntu-based enterprise-base image.
# ---------------------------------------------------------------------------
RUN dnf install -y --nodocs \
        bash \
        ca-certificates \
        curl \
        gawk \
        gcc \
        gcc-c++ \
        glibc-langpack-en \
        git \
        gnupg2 \
        htop \
        iproute \
        jq \
        make \
        man-db \
        openssl \
        openssl-devel \
        procps-ng \
        python3 \
        python3-pip \
        python3-setuptools \
        rsync \
        sudo \
        systemd \
        unzip \
        vim-enhanced \
        wget \
        which \
        zip && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# ---------------------------------------------------------------------------
# Docker CE (from Docker's CentOS/RHEL repository)
# ---------------------------------------------------------------------------
# We add the official Docker CE repo for RHEL/CentOS. The `centos` slug is
# correct — Docker publishes RHEL-compatible RPMs under this path.
# ---------------------------------------------------------------------------
RUN dnf config-manager --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo && \
    dnf install -y --nodocs \
        containerd.io \
        docker-ce \
        docker-ce-cli \
        docker-buildx-plugin \
        docker-compose-plugin && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Enable Docker to start with systemd (matches enterprise-base behavior)
RUN systemctl enable docker

# Create a symlink for standalone docker-compose usage
RUN ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose

# ---------------------------------------------------------------------------
# Locale Configuration
# ---------------------------------------------------------------------------
# RHEL 9 uses glibc-langpack-* instead of locale-gen. The glibc-langpack-en
# package installed above provides en_US.UTF-8.
# ---------------------------------------------------------------------------
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
# Workspace User
# ---------------------------------------------------------------------------
# Create a non-root `coder` user (UID 1000) with passwordless sudo and Docker
# group membership, mirroring the enterprise-base convention.
# ---------------------------------------------------------------------------
RUN useradd coder \
        --create-home \
        --shell=/bin/bash \
        --groups=docker \
        --uid=1000 \
        --user-group && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd && \
    chmod 0440 /etc/sudoers.d/nopasswd

USER coder
