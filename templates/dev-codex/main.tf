# =============================================================================
# Dev Codex — Generic Development Template with OpenAI Codex CLI
# =============================================================================
# Kubernetes pod-based workspace built on the enterprise-node image with
# OpenAI Codex CLI pre-installed. This is a general-purpose dev environment
# for engineers who want AI-assisted coding via the Codex CLI.
#
# Image: codercom/enterprise-node:ubuntu (will switch to FIPS image later)
#
# Included tools:
#   AI:
#     - OpenAI Codex CLI (npm install -g @openai/codex)
#   Web IDEs:
#     - code-server (VS Code in the browser)
#     - mux (terminal multiplexer)
#   System packages (installed on startup):
#     git, curl, wget, ca-certificates, openssh-client, jq, ripgrep,
#     fd-find, build-essential, python3, python3-pip, unzip, procps
# =============================================================================

terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "coder" {}

variable "use_kubeconfig" {
  type        = bool
  description = "Use host kubeconfig instead of in-cluster config"
  default     = false
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for workspaces"
  default     = "coder-workspaces"
}

provider "kubernetes" {
  config_path = var.use_kubeconfig ? "~/.kube/config" : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU Cores"
  description  = "CPU limit for the workspace pod"
  type         = "number"
  default      = "4"
  mutable      = true
  icon         = "/icon/memory.svg"
  option { name = "2 Cores"; value = "2" }
  option { name = "4 Cores"; value = "4" }
  option { name = "8 Cores"; value = "8" }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Memory allocation for the workspace pod"
  type         = "number"
  default      = "8"
  mutable      = true
  icon         = "/icon/memory.svg"
  option { name = "4 GB"; value = "4" }
  option { name = "8 GB"; value = "8" }
  option { name = "12 GB"; value = "12" }
  option { name = "16 GB"; value = "16" }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size (GB)"
  description  = "Persistent volume size — cannot be changed after creation"
  type         = "number"
  default      = "20"
  mutable      = false
  icon         = "/icon/database.svg"
  option { name = "10 GB"; value = "10" }
  option { name = "20 GB"; value = "20" }
  option { name = "50 GB"; value = "50" }
}

data "coder_parameter" "dotfiles_url" {
  name         = "dotfiles_url"
  display_name = "Dotfiles URL"
  description  = "Git repository URL for your dotfiles (optional)."
  type         = "string"
  default      = ""
  mutable      = false
  icon         = "/icon/dotfiles.svg"
}

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git Repository"
  description  = "Repository to clone on workspace start (optional)."
  type         = "string"
  default      = ""
  mutable      = false
  icon         = "/icon/git.svg"
}

# ---------------------------------------------------------------------------
# Agent
# ---------------------------------------------------------------------------

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    #!/bin/bash
    touch ~/.bashrc

    # Ensure npm global bin is on PATH
    NPM_BIN="$(npm config get prefix)/bin"
    export PATH="$HOME/.local/bin:$NPM_BIN:$PATH"
    for P in "$HOME/.local/bin" "$NPM_BIN"; do
      grep -qF "$P" ~/.profile 2>/dev/null || echo "export PATH=\"$P:\$PATH\"" >> ~/.profile
    done

    # Workaround: remove stale yarn repo that can break apt-get update
    sudo rm -f /etc/apt/sources.list.d/yarn.list 2>/dev/null || true

    # --- Install system packages ---
    echo "Installing development tools..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
      git curl wget ca-certificates openssh-client jq ripgrep fd-find \
      build-essential python3 python3-pip unzip procps > /dev/null 2>&1 || true

    # Symlink fd if installed as fdfind (Debian/Ubuntu naming)
    if command -v fdfind &> /dev/null && ! command -v fd &> /dev/null; then
      sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
    fi

    # --- Install OpenAI Codex CLI ---
    echo "Installing OpenAI Codex CLI..."
    npm install -g @openai/codex 2>&1 || true

    echo "=== Workspace Ready ==="
  EOT

  env = { EDITOR = "code"; VISUAL = "code" }

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Memory Usage"
    key          = "mem_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Disk Usage"
    key          = "disk_usage"
    script       = "coder stat disk --path /home/coder"
    interval     = 60
    timeout      = 1
  }
}

# ---------------------------------------------------------------------------
# Modules — Web IDEs & utilities
# ---------------------------------------------------------------------------

module "code-server" {
  count     = data.coder_workspace.me.start_count
  source    = "registry.coder.com/coder/code-server/coder"
  version   = "1.3.1"
  agent_id  = coder_agent.main.id
  folder    = "/home/coder"
  subdomain = true
  group     = "Web IDEs"
  order     = 1
}

module "mux" {
  count     = data.coder_workspace.me.start_count
  source    = "registry.coder.com/coder/mux/coder"
  version   = "1.4.3"
  agent_id  = coder_agent.main.id
  subdomain = true
  group     = "Web IDEs"
  order     = 2
}

module "dotfiles" {
  count        = data.coder_parameter.dotfiles_url.value != "" ? data.coder_workspace.me.start_count : 0
  source       = "registry.coder.com/coder/dotfiles/coder"
  version      = "1.0.23"
  agent_id     = coder_agent.main.id
  dotfiles_uri = data.coder_parameter.dotfiles_url.value
}

module "git-clone" {
  count    = data.coder_parameter.git_repo.value != "" ? data.coder_workspace.me.start_count : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "1.0.22"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo.value
  base_dir = "/home/coder"
}

# ---------------------------------------------------------------------------
# Persistent Volume Claim
# ---------------------------------------------------------------------------

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources { requests = { storage = "${data.coder_parameter.disk_size.value}Gi" } }
  }
  lifecycle { ignore_changes = all }
}

# ---------------------------------------------------------------------------
# Workspace Pod
# ---------------------------------------------------------------------------

resource "kubernetes_pod_v1" "workspace" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${data.coder_workspace.me.id}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-${data.coder_workspace.me.id}"
      "app.kubernetes.io/part-of"  = "coder"
    }
  }
  spec {
    security_context { run_as_user = 1000; fs_group = 1000 }
    container {
      name              = "dev"
      image             = "codercom/enterprise-node:ubuntu"
      image_pull_policy = "Always"
      command           = ["sh", "-c", coder_agent.main.init_script]
      security_context { run_as_user = 1000 }
      env { name = "CODER_AGENT_TOKEN"; value = coder_agent.main.token }
      env { name = "CODER_AGENT_URL"; value = data.coder_workspace.me.access_url }
      resources {
        requests = { "cpu" = "1"; "memory" = "${max(2, floor(data.coder_parameter.memory.value / 2))}Gi" }
        limits   = { "cpu" = "${data.coder_parameter.cpu.value}"; "memory" = "${data.coder_parameter.memory.value}Gi" }
      }
      volume_mount { mount_path = "/home/coder"; name = "home"; read_only = false }
    }
    volume {
      name = "home"
      persistent_volume_claim { claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name }
    }
    affinity {
      pod_anti_affinity {
        preferred_during_scheduling_ignored_during_execution {
          weight = 1
          pod_affinity_term {
            topology_key = "kubernetes.io/hostname"
            label_selector {
              match_expressions { key = "app.kubernetes.io/name"; operator = "In"; values = ["coder-workspace"] }
            }
          }
        }
      }
    }
  }
}
