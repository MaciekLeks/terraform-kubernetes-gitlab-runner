locals {
  values_file     = var.values_file != null ? file(var.values_file) : ""
  repository      = "https://charts.gitlab.io"
  chart_name      = "gitlab-runner"
  runner_token    = var.runner_registration_token == null ? var.runner_token : null
  replicas        = var.runner_token != null ? 1 : var.replicas
  gcs_secret_name = lookup(var.cache.gcs, "CredentialsFile", "") != "" ? "google-application-credentials" : lookup(var.cache.gcs, "AccessID", "") != "" ? "gcsaccess" : ""

  cache_secret_config = {
    s3    = "s3access"
    azure = "azureaccess"
    gcs   = local.gcs_secret_name
  }
  cache_secret_name = var.cache.secret_name != "" ? var.cache.secret_name : lookup(local.cache_secret_config, var.cache.type, "")

  runner_envs = [
    for env in var.envs : {
      name  = env.name,
      value = env.value
    } if env.runner == true
  ]

  job_envs = [
    for env in var.envs :
    "${env.name}=${env.value}" if env.job == true
  ]

  // snake to cammel case conversion
  service = {
    for k, v in var.service :
    join("", [for i, kv in split("_", k) : i == 0 ? kv : kv == "ip" ? "IP" : kv == "ips" ? "IPs" : title(kv)]) => v
  }

  //snake to cammel case conversion
  metrics_service_monitor = {
    for k, v in var.metrics.service_monitor :
    join("", [for i, kv in split("_", k) : i == 0 ? kv : title(kv)]) => v
  }

  // snake to cammel case conversion
  // cond ? v1: v2 must be of the same type, to workaround this we use list: ["x", true][cond ? 0:1]
  metrics = {
    for k, v in var.metrics :
    join("", [for i, kv in split("_", k) : i == 0 ? kv : title(kv)]) => [local.metrics_service_monitor, v][k == "service_monitor" ? 0 : 1]
  }

  rbac_pod_security_policy = {
    for k, v in var.rbac.pod_security_policy :
    join("", [for i, kv in split("_", k) : i == 0 ? kv : title(kv)]) => v
  }

  rbac_rules = [
    for rule in var.rbac.rules : {
      for kr, vr in rule :
      join("", [for i, kv in split("_", kr) : i == 0 ? kv : title(kv)]) => vr
    }
  ]

  // cond ? v1: v2 must be of the same type, to workaround this we use list: ["x", true][cond ? 0:1]
  rbac = {
    for k, v in var.rbac :
    join("", [for i, kv in split("_", k) : i == 0 ? kv : title(kv)]) =>
    [local.rbac_pod_security_policy, local.rbac_rules, v][k == "pod_security_policy" ? 0 : k == "rules" ? 1 : 2]
  }
}

