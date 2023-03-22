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
      image                         = var.runner_image
      imagePullPolicy               = var.runner_image_pull_policy
      gitlabUrl                     = var.gitlab_url
      concurrent                    = var.concurrent
      runnerRegistrationToken       = var.runner_registration_token
      runnerToken                   = local.runner_token
      replicas                      = local.replicas
      unregisterRunners             = var.unregister_runners
      terminationGracePeriodSeconds = var.termination_grace_period_seconds
      checkInterval                 = var.check_interval
      logLevel                      = var.log_level

      rbac = local.rbac

      metrics = local.metrics
      service = local.service

      secrets = var.additional_secrets

      runners = {
        name        = var.runner_name
        runUntagged = var.run_untagged_jobs
        tags        = var.runner_tags
        locked      = var.runner_locked
        config      = local.config

        cache = {
          secretName = local.cache_secret_name
        }
      }

      #      rbac = {
      #        create                    = var.create_service_account
      #        serviceAccountAnnotations = var.service_account_annotations
      #        serviceAccountName        = var.service_account
      #        clusterWideAccess         = var.service_account_clusterwide_access
      #      }


      securityContext    = local.security_context
      podSecurityContext = local.pod_security_context
      resources          = var.resources

      envVars = local.runner_envs

      //affinity = local.affinity
      affinity = module.affinity_transformer.output

      nodeSelector   = var.manager_node_selectors
      tolerations    = var.manager_node_tolerations
      podLabels      = var.manager_pod_labels
      podAnnotations = var.manager_pod_annotations
    }),
    yamlencode(var.values),
    local.values_file
  ]

}
