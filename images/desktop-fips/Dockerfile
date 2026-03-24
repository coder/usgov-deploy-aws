# =============================================================================
# FIPS-Compliant Desktop Image for gov.demo.coder.com
# =============================================================================
#
# Extends the base-fips image with a full XFCE4 desktop environment and
# KasmVNC for browser-based remote access. Designed for Coder workspaces
# that need a graphical UI (e.g., IDE GUIs, browser testing, design tools).
#
# Desktop:   XFCE4 (lightweight, well-supported on RHEL 9)
# VNC:       KasmVNC (web-native, GPU-accelerated, Coder-integrated)
# FIPS:      Inherited from base-fips image
#
# Usage:
#   docker build \
#     --build-arg BASE_IMAGE=<ecr-registry>/coder-enterprise-fips:latest \
#     -t coder-enterprise-fips-desktop:latest .
#
# =============================================================================

ARG BASE_IMAGE=coder-enterprise-fips:latest
FROM ${BASE_IMAGE}

LABEL maintainer="platform-team@gov.demo.coder.com" \
      description="FIPS-compliant desktop workspace image with XFCE4 and KasmVNC for gov.demo.coder.com" \
      org.opencontainers.image.title="coder-enterprise-fips-desktop" \
      org.opencontainers.image.vendor="gov.demo.coder.com"

USER root

# ---------------------------------------------------------------------------
# XFCE4 Desktop Environment
# ---------------------------------------------------------------------------
# Install XFCE4 and supporting packages. On RHEL 9, EPEL provides the XFCE
# group. We install individual packages for a controlled, minimal footprint.
# ---------------------------------------------------------------------------
RUN dnf install -y --nodocs \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm && \
    dnf groupinstall -y --nodocs "Xfce" && \
    dnf install -y --nodocs \
        dbus-x11 \
        openssl \
        xfce4-terminal \
        xorg-x11-server-Xvfb \
        xorg-x11-xauth \
        xorg-x11-fonts-Type1 \
        xorg-x11-fonts-misc \
        mesa-dri-drivers && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Remove any stale reboot-required markers (container, not a real host)
RUN rm -f /run/reboot-required* 2>/dev/null || true

# ---------------------------------------------------------------------------
# KasmVNC
# ---------------------------------------------------------------------------
# Install KasmVNC from the official KasmTech GitHub releases. KasmVNC
# provides a performant, web-native VNC server with built-in websocket
# support — no separate noVNC proxy needed.
#
# Pin the version for reproducible builds; update as new releases are tested.
# ---------------------------------------------------------------------------
ARG KASMVNC_VERSION=1.3.3
ARG TARGETARCH=amd64

RUN KASM_RPM="kasmvncserver-${KASMVNC_VERSION}-1.el9.$(uname -m).rpm" && \
    KASM_URL="https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/${KASM_RPM}" && \
    echo "Downloading KasmVNC from: ${KASM_URL}" && \
    curl -fsSL -o "/tmp/${KASM_RPM}" "${KASM_URL}" && \
    dnf install -y --nodocs "/tmp/${KASM_RPM}" && \
    rm -f "/tmp/${KASM_RPM}" && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# ---------------------------------------------------------------------------
# KasmVNC Configuration
# ---------------------------------------------------------------------------
# Port 6901:  Standard KasmVNC web port (Coder's coder_app proxies this)
# No auth:    Coder handles workspace authentication; KasmVNC auth is
#             redundant and complicates the connection flow.
# ---------------------------------------------------------------------------
RUN mkdir -p /home/coder/.vnc && \
    echo "#!/bin/bash" > /home/coder/.vnc/xstartup && \
    echo "unset SESSION_MANAGER" >> /home/coder/.vnc/xstartup && \
    echo "unset DBUS_SESSION_BUS_ADDRESS" >> /home/coder/.vnc/xstartup && \
    echo "exec /usr/bin/startxfce4" >> /home/coder/.vnc/xstartup && \
    chmod +x /home/coder/.vnc/xstartup && \
    chown -R coder:coder /home/coder/.vnc

# Write KasmVNC yaml configuration
RUN mkdir -p /etc/kasmvnc && \
    cat > /etc/kasmvnc/kasmvnc.yaml <<'EOF'
desktop:
  resolution:
    width: 1920
    height: 1080
  allow_resize: true
network:
  protocol: http
  websocket_port: 6901
  ssl:
    require_ssl: false
    pem_certificate:
    pem_key:
runtime_configuration:
  allow_override_standard_vnc_server:
    enabled: false
  allow_override_list: []
EOF

# ---------------------------------------------------------------------------
# XDG / Session Environment
# ---------------------------------------------------------------------------
# Set environment variables so XFCE and desktop apps launch correctly inside
# the container, mirroring the enterprise-desktop pattern.
# ---------------------------------------------------------------------------
ARG USER=coder
RUN echo 'LANG=en_US.UTF-8' >> /etc/default/locale 2>/dev/null || true && \
    echo 'export GNOME_SHELL_SESSION_MODE=ubuntu' > /home/${USER}/.xsessionrc && \
    echo 'export XDG_CURRENT_DESKTOP=XFCE' >> /home/${USER}/.xsessionrc && \
    echo 'export XDG_SESSION_TYPE=x11' >> /home/${USER}/.xsessionrc && \
    chown ${USER}:${USER} /home/${USER}/.xsessionrc

ENV XDG_CURRENT_DESKTOP=XFCE
ENV XDG_SESSION_TYPE=x11

# Ensure the coder user owns their home directory (catches any root-owned files)
RUN chown -R coder:coder /home/coder

USER coder
