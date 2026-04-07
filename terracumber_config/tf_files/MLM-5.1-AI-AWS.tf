
// Mandatory variables for terracumber
variable "URL_PREFIX" {
  type = string
  default = "https://ci.suse.de/view/Manager/view/Manager-5.1/job/manager-ai-aws/"
}

// Not really used as this is for --runall parameter, and we run cucumber step by step
variable "CUCUMBER_COMMAND" {
  type = string
  default = "export PRODUCT='SUSE-Manager' && run-testsuite"
}

variable "CUCUMBER_GITREPO" {
  type = string
  default = "https://github.com/SUSE/spacewalk.git"
}

variable "CUCUMBER_BRANCH" {
  type = string
  default = "Manager-5.1"
}

variable "CUCUMBER_RESULTS" {
  type = string
  default = "/root/spacewalk/testsuite"
}

variable "MAIL_SUBJECT" {
  type = string
  default = "Results Manager-AI-AWS $status: $tests scenarios ($failures failed, $errors errors, $skipped skipped, $passed passed)"
}

variable "MAIL_TEMPLATE" {
  type = string
  default = "../mail_templates/mail-template-jenkins.txt"
}

variable "MAIL_SUBJECT_ENV_FAIL" {
  type = string
  default = "Results Manager-AI-AWS: Environment setup failed"
}

variable "MAIL_TEMPLATE_ENV_FAIL" {
  type = string
  default = "../mail_templates/mail-template-jenkins-env-fail.txt"
}

variable "MAIL_FROM" {
  type = string
  default = "galaxy-noise@suse.de"
}

variable "MAIL_TO" {
  type = string
  default = "galaxy-noise@suse.de"
}

variable "GIT_USER" {
  type = string
  default = null // Not needed for master, as it is public
}

variable "GIT_PASSWORD" {
  type = string
  default = null // Not needed for master, as it is public
}

variable "REGION" {
  type = string
  default = null
}

variable "MIRROR"{
  type = string
  default = null
}


// sumaform specific variables
variable "SCC_USER" {
  type = string
  default = null
}

variable "SCC_PASSWORD" {
  type = string
  default = null
}

variable "AVAILABILITY_ZONE" {
  type = string
  default = null
}

variable "KEY_FILE" {
  type = string
  default = "/home/jenkins/.ssh/testing-suma.pem"
}

variable "KEY_NAME" {
  type = string
  default = "testing-suma"
}

variable "SERVER_REGISTRATION_CODE" {
  type = string
  default = null
}

variable "PROXY_REGISTRATION_CODE" {
  type = string
  default = null
}

variable "SLES_REGISTRATION_CODE" {
  type = string
  default = null
}

variable "ALLOWED_IPS" {
  type = list(string)
  default = []
}

variable "NAME_PREFIX" {
  type = string
  default = "mlm-ai-"
}

variable "SERVER_AMI" {
  description = "Custom AMI ID to use for server. Leave empty to use the default MLM image."
  type = string
  default     = ""
}

variable "SERVER_ADDITIONAL_REPOS" {
  type        = map(string)
  description = "extra server repositories in the form {label = \"url\"}"
  default     = {}
}

variable "PROXY_AMI" {
  description = "Custom AMI ID to use for proxy. Leave empty to use the default MLMr image."
  type        = string
  default     = ""
}

variable "ARCHITECTURE" {
  description = "Select Server and Proxy architecture"
  type        = string
  default     = "x86_64"
}

variable "ENVIRONMENT_CONFIGURATION" {
  description = "Environment declaration"
}

locals {
  empty_minion_config = { ids = [], hostnames = [], macaddrs = [], private_macs = [], ipaddrs = [] }
  empty_proxy_config = { hostname = null }
}

provider "aws" {
  region     = var.REGION
}

module "base" {
  source                   = "./modules/base"
  product_version          = "5.1-released"
  cc_username              = var.SCC_USER
  cc_password              = var.SCC_PASSWORD
  name_prefix              = var.NAME_PREFIX
  mirror                   = var.MIRROR
  testsuite                = false
  use_avahi                = false
  use_eip_bastion          = false
  is_server_paygo_instance = true
  provider_settings        = {
    availability_zone = var.AVAILABILITY_ZONE
    region            = var.REGION
    ssh_allowed_ips   = var.ALLOWED_IPS
    key_name          = var.KEY_NAME
    key_file          = var.KEY_FILE
  }
}

module "server" {
  source             = "./modules/server_containerized"
  base_configuration = merge(module.base.configuration,
    {
      mirror = null
    })
  name                       = var.ENVIRONMENT_CONFIGURATION.server_containerized.name
  image                      = var.SERVER_AMI != "" ? var.SERVER_AMI : "smlm-server-51-${var.ARCHITECTURE}-ltd-paygo"
  main_disk_size             = 100
  repository_disk_size       = 500
  database_disk_size         = 0
  product_version            = var.ENVIRONMENT_CONFIGURATION.server_containerized.product_version

  auto_accept                    = false
  monitored                      = false
  disable_firewall               = false
  allow_postgres_connections     = false
  skip_changelog_import          = false
  mgr_sync_autologin             = false
  create_sample_channel          = false
  create_sample_activation_key   = false
  create_sample_bootstrap_script = false
  publish_private_ssl_key        = false
  use_os_released_updates        = false
  disable_download_tokens        = false
  large_deployment               = true
  provision                      = true
  install_salt_bundle            = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  provider_settings = {
    instance_type = var.ARCHITECTURE == "x86_64" ? "m6a.2xlarge" : "m6g.2xlarge"
  }

  additional_repos               = var.SERVER_ADDITIONAL_REPOS
}

module "proxy_containerized" {
  count                     = lookup(var.ENVIRONMENT_CONFIGURATION, "proxy_containerized", null) != null ? 1 : 0
  source                    = "./modules/proxy_containerized"
  base_configuration        = module.base.configuration
  server_configuration      = module.server.configuration
  name                      = var.ENVIRONMENT_CONFIGURATION.proxy_containerized.name
  proxy_registration_code   = var.PROXY_REGISTRATION_CODE
  image                     = var.PROXY_AMI != "" ? var.PROXY_AMI : "smlm-proxy-51-${var.ARCHITECTURE}-byos"
  provision                 = false


  auto_configure            = false
  use_os_released_updates   = false
  ssh_key_path              = "./salt/controller/id_ed25519.pub"
  provider_settings         = {
    instance_type = var.ARCHITECTURE == "x86_64" ?  "c6i.large" : "c6g.large"
  }

  additional_repos          = var.PROXY_ADDITIONAL_REPOS
}

module "sles12sp5_paygo_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles12sp5_paygo_minion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles12sp5_paygo_minion.name
  image              = "sles12sp5-paygo"
  product_version    = var.ENVIRONMENT_CONFIGURATION.sles12sp5_paygo_minion.product_version
  provider_settings = {
    instance_type = "t3a.medium"
  }
  server_configuration = module.server.configuration
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
}

module "sles15sp5_paygo_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles15sp5_paygo_minion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles15sp5_paygo_minion.name
  image              = "sles15sp5-paygo"
  product_version    = var.ENVIRONMENT_CONFIGURATION.sles15sp5_paygo_minion.product_version
  provider_settings  = {
    instance_type = "t3a.medium"
  }
  server_configuration    = module.server.configuration
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
}

module "sles15sp6_paygo_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles15sp6_paygo_minion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles15sp6_paygo_minion.name
  image              = "sles15sp6-paygo"
  product_version    = var.ENVIRONMENT_CONFIGURATION.sles15sp6_paygo_minion.product_version
  provider_settings = {
    instance_type = "t3a.medium"
  }
  server_configuration = module.server.configuration
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
}

module "sles160_paygo_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles160_paygo_minion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles160_paygo_minion.name
  image              = "sles160-paygo"
  product_version    = var.ENVIRONMENT_CONFIGURATION.sles160_paygo_minion.product_version
  provider_settings = {
    instance_type = "t3a.medium"
  }
  server_configuration = module.server.configuration
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
}

module "sles15sp7_paygo_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles15sp7_paygo_minion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles15sp7_paygo_minion.name
  image              = "sles15sp7-paygo"
  product_version    = var.ENVIRONMENT_CONFIGURATION.sles15sp7_paygo_minion.product_version
  provider_settings = {
    instance_type = "t3a.medium"
  }
  server_configuration = module.server.configuration
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
}

module "slesforsap15sp5_paygo_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "slesforsap15sp5_paygo_minion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.slesforsap15sp5_paygo_minion.name
  image              = "slesforsap15sp5-paygo"
  product_version    = var.ENVIRONMENT_CONFIGURATION.slesforsap15sp5_paygo_minion.product_version
  provider_settings = {
    instance_type = "t3.large"
  }
  server_configuration = module.server.configuration
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
}


module "sles12sp5_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles12sp5_minion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles12sp5_minion.name
  image              = "sles12sp5"
  server_configuration = module.server.configuration
  sles_registration_code = var.SLES_REGISTRATION_CODE
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  provider_settings = {
    instance_type = "t3a.medium"
  }
  additional_packages = [ "chrony" ]

}

module "sles15sp4_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles15sp4_minion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles15sp4_minion.name
  image              = "sles15sp4o"
  server_configuration = module.server.configuration
  sles_registration_code = var.SLES_REGISTRATION_CODE
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  provider_settings = {
    instance_type = "t3a.medium"
  }

}

module "sles15sp5_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles15sp5_minion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles15sp5_minion.name
  image              = "sles15sp5o"
  server_configuration = module.server.configuration
  sles_registration_code = var.SLES_REGISTRATION_CODE
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  provider_settings = {
    instance_type = "t3a.medium"
  }

}

module "sles15sp6_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles15sp6_minion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles15sp6_minion.name
  image              = "sles15sp6o"
  server_configuration = module.server.configuration
  sles_registration_code = var.SLES_REGISTRATION_CODE
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  provider_settings = {
    instance_type = "t3a.medium"
  }

}

module "sles15sp7_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles15sp7_minion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles15sp7_minion.name
  image              = "sles15sp7o"
  server_configuration = module.server.configuration
  sles_registration_code = var.SLES_REGISTRATION_CODE
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  provider_settings = {
    instance_type = "t3a.medium"
  }

}

module "sles12sp5_sshminion" {
  source             = "./modules/sshminion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles12sp5_sshminion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles12sp5_sshminion.name
  image              = "sles12sp5"
  use_os_released_updates = false
  install_salt_bundle     = false
  sles_registration_code = var.SLES_REGISTRATION_CODE
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  gpg_keys                = ["default/gpg_keys/galaxy.key"]
  provider_settings = {
    instance_type = "t3a.medium"
  }
  additional_packages = [ "chrony" ]
}

module "sles15sp4_sshminion" {
  source             = "./modules/sshminion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles15sp4_sshminion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles15sp4_sshminion.name
  image              = "sles15sp4o"
  sles_registration_code = var.SLES_REGISTRATION_CODE
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  provider_settings = {
    instance_type = "t3a.medium"
  }
}


module "sles15sp5_sshminion" {
  source             = "./modules/sshminion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles15sp5_sshminion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles15sp5_sshminion.name
  image              = "sles15sp5o"
  sles_registration_code = var.SLES_REGISTRATION_CODE
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  provider_settings = {
    instance_type = "t3a.medium"
  }

}

module "sles15sp6_sshminion" {
  source             = "./modules/sshminion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles15sp6_sshminion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles15sp6_sshminion.name
  image              = "sles15sp6o"
  sles_registration_code = var.SLES_REGISTRATION_CODE
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  provider_settings = {
    instance_type = "t3a.medium"
  }

}

module "sles15sp7_sshminion" {
  source             = "./modules/sshminion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "sles15sp7_sshminion", null) != null ? 1 : 0
  base_configuration = module.base.configuration
  name               = var.ENVIRONMENT_CONFIGURATION.sles15sp7_sshminion.name
  image              = "sles15sp7o"
  sles_registration_code = var.SLES_REGISTRATION_CODE
  use_os_released_updates = false
  install_salt_bundle     = false
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  provider_settings = {
    instance_type = "t3a.medium"
  }
}

module "rhel9_paygo_minion" {
  source             = "./modules/minion"
  count              = lookup(var.ENVIRONMENT_CONFIGURATION, "rhel9_paygo_minion", null) != null ? 1 : 0
  base_configuration = merge(module.base.configuration,
    {
      testsuite = "false"
    })
  name               = var.ENVIRONMENT_CONFIGURATION.rhel9_paygo_minion.name
  image              = "rhel9"
  server_configuration = module.server.configuration
  auto_connect_to_master  = false
  use_os_released_updates = false
  install_salt_bundle     = true
  product_version         = var.ENVIRONMENT_CONFIGURATION.rhel9_paygo_minion.product_version
  ssh_key_path            = "./salt/controller/id_ed25519.pub"
  provider_settings = {
    memory = 2048
    vcpu = 2
    instance_type = "t3a.medium"
  }

}

output "bastion_public_name" {
  value = lookup(module.base.configuration, "bastion_host", null)
}

output "configuration" {
  value = {
    controller  = module.controller.configuration
    server      = module.server.configuration
    bastion     = {
      hostname  = lookup(module.base.configuration, "bastion_host", null)
    }
  }
}

output "server_instance_id" {
  value = module.server.configuration.id
}
