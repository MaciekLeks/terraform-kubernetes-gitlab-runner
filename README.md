# Disclaimer: Project No Longer Maintained

This project is no longer actively developed or maintained. We recommend switching to the new project [lazy-gitlab-runner-k8s-tf](https://github.com/MaciekLeks/lazy-gitlab-runner-k8s-tf), which includes improvements and new features:

# History

terraform-kubernetes-gitlab-runner is originated
on [DeimosCloud/terraform-kubernetes-gitlab-runner](https://github.com/DeimosCloud/terraform-kubernetes-gitlab-runner),
but the forked repository had diverged significantly from its parent, so I've decided to detach it.

# TODO

- [ ] add static typing for azure, and s3 `cache` variable

# Terraform Kubernetes Gitlab-Runner Module

Setup Gitlab Runner on cluster using terraform. The runner is installed via
the [Gitlab Runner Helm Chart](https://gitlab.com/gitlab-org/charts/gitlab-runner)

Ensure Kubernetes Provider and Helm Provider settings are
correct https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/guides/getting-started#provider-setup

## Usage

```hcl
module "gitlab_runner" {
  source                    = "DeimosCloud/gitlab-runner/kubernetes"
  release_name              = "${var.project_name}-runner-${var.environment}"
  runner_tags               = var.runner_tags
  runner_registration_token = var.runner_registration_token
  runner_image              = var.runner_image
  namespace                 = var.gitlab_runner_namespace

  # change runner's default image registry settings
  image = {
    registry   = "nexus.my.domain"
    repository = "gitlab/gitlab-runner"
    tag        = "alpine3.18"
  }

  // set default shell
  shell = "bash"

  // increase log limit for verbose jobs
  output_limit = 26000

  rbac {
    create                      = true
    # Pass annotations to service account, e.g. in this case GCP Workload Identity needs it
    service_account_annotations = {
      "iam.gke.io/gcp-service-account" = module.workload_identity["gitlab-runner"].gcp_service_account_email
    }
    rules = [
      {
        resources = ["configmaps", "pods", "pods/attach", "secrets", "services"]
        verbs : ["get", "list", "watch", "create", "patch", "update", "delete"]
      },
      {
        api_groups = [""]
        resources  = ["pods/exec"]
        verbs      = ["create", "patch", "delete"]
      }
    ]
  }

  // job pods will be scheduled with these resource requests/limits 
  job_resources = {
    cpu_request                          = "100m"
    cpu_request_overwrite_max_allowed    = "2000m"
    memory_request                       = "1Gi"
    memory_request_overwrite_max_allowed = "2Gi"

    cpu_limit_overwrite_max_allowed    = "2000m"
    memory_limit_overwrite_max_allowed = "2Gi"

    helper_cpu_request    = "200m"
    helper_memory_request = "256Mi"

    service_cpu_request    = "1000m"
    service_memory_request = "1Gi"
    service_cpu_limit      = "3000m"
    service_memory_limit   = "2Gi"
  }

  # runner resources requests/limits	
  resources = {
    requests = {
      memory = "128Mi"
      cpu    = "100m"
    }
  }

  # enable prometheus metrics
  metrics = {
    enabled = true
  }

  # add this labels to every job's pod
  job_pod_labels = {
    jobId        = "$CI_JOB_ID"
    pipelineId   = "$CI_PIPELINE_ID"
    gitUserLogin = "$GITLAB_USER_LOGIN"
    project      = "$CI_PROJECT_NAME"
  }

  # cache settings
  cache = {
    type        = "gcs"
    path        = "cache"
    shared      = true
    secret_name = kubernetes_secret.gcscred.metadata[0].name
    gcs         = {
      bucket_name = module.gcs.bucket_name
    }
  }

  # docker-in-docker cert settings
  build_job_empty_dirs = {
    "docker-certs" = {
      mount_path = "/certs/client"
      medium     = "Memory"
    }
  }

  # simple runner and job environment variables setting, e.g. HTTPS_PROXY
  envs = [
    {
      name   = "HTTPS_PROXY"
      value  = "http://proxy.net.int:3128"
      job    = true #job container sees that variable
      runner = true #runner also sees that var
    },
    {
      name   = "FOO"
      value  = "bar"
      job    = true
      runner = false #only job needs this env variable
    }
  ]
}
```

### Custom Values

To pass in custom values use the `var.values` input which specifies a map of values in terraform map format
or `var.values_file` which specifies a path containing a valid yaml values file to pass to the Chart

### Hostmounted Directories

There are a few capabilities enabled by using hostmounted directories; let's look at a few examples of config and what
they effectively configure in the config.toml.

#### Docker Socket

The most common hostmount is simply sharing the docker socket to allow the build container to start new containers, but
avoid a Docker-in-Docker config. This is useful to take an unmodified `docker build ...` command from your current build
process, and copy it to a .gitlab-ci.yaml or a github action. To map your docker socket from the docker host to the
container, you need to (as above):

```hcl
module "gitlab_runner" {
  ...
build_job_mount_docker_socket = true
...
}
```

This causes the config.toml to create two sections:

```toml
[runners.kubernetes.pod_security_context]
      ...
      fs_group = ${var.docker_fs_group}
      ...
```

This first section defines a Kubernetes Pod Security Policy that causes the mounted filesystem to have the group value
overwritten to this GID (
see https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod).
Combined with a `runAsGroup` in Kubernetes, this would ensure that the files in the container are writeable by the
process running as a defined GID.

Additionally, the config.toml gains a host_path config:

```toml
    [runners.kubernetes.volumes]
      ...
      [[runners.kubernetes.volumes.host_path]]
        name = "docker-socket"
        mount_path = "/var/run/docker.sock"
        read_only = true
        host_path = "/var/run/docker.sock"
      ...
```

This causes the `/var/run/docker.sock` "volume" (really a Unix-Domain Socket) at the default path to communicate with
the docker engine to bemounted in the same location inside the container. The mount is marked "read_only" because the
filesystem cannot have filesystem objects added to it (you're not going to add file or directories to the socket UDS)
but the docker command can still write to the socket to send commands.

#### Statsd for Metrics

The standard way of collecting metrics from a Gitlab-Runner is to enable the Prometheus endpoint, and subscribe it for
scraping; what if you want to send events? Statsd has a timer (the Datadog implementation does not), but you can expose
the UDS from statsd or dogstatsd to allow simple netcat-based submisison of build events and timings if desired.

For example, the standard UDS for Dogstatsd, the Datadog mostly-drop-in replacement for statsd, is
at `/var/run/datadog/dsd.socket`. I chose to share that entire directory into the build container as follows:

```hcl
module "gitlab_runner" {
  ...
build_job_hostmounts = {
  dogstatsd = { host_path = "/var/run/datadog" }
}
...
}
```

You may notice that I haven't set a `container_path` to define the `mount_path` in the container at which the host's
volume should be mounted. If it's not defined, `container_path` defaults to the `host_path`.

This causes the config.toml to create a host_path section:

```toml
    [runners.kubernetes.volumes]
      ...
      [[runners.kubernetes.volumes.host_path]]
        name = "dogstatsd"
        mount_path = "/var/run/datadog"
        read_only = false
        host_path = "/var/run/datadog"
      ...
```

This allows the basic submission of custom metrics to be done with, say, netcat as per the Datadog
instructions (https://docs.datadoghq.com/developers/dogstatsd/unix_socket/?tab=host#test-with-netcat):

```shell
echo -n "custom.metric.name:1|c" | nc -U -u -w1 /var/run/datadog/dsd.socket
```

If I wanted a non-standard path inside the container (so that, say, some rogue process doesn't automatically log to a
socket if it's present in the default location) re can remap the UDS in the contrived example that follows.

#### Statsd for Metrics, nonstandard path

As noted above, a contrived example of mounting in a different path might be some corporate service/daemon in a
container that automatically tries to submit metrics if it sees the socket in the filesystem. Lacking the source or
permission to change that automation, but wanting to use the UDS ourselves to sink metrics, we can mount it at a
different nonstandard location.

This isn't the best example, but there are stranger things in corporate software than I can dream up.

In order to make this UDS appear at a different location, you could do the following. Note that you might want to refer
to the actual socket rather than the containing directory as the docker.sock is done above. That likely makes more
sense, but to keep parallelism with the dogstatsd example that I (chickenandpork) am using daily, let's map the
containing directory: let's map /var/run/datadog/ in the host to the container's /var/run/metrics/ path:

```hcl
module "gitlab_runner" {
  ...
build_job_hostmounts = {
  dogstatsd = {
    host_path      = "/var/run/datadog"
    container_path = "/var/run/metrics"
  }
}
...
}
```

This causes the config.toml to create a host_path section:

```toml
    [runners.kubernetes.volumes]
      ...
      [[runners.kubernetes.volumes.host_path]]
        name = "dogstatsd"
        mount_path = "/var/run/metrics"
        read_only = false
        host_path = "/var/run/datadog"
      ...
```

The result is that the Unix -Domain Socket is available at a non-standard location that our custom tools can use, but
anything looking in the conventional default location won't see anything.

Although you'd likely use a proper binary to sink metrics in production, you can manually log metrics to test inside the
container (or in your build script) using:

```shell
echo -n "custom.metric.name:1|c" | nc -U -u -w1 /var/run/metrics/dsd.socket
```

In production, you'd likely also make this `read_only`, use filesystem permissions to guard access, and likely too
simply configure or improve the errant software, but there are strange side-effects and constraints of long-lived
software in industry.

#### Shared Certificates

If you're using the TLS docker connection to do docker builds in your CI, and you don't set an empty TLS_CERTS
directory, then the docker engine recently defaults to creating certificates, and requiring TLS. In order to have these
certificates available to your build-container's docker command, you may need to share that certificate directory back
into the buid container.

This can be done with:

```hcl
module "gitlab_runner" {
  #...
  build_job_empty_dirs = {
    "docker-certs" = {
      mount_path = "/certs/client"
      medium     = "Memory"
    }
  }
  #...
}
```

This causes the config.toml to create a host_path section:

```toml
    [runners.kubernetes.volumes]
      ...
        [[runners.kubernetes.volumes.empty_dir]]
        name = "docker-certs
        mount_path = "/certs/client
        medium = "Memory"
      ...
```

In your build, you may need to define the enviroment variables:

- `DOCKER_TLS_CERTDIR: /certs`,
- `DOCKER_TLS_VERIFY: 1`
- `DOCKER_CERT_PATH: "$DOCKER_TLS_CERTDIR/client"`
  The docker CLI should use the TLS tcp/2376 port if it sees a `DOCKER_TLS_CERTDIR`,
  but if not, `--host` argument or `DOCKER_HOST=tcp://hostname:2376/` are some options to steer it to the correct
  port/protocol.

## Contributing

Report issues/questions/feature requests on in the issues section.

Full contributing guidelines are covered [here](CONTRIBUTING.md).

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.3 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.10 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.22 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | 2.10.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_affinity_transformer"></a> [affinity\_transformer](#module\_affinity\_transformer) | git::https://github.com/MaciekLeks/case-style-transformer.git | 0.2.0 |
| <a name="module_hpa"></a> [hpa](#module\_hpa) | git::https://github.com/MaciekLeks/case-style-transformer.git | 0.2.0 |
| <a name="module_resources"></a> [resources](#module\_resources) | git::https://github.com/MaciekLeks/case-style-transformer.git | 0.2.0 |
| <a name="module_topology_spread_constraints"></a> [topology\_spread\_constraints](#module\_topology\_spread\_constraints) | git::https://github.com/MaciekLeks/case-style-transformer.git | 0.2.0 |

## Resources

| Name | Type |
|------|------|
| [helm_release.gitlab_runner](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_affinity"></a> [affinity](#input\_affinity) | Affinity for pod assignment. | <pre>object({<br>    node_affinity : optional(object({<br>      preferred_during_scheduling_ignored_during_execution : optional(list(object({<br>        weight : number<br>        preference : object({<br>          match_expressions : optional(list(object({<br>            key : string<br>            operator : string<br>            values : list(string)<br>          })))<br>          match_fields : optional(list(object({<br>            key : string<br>            operator : string<br>            values : list(string)<br>          })))<br>        })<br>      })))<br>      required_during_scheduling_ignored_during_execution : optional(list(object({<br>        node_selector_terms : object({<br>          match_expressions : optional(object({<br>            key : string<br>            operator : string<br>            values : list(string)<br>          }))<br>          match_fields : optional(object({<br>            key : string<br>            operator : string<br>            values : list(string)<br>          }))<br>        })<br>      })))<br>    }), {})<br><br>    pod_affinity : optional(object({<br>      preferred_during_scheduling_ignored_during_execution : optional(list(object({<br>        pod_affinity_term : object({<br>          weight : number<br>          topology_key : string<br>          namespaces : optional(list(string))<br>          label_selector : optional(object({<br>            match_expressions : optional(list(object({<br>              key : string<br>              operator : string<br>              values : list(string)<br>            })))<br>            match_labels : optional(list(string))<br>          }))<br>          namespace_selector : optional(object({<br>            match_expressions : optional(list(object({<br>              key : string<br>              operator : string<br>              values : list(string)<br>            })))<br>            match_labels : optional(list(string))<br>          }))<br>        })<br>      })))<br>      required_during_scheduling_ignored_during_execution : optional(list(object({<br>        topology_key : string<br>        namespaces : optional(list(string))<br>        label_selector : optional(object({<br>          match_expressions : optional(list(object({<br>            key : string<br>            operator : string<br>            values : list(string)<br>          })))<br>          match_labels : optional(list(string))<br>        }))<br>        namespace_selector : optional(object({<br>          match_expressions : optional(list(object({<br>            key : string<br>            operator : string<br>            values : list(string)<br>          })))<br>          match_labels : optional(list(string))<br>        }))<br>      })))<br>    }), {})<br><br>    pod_anti_affinity : optional(object({<br>      preferred_during_scheduling_ignored_during_execution : optional(list(object({<br>        pod_affinity_term : object({<br>          weight : number<br>          topology_key : string<br>          namespaces : optional(list(string))<br>          label_selector : optional(object({<br>            match_expressions : optional(list(object({<br>              key : string<br>              operator : string<br>              values : list(string)<br>            })))<br>            match_labels : optional(list(string))<br>          }))<br>          namespace_selector : optional(object({<br>            match_expressions : optional(list(object({<br>              key : string<br>              operator : string<br>              values : list(string)<br>            })))<br>            match_labels : optional(list(string))<br>          }))<br>        })<br>      })))<br>      required_during_scheduling_ignored_during_execution : optional(list(object({<br>        topology_key : string<br>        namespaces : optional(list(string))<br>        label_selector : optional(object({<br>          match_expressions : optional(list(object({<br>            key : string<br>            operator : string<br>            values : list(string)<br>          })))<br>          match_labels : optional(list(string))<br>        }))<br>        namespace_selector : optional(object({<br>          match_expressions : optional(list(object({<br>            key : string<br>            operator : string<br>            values : list(string)<br>          })))<br>          match_labels : optional(list(string))<br>        }))<br>      })))<br>    }), {})<br>  })</pre> | `{}` | no |
| <a name="input_atomic"></a> [atomic](#input\_atomic) | whether to deploy the entire module as a unit | `bool` | `true` | no |
| <a name="input_build_job_default_container_image"></a> [build\_job\_default\_container\_image](#input\_build\_job\_default\_container\_image) | Default container image to use for builds when none is specified | `string` | `"ubuntu:20.04"` | no |
| <a name="input_build_job_empty_dirs"></a> [build\_job\_empty\_dirs](#input\_build\_job\_empty\_dirs) | A map of name:{mount\_path, medium} for which each named value will result in a named empty\_dir mounted with. | <pre>map(object({<br>    mount_path : string<br>    medium : string<br>    size_limit : optional(string, null)<br>  }))</pre> | `{}` | no |
| <a name="input_build_job_hostmounts"></a> [build\_job\_hostmounts](#input\_build\_job\_hostmounts) | A list of maps of name:{host\_path, container\_path, read\_only} for which each named value will result in a hostmount of the host path to the container at container\_path.  If not given, container\_path fallsback to host\_path:   dogstatsd = { host\_path = '/var/run/dogstatsd' } will mount the host /var/run/dogstatsd to the same path in container. | `map(map(any))` | `{}` | no |
| <a name="input_build_job_mount_docker_socket"></a> [build\_job\_mount\_docker\_socket](#input\_build\_job\_mount\_docker\_socket) | Path on nodes for caching | `bool` | `false` | no |
| <a name="input_build_job_privileged"></a> [build\_job\_privileged](#input\_build\_job\_privileged) | Run all containers with the privileged flag enabled. This will allow the docker:dind image to run if you need to run Docker | `bool` | `false` | no |
| <a name="input_build_job_run_container_as_user"></a> [build\_job\_run\_container\_as\_user](#input\_build\_job\_run\_container\_as\_user) | SecurityContext: runAsUser for all running job pods | `string` | `null` | no |
| <a name="input_build_job_secret_volumes"></a> [build\_job\_secret\_volumes](#input\_build\_job\_secret\_volumes) | Secret volume configuration instructs Kubernetes to use a secret that is defined in Kubernetes cluster and mount it inside of the containes as defined https://docs.gitlab.com/runner/executors/kubernetes.html#secret-volumes | <pre>object({<br>    name       = string<br>    mount_path = string<br>    read_only  = string<br>    items      = map(string)<br>  })</pre> | <pre>{<br>  "items": {},<br>  "mount_path": null,<br>  "name": null,<br>  "read_only": null<br>}</pre> | no |
| <a name="input_cache"></a> [cache](#input\_cache) | Describes the properties of the cache. type can be either of ['local', 'gcs', 's3', 'azure'], path defines a path to append to the bucket url, shared specifies whether the cache can be shared between runners. you also specify the individual properties of the particular cache type you select. see https://docs.gitlab.com/runner/configuration/advanced-configuration.html#the-runnerscache-section | <pre>object({<br>    type   = optional(string, "local")<br>    path   = optional(string, "")<br>    shared = optional(bool)<br>    gcs = optional(object({<br>      credentials_file : optional(string)<br>      access_id : optional(string)<br>      private_key : optional(string)<br>      bucket_name : string<br>    }))<br>    s3          = optional(map(any), {}) //TODO: add static typing as for gcs<br>    azure       = optional(map(any), {}) //TODO: add static typing as for gcs<br>    secret_name = optional(string)<br>  })</pre> | `null` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | The version of the chart | `string` | `"0.40.1"` | no |
| <a name="input_check_interval"></a> [check\_interval](#input\_check\_interval) | Defines in seconds how often to check GitLab for a new builds. | `number` | `30` | no |
| <a name="input_concurrent"></a> [concurrent](#input\_concurrent) | Configure the maximum number of concurrent jobs | `number` | `10` | no |
| <a name="input_config_maps"></a> [config\_maps](#input\_config\_maps) | Additional map merged with the default runner ConfigMap. | `map(string)` | `null` | no |
| <a name="input_create_namespace"></a> [create\_namespace](#input\_create\_namespace) | (Optional) Create the namespace if it does not yet exist. Defaults to false. | `bool` | `true` | no |
| <a name="input_docker_fs_group"></a> [docker\_fs\_group](#input\_docker\_fs\_group) | The fsGroup to use for docker. This is added to security context when mount\_docker\_socket is enabled | `number` | `412` | no |
| <a name="input_envs"></a> [envs](#input\_envs) | Environment variable to be set for either runner or job or both. | <pre>list(object({<br>    name   = string<br>    value  = string<br>    job    = optional(bool)<br>    runner = optional(bool)<br>  }))</pre> | `[]` | no |
| <a name="input_gitlab_url"></a> [gitlab\_url](#input\_gitlab\_url) | The GitLab Server URL (with protocol) that want to register the runner against | `string` | `"https://gitlab.com/"` | no |
| <a name="input_health_check"></a> [health\_check](#input\_health\_check) | Health check options for the runner to check it's health. Supports only timeoutSeconds. | <pre>object({<br>    timeout_seconds : optional(number, 3) #maps to .Values.probeTimeoutSeconds :/<br>  })</pre> | `{}` | no |
| <a name="input_helper_job_container_image"></a> [helper\_job\_container\_image](#input\_helper\_job\_container\_image) | Helper container image. | `string` | `null` | no |
| <a name="input_host_aliases"></a> [host\_aliases](#input\_host\_aliases) | List of hosts and IPs that will be injected into the pod's hosts file. | <pre>list(object({<br>    ip : string<br>    hostnames : list(string)<br>  }))</pre> | `[]` | no |
| <a name="input_hpa"></a> [hpa](#input\_hpa) | Horizontal Pod Autoscaling with API limited to metrics specification only (api/version: autoscaling/v2). | <pre>object({<br>    min_replicas : number<br>    max_replicas : number<br>    metrics : list(object({<br>      type : string<br>      pods : object({<br>        metric : object({<br>          name : string<br>        })<br>        target : object({<br>          type : string<br>          average_value : optional(string)<br>          average_utilization : optional(number)<br>          value : optional(string)<br>        })<br>      })<br>    }))<br>  })</pre> | `null` | no |
| <a name="input_image"></a> [image](#input\_image) | The docker gitlab runner image. | <pre>object({<br>    registry : optional(string, "registry.gitlab.com")<br>    image : optional(string, "gitlab/gitlab-runner")<br>    tag : optional(string)<br>  })</pre> | `{}` | no |
| <a name="input_image_pull_policy"></a> [image\_pull\_policy](#input\_image\_pull\_policy) | Specify the job images pull policy: Never, IfNotPresent, Always. | `string` | `"IfNotPresent"` | no |
| <a name="input_image_pull_secrets"></a> [image\_pull\_secrets](#input\_image\_pull\_secrets) | A array of secrets that are used to authenticate Docker image pulling. | `list(string)` | `[]` | no |
| <a name="input_job_affinity"></a> [job\_affinity](#input\_job\_affinity) | Specify affinity rules that determine which node runs the job. No HCL support for this variable. Use string interpolation if needed. | `string` | `""` | no |
| <a name="input_job_identity"></a> [job\_identity](#input\_job\_identity) | Default service account job pods use to talk to Kubernetes API. | <pre>object({<br>    service_account                   = optional(string)<br>    service_account_overwrite_allowed = optional(string)<br>  })</pre> | `{}` | no |
| <a name="input_job_pod_annotations"></a> [job\_pod\_annotations](#input\_job\_pod\_annotations) | A map of annotations to be added to each build pod created by the Runner. The value of these can include environment variables for expansion. Pod annotations can be overwritten in each build. | `map(string)` | `{}` | no |
| <a name="input_job_pod_labels"></a> [job\_pod\_labels](#input\_job\_pod\_labels) | A map of labels to be added to each build pod created by the runner. The value of these can include environment variables for expansion. | `map(string)` | `{}` | no |
| <a name="input_job_pod_node_selectors"></a> [job\_pod\_node\_selectors](#input\_job\_pod\_node\_selectors) | A map of node selectors to apply to the pods | `map(string)` | `{}` | no |
| <a name="input_job_pod_node_tolerations"></a> [job\_pod\_node\_tolerations](#input\_job\_pod\_node\_tolerations) | A map of node tolerations to apply to the pods as defined https://docs.gitlab.com/runner/executors/kubernetes.html#other-configtoml-settings | `map(string)` | `{}` | no |
| <a name="input_job_resources"></a> [job\_resources](#input\_job\_resources) | The CPU and memory resources given to service containers. | <pre>object({<br>    //builder containers<br>    cpu_limit : optional(string)<br>    cpu_limit_overwrite_max_allowed : optional(string)<br>    cpu_request : optional(string)<br>    cpu_request_overwrite_max_allowed : optional(string)<br>    memory_limit : optional(string)<br>    memory_limit_overwrite_max_allowed : optional(string)<br>    memory_request : optional(string)<br>    memory_request_overwrite_max_allowed : optional(string)<br>    ephemeral_storage_limit : optional(string)<br>    ephemeral_storage_limit_overwrite_max_allowed : optional(string)<br>    ephemeral_storage_request : optional(string)<br>    ephemeral_storage_request_overwrite_max_allowed : optional(string)<br><br>    //helper containers<br>    helper_cpu_limit : optional(string)<br>    helper_cpu_limit_overwrite_max_allowed : optional(string)<br>    helper_cpu_request : optional(string)<br>    helper_cpu_request_overwrite_max_allowed : optional(string)<br>    helper_memory_limit : optional(string)<br>    helper_memory_limit_overwrite_max_allowed : optional(string)<br>    helper_memory_request : optional(string)<br>    helper_memory_request_overwrite_max_allowed : optional(string)<br>    helper_ephemeral_storage_limit : optional(string)<br>    helper_ephemeral_storage_limit_overwrite_max_allowed : optional(string)<br>    helper_ephemeral_storage_request : optional(string)<br>    helper_ephemeral_storage_request_overwrite_max_allowed : optional(string)<br><br>    // service containers<br>    service_cpu_limit : optional(string)<br>    service_cpu_limit_overwrite_max_allowed : optional(string)<br>    service_cpu_request : optional(string)<br>    service_cpu_request_overwrite_max_allowed : optional(string)<br>    service_memory_limit : optional(string)<br>    service_memory_limit_overwrite_max_allowed : optional(string)<br>    service_memory_request : optional(string)<br>    service_memory_request_overwrite_max_allowed : optional(string)<br>    service_ephemeral_storage_limit : optional(string)<br>    service_ephemeral_storage_limit_overwrite_max_allowed : optional(string)<br>    service_ephemeral_storage_request : optional(string)<br>    service_ephemeral_storage_request_overwrite_max_allowed : optional(string)<br>  })</pre> | `{}` | no |
| <a name="input_local_cache_dir"></a> [local\_cache\_dir](#input\_local\_cache\_dir) | Path on nodes for caching | `string` | `"/tmp/gitlab/cache"` | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Configure GitLab Runner's logging level. Available values are: debug, info, warn, error, fatal, panic. | `string` | `"info"` | no |
| <a name="input_metrics"></a> [metrics](#input\_metrics) | Configure integrated Prometheus metrics exporter. | <pre>object({<br>    enabled : optional(bool, false)<br>    port_name : optional(string, "metrics")<br>    port : optional(number, 9252)<br>    service_monitor : optional(object({<br>      enabled : optional(bool, false)<br>      labels : optional(map(string), {})<br>      interval : optional(string, "1m")<br>      scheme : optional(string, "http")<br>      tls_config : optional(map(string), {})<br>      path : optional(string, "/metrics")<br>      metric_relabeling : optional(list(string), [])<br>      relabelings : optional(list(string), [])<br>    }), {})<br>  })</pre> | `{}` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | n/a | `string` | `"gitlab-runner"` | no |
| <a name="input_node_selector"></a> [node\_selector](#input\_node\_selector) | A map of node selectors to apply to the pods | `map(string)` | `{}` | no |
| <a name="input_output_limit"></a> [output\_limit](#input\_output\_limit) | Maximum build log size in kilobytes. Default is 4096 (4MB). | `number` | `null` | no |
| <a name="input_pod_annotations"></a> [pod\_annotations](#input\_pod\_annotations) | A map of annotations to be added to each build pod created by the Runner. The value of these can include environment variables for expansion. Pod annotations can be overwritten in each build. | `map(string)` | `{}` | no |
| <a name="input_pod_labels"></a> [pod\_labels](#input\_pod\_labels) | A map of labels to be added to each build pod created by the runner. The value of these can include environment variables for expansion. | `map(string)` | `{}` | no |
| <a name="input_pod_security_context"></a> [pod\_security\_context](#input\_pod\_security\_context) | Runner POD security context. | <pre>object({<br>    run_as_user : optional(number, 100)<br>    run_as_group : optional(number, 65533)<br>    fs_group : optional(number, 65533)<br>    supplemental_groups : optional(list(number), [])<br>  })</pre> | `{}` | no |
| <a name="input_poll"></a> [poll](#input\_poll) | Polling options for the runner to poll it's job pods. | <pre>object({<br>    interval : optional(number, 3)<br>    timeout : optional(number, 180)<br>  })</pre> | `{}` | no |
| <a name="input_priority_class_name"></a> [priority\_class\_name](#input\_priority\_class\_name) | Configure priorityClassName for the runner pod. If not set, globalDefault priority class is used. | `string` | `""` | no |
| <a name="input_pull_policy"></a> [pull\_policy](#input\_pull\_policy) | Specify the job images pull policy: never, if-not-present, always. | `set(string)` | <pre>[<br>  "if-not-present"<br>]</pre> | no |
| <a name="input_rbac"></a> [rbac](#input\_rbac) | RBAC support. | <pre>object({<br>    //create : optional(bool, false) #create k8s SA and apply RBAC roles #depreciated<br>    //resources : optional(list(string), ["pods", "pods/exec", "pods/attach", "secrets", "configmaps"])<br>    //verbs : optional(list(string), ["get", "list", "watch", "create", "patch", "delete"])<br>    rules : optional(list(object({<br>      resources : optional(list(string), [])<br>      api_groups : optional(list(string), [""])<br>      verbs : optional(list(string))<br>    })), [])<br><br>    cluster_wide_access : optional(bool, false)<br>    #service_account_name : optional(string, "default") #depreciated <br>    #service_account_annotations : optional(map(string), {}) #depreciated<br>    pod_security_policy : optional(object({<br>      enabled : optional(bool, false)<br>      resource_names : optional(list(string), [])<br>    }), { enabled : false })<br>  })</pre> | `{}` | no |
| <a name="input_release_name"></a> [release\_name](#input\_release\_name) | The helm release name | `string` | `"gitlab-runner"` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | The number of runner pods to create. | `number` | `1` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | The CPU and memory resources given to the runner. | <pre>object({<br>    requests = optional(object({<br>      cpu               = optional(string)<br>      memory            = optional(string)<br>      ephemeral_storage = optional(string)<br>    })), #TODO: null is ok?<br>    limits = optional(object({<br>      cpu               = optional(string)<br>      memory            = optional(string)<br>      ephemeral_storage = optional(string)<br>    })) #TODO: null ia ok?<br>  })</pre> | `null` | no |
| <a name="input_run_untagged_jobs"></a> [run\_untagged\_jobs](#input\_run\_untagged\_jobs) | Specify if jobs without tags should be run. https://docs.gitlab.com/ce/ci/runners/#runner-is-allowed-to-run-untagged-jobs | `bool` | `false` | no |
| <a name="input_runner_locked"></a> [runner\_locked](#input\_runner\_locked) | Specify whether the runner should be locked to a specific project/group | `string` | `true` | no |
| <a name="input_runner_name"></a> [runner\_name](#input\_runner\_name) | The runner's description. | `string` | n/a | yes |
| <a name="input_runner_registration_token"></a> [runner\_registration\_token](#input\_runner\_registration\_token) | runner registration token | `string` | n/a | yes |
| <a name="input_runner_tags"></a> [runner\_tags](#input\_runner\_tags) | Specify the tags associated with the runner. Comma-separated list of tags. | `string` | n/a | yes |
| <a name="input_runner_token"></a> [runner\_token](#input\_runner\_token) | token of already registered runer. to use this var.runner\_registration\_token must be set to null | `string` | `null` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Secrets to mount into the runner pods | `list(map(string))` | `[]` | no |
| <a name="input_security_context"></a> [security\_context](#input\_security\_context) | Runner container security context. | <pre>object({<br>    allow_privilege_escalation : optional(bool, false)<br>    read_only_root_filesystem : optional(bool, false)<br>    run_as_non_root : optional(bool, true)<br>    privileged : optional(bool, false)<br>    capabilities : optional(object({<br>      add : optional(list(string), [])<br>      drop : optional(list(string), [])<br>    }), { drop : ["ALL"] })<br>  })</pre> | `{}` | no |
| <a name="input_service"></a> [service](#input\_service) | Configure a service resource e.g., to allow scraping metrics via prometheus-operator serviceMonitor. | <pre>object({<br>    enabled : optional(bool, false)<br>    labels : optional(map(string), {})<br>    annotations : optional(map(string), {})<br>    cluster_ip : optional(string, "")<br>    external_ips : optional(list(string), [])<br>    load_balancer_ip : optional(string, "")<br>    load_balancer_source_ranges : optional(list(string), [])<br>    type : optional(string, "ClusterIP")<br>    node_port : optional(string, "")<br>    additional_ports : optional(list(string), [])<br>  })</pre> | `{}` | no |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | The name of the k8s service account to create (since 17.x.x) | <pre>object({<br>    create             = optional(bool, false)<br>    name               = optional(string, "")<br>    annotations        = optional(map(string), {})<br>    image_pull_secrets = optional(list(string), [])<br>  })</pre> | n/a | yes |
| <a name="input_shell"></a> [shell](#input\_shell) | Name of shell to generate the script. | `string` | `null` | no |
| <a name="input_shutdown_timeout"></a> [shutdown\_timeout](#input\_shutdown\_timeout) | Number of seconds until the forceful shutdown operation times out and exits the process. The default value is 30. If set to 0 or lower, the default value is used. | `number` | `0` | no |
| <a name="input_termination_grace_period_seconds"></a> [termination\_grace\_period\_seconds](#input\_termination\_grace\_period\_seconds) | When stopping the runner, give it time (in seconds) to wait for its jobs to terminate. | `number` | `3600` | no |
| <a name="input_tolerations"></a> [tolerations](#input\_tolerations) | A map of node tolerations to apply to the pods as defined https://docs.gitlab.com/runner/executors/kubernetes.html#other-configtoml-settings | <pre>list(object({<br>    key : string<br>    operator : string<br>    effect : string<br>  }))</pre> | `null` | no |
| <a name="input_topology_spread_constraints"></a> [topology\_spread\_constraints](#input\_topology\_spread\_constraints) | TopologySpreadConstraints for pod assignment. | <pre>list(object({<br>    max_skew : number<br>    topology_key : string<br>    when_unsatisfiable : string<br>    label_selector : object({<br>      match_labels : optional(map(string), {})<br>      match_expressions : optional(list(object({<br>        key : string<br>        operator : string<br>        values : list(string)<br>      })), [])<br>    })<br>  }))</pre> | `null` | no |
| <a name="input_unhealthy_interval"></a> [unhealthy\_interval](#input\_unhealthy\_interval) | Duration that a runner worker is disabled for after it exceeds the unhealthy requests limit. Supports syntax like ‘3600s’, ‘1h30min’ etc. | `string` | `"120s"` | no |
| <a name="input_unhealthy_requests_limit"></a> [unhealthy\_requests\_limit](#input\_unhealthy\_requests\_limit) | The number of unhealthy responses to new job requests after which a runner worker will be disabled. | `number` | `30` | no |
| <a name="input_unregister_runners"></a> [unregister\_runners](#input\_unregister\_runners) | whether runners should be unregistered when pool is deprovisioned | `bool` | `true` | no |
| <a name="input_values"></a> [values](#input\_values) | Additional values to be passed to the gitlab-runner helm chart | `map(any)` | `{}` | no |
| <a name="input_values_file"></a> [values\_file](#input\_values\_file) | Path to Values file to be passed to gitlab-runner helm chart | `string` | `null` | no |
| <a name="input_volume_mounts"></a> [volume\_mounts](#input\_volume\_mounts) | Additional volumeMounts to add to the runner container. | <pre>list(object({<br>    mount_path : string<br>    name : string<br>    mount_propagation : optional(string)<br>    read_only : optional(bool, false)<br>    sub_path : optional(string)<br>    sub_path_expr : optional(string)<br>  }))</pre> | `[]` | no |
| <a name="input_volumes"></a> [volumes](#input\_volumes) | Additional volumes to add to the runner pod. No HCL support here yet. Please use camel case for this variable. | `list(any)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_chart_version"></a> [chart\_version](#output\_chart\_version) | The chart version |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | The namespace gitlab-runner was deployed in |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | The helm release name |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
