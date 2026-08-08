variable "project_id" {
  description = "GCP project ID (CloudLabs sandbox)."
  type        = string
}

variable "region" {
  description = "Region. europe-west1 (Belgium) — cheapest EU region with full coverage for everything used here."
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "Zone for zonal resources (Mongo VM, GKE)."
  type        = string
  default     = "europe-west1-b"
}

variable "prefix" {
  description = "Name prefix for all resources."
  type        = string
  default     = "wizex"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form (e.g. 1.2.3.4/32) — authorises kubectl access to the GKE control plane. NOT one of the intentional weaknesses; this is a genuine control. (SSH to the Mongo VM is separately open to the world, by design.)"
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0))
    error_message = "admin_cidr must be valid CIDR notation, e.g. 1.2.3.4/32 (run: curl -s ifconfig.me)."
  }
}

variable "extra_admin_cidrs" {
  description = <<-EOT
    Additional CIDRs authorised to reach the GKE control plane, each with a label.
    Kept separate from admin_cidr so the primary entry stays unambiguous.

    Use when a second source needs kubectl: a VPN egress, a different site on
    demo day, or a CI runner. Note that GitHub-hosted runners have dynamic
    egress IPs and cannot be pinned this way — the deploy job is expected to run
    from an authorised network, with CI owning build and push. See docs/sandbox.md.

    Example:
      extra_admin_cidrs = [
        { cidr = "203.0.113.7/32", name = "vpn-egress" },
      ]

    GCP caps master_authorized_networks at 50 entries.
  EOT
  type = list(object({
    cidr = string
    name = string
  }))
  default = []

  validation {
    condition     = alltrue([for c in var.extra_admin_cidrs : can(cidrhost(c.cidr, 0))])
    error_message = "Every extra_admin_cidrs entry must be valid CIDR notation."
  }
}

variable "mongo_image" {
  description = <<-EOT
    Boot image for the MongoDB VM. Pinned to the ORIGINAL Ubuntu 20.04 release
    build (April 2020) — not a family alias, and not a recent rebuild.

    Three reasons, all deliberate:
      • the exercise requires a 1+ year outdated Linux. This is over six years
        old and end-of-standard-support since April 2025, so the vulnerability
        surface is real rather than nominal. A family alias resolves to a
        freshly-patched build, which would give a scanner almost nothing to find.
      • MongoDB 5.0 — which the application's driver requires, see
        var.mongo_version — publishes SERVER packages for focal only. The
        jammy/5.0 suite exists but ships just the shell and tools, so
        `apt-get install mongodb-org` fails there. OS and DB are coupled.
      • pinning is reproducible. A family alias silently changes what `apply`
        builds, which is the opposite of infrastructure as code.

    Note on why the pin matters, learned here: the `ubuntu-2004-lts` FAMILY no
    longer resolves — Google retired the alias after EOL. The individual images
    are still present and READY, just marked DEPRECATED, so an exact name keeps
    working long after the alias dies. Pinning did not merely make this
    reproducible; it is the only reason it is still buildable at all.
  EOT
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2004-focal-v20200423"
}

variable "mongo_apt_suite" {
  description = <<-EOT
    Ubuntu codename for the MongoDB apt repository. MUST match mongo_image, and
    must be a suite that publishes server packages for var.mongo_version —
    focal does for 5.0, jammy does not.
  EOT
  type        = string
  default     = "focal"
}

variable "mongo_version" {
  description = <<-EOT
    MongoDB major.minor series to install.

    Pinned to 5.0, and NOT freely upgradable — this is a hard compatibility
    floor, not a preference. NodeGoat ships a 2016-era MongoDB driver that
    speaks the legacy OP_QUERY wire protocol. MongoDB REMOVED OP_QUERY in 5.1,
    so on 6.0 the app connects and then fails every read and write with
    "Unsupported OP_QUERY command: find" (code 352). 5.0 is the last series the
    application can actually talk to.

    That constraint happens to serve the exercise rather than fight it: MongoDB
    5.0 reached end-of-life in October 2024, so the datastore is genuinely
    unsupported and unpatched — a real finding for the scanners, not a
    contrived one. The outdated version here is FORCED BY THE APPLICATION,
    which is exactly how legacy risk arrives in the real world: nobody chose
    it, an old dependency pinned it.

    Fixing it properly means upgrading the application's driver — an app-layer
    change, which is the point: this is an AppSec problem wearing an
    infrastructure costume.
  EOT
  type        = string
  default     = "5.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.mongo_version))
    error_message = "mongo_version must be a major.minor series, e.g. \"5.0\"."
  }
}

variable "mongo_user" {
  description = "MongoDB application user."
  type        = string
  default     = "app"
}

variable "mongo_password" {
  description = <<-EOT
    MongoDB application password. Leave null (the default) and Terraform
    generates one with random_password and stores it in Secret Manager — so the
    value never exists in tfvars, in a shell, or in shell history.

    It does still land in Terraform state, which is why state lives in a
    versioned, IAM-restricted, public-access-enforced GCS bucket. Removing it
    from state entirely means never letting it pass through Terraform at all
    (generate on the VM at boot, write straight to Secret Manager) — the residual
    gap named on the "what I'd do differently" slide.

    Set explicitly only to pin a known value for debugging.
  EOT
  type        = string
  sensitive   = true
  default     = null
}

variable "mongo_db" {
  description = "Application database name."
  type        = string
  default     = "todos"
}

variable "enable_org_policy" {
  description = "Apply the org-policy preventative control. CloudLabs sandboxes are often project-scoped without org permissions — leave false if `terraform apply` is denied, and demo the Gatekeeper/Policy Controller preventative instead."
  type        = bool
  default     = false
}
