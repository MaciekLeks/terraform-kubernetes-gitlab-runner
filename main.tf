//INSTALL HELM CHART
resource "helm_release" "gitlab_runner" {
  name             = var.release_name
  repository       = local.repository
  chart            = local.chart_name
  namespace        = var.namespace
  version          = var.chart_version
  create_namespace = var.create_namespace
  atomic           = var.atomic

  values = [
    yamlencode({
      image                         = var.image
      imagePullPolicy               = var.image_pull_policy
      gitlabUrl                     = var.gitlab_url
      concurrent                    = var.concurrent
      runnerRegistrationToken       = var.runner_registration_token
      runnerToken                   = local.runner_token
      replicas                      = local.replicas
      unregisterRunners             = var.unregister_runners
      terminationGracePeriodSeconds = var.termination_grace_period_seconds
      shutdown_timeout              = var.shutdown_timeout
      checkInterval                 = var.check_interval
      logLevel                      = var.log_level

      probeTimeoutSeconds = var.health_check.timeout_seconds

      rbac           = local.rbac
      serviceAccount = local.service_account

      metrics = local.metrics
      service = local.service


      runners = {
        name        = var.runner_name
        runUntagged = var.run_untagged_jobs
        tags        = var.runner_tags
        locked      = var.runner_locked
        config      = local.config

        cache = var.cache != null ? var.cache.secret_name != null ? { secretName = var.cache.secret_name } : {} : {}

      }

      #      rbac = {
      #        create                    = var.create_service_account
      #        serviceAccountAnnotations = var.service_account_annotations
      #        serviceAccountName        = var.service_account
      #        clusterWideAccess         = var.service_account_clusterwide_access
      #      }


      securityContext    = local.security_context
      podSecurityContext = local.pod_security_context
      resources          = module.resources.output


      //affinity = local.affinity
      affinity = module.affinity_transformer.output
      #topologySpreadConstraints = module.topology_spread_constraints - commented due to helm issue
      #topologySpreadConstraints = {} #test if helm works with object or array of objects

      nodeSelector = var.node_selector
      tolerations  = var.tolerations

      envVars           = local.runner_envs
      hostAliases       = var.host_aliases
      podLabels         = var.pod_labels
      podAnnotations    = var.pod_annotations
      hpa               = module.hpa.output
      priorityClassName = var.priority_class_name
      secrets           = var.secrets
      configMaps        = var.config_maps
      volumeMounts      = local.volume_mounts
      volumes           = var.volumes
    }),
    yamlencode(var.values),
    local.values_file
  ]

}
