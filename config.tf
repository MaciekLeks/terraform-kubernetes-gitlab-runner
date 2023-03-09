locals {
  config = <<EOF
[[runners]]
  name = "${var.runner_name}"
  executor = "kubernetes"
  shell = "${var.shell}"
%{if var.cache.type == "local"~}
  cache_dir = "${var.local_cache_dir}"
%{~else~}
  [runners.cache]
    Type = "${var.cache.type}"
    Path = "${var.cache.path}"
    Shared = ${var.cache.shared}
    [runners.cache.s3]
    %{~for key, value in var.cache.s3~}
      "${key}" = "${value}"
    %{~endfor~}
    [runners.cache.gcs]
    %{~for key, value in var.cache.gcs~}
      "${key}" = "${value}"
    %{~endfor~}
    [runners.cache.azure]
    %{~for key, value in var.cache.azure~}
      "${key}" = "${value}"
    %{~endfor~}
%{~endif}
  [runners.kubernetes]
    cpu_limit = "${var.job_build_container_resources.limits.cpu}"
    cpu_limit_overwrite_max_allowed = "${var.job_build_container_resources.limits.cpu_overwrite_max_allowed}"
    cpu_request = "${var.job_build_container_resources.requests.cpu}"
    cpu_request_overwrite_max_allowed = "${var.job_build_container_resources.requests.cpu_overwrite_max_allowed}"
    memory_limit = "${var.job_build_container_resources.limits.memory}"
    memory_limit_overwrite_max_allowed = "${var.job_build_container_resources.limits.memory_overwrite_max_allowed}"
    memory_request = "${var.job_build_container_resources.requests.memory}"
    memory_request_overwrite_max_allowed = "${var.job_build_container_resources.requests.cpu_overwrite_max_allowed}"

    helper_cpu_limit = "${var.job_helper_container_resources.limits.cpu}"
    helper_cpu_limit_overwrite_max_allowed = "${var.job_helper_container_resources.limits.cpu_overwrite_max_allowed}"
    helper_cpu_request = "${var.job_helper_container_resources.requests.cpu}"
    helper_cpu_request_overwrite_max_allowed = "${var.job_helper_container_resources.requests.cpu_overwrite_max_allowed}"
    helper_memory_limit = "${var.job_helper_container_resources.limits.memory}"
    helper_memory_limit_overwrite_max_allowed = "${var.job_helper_container_resources.limits.memory_overwrite_max_allowed}"
    helper_memory_request = "${var.job_helper_container_resources.requests.memory}"
    helper_memory_request_overwrite_max_allowed = "${var.job_helper_container_resources.requests.cpu_overwrite_max_allowed}"

    service_cpu_limit = "${var.job_service_container_resources.limits.cpu}"
    service_cpu_limit_overwrite_max_allowed = "${var.job_service_container_resources.limits.cpu_overwrite_max_allowed}"
    service_cpu_request = "${var.job_service_container_resources.requests.cpu}"
    service_cpu_request_overwrite_max_allowed = "${var.job_service_container_resources.requests.cpu_overwrite_max_allowed}"
    service_memory_limit = "${var.job_service_container_resources.limits.memory}"
    service_memory_limit_overwrite_max_allowed = "${var.job_service_container_resources.limits.memory_overwrite_max_allowed}"
    service_memory_request = "${var.job_service_container_resources.requests.memory}"
    service_memory_request_overwrite_max_allowed = "${var.job_service_container_resources.requests.cpu_overwrite_max_allowed}"
  %{~if var.build_job_default_container_image != null~}
    image = "${var.build_job_default_container_image}"
  %{~endif~}
  %{~if var.job_service_account~}
    service_account = "${var.job_service_account}"
  %{~endif~}
    image_pull_secrets = ${jsonencode(var.image_pull_secrets)}
    privileged      = ${var.build_job_privileged}
    [runners.kubernetes.affinity]
    [runners.kubernetes.node_selector]
    %{~for key, value in var.build_job_node_selectors~}
      "${key}" = "${value}"
    %{~endfor~}
    [runners.kubernetes.node_tolerations]
    %{~for key, value in var.build_job_node_tolerations~}
      "${key}" = "${value}"
    %{~endfor~}
    [runners.kubernetes.pod_labels]
    %{~for key, value in var.build_job_pod_labels~}
      "${key}" = "${value}"
    %{~endfor~}
    [runners.kubernetes.pod_annotations]
    %{~for key, value in var.build_job_pod_annotations~}
      "${key}" = "${value}"
    %{~endfor~}
    [runners.kubernetes.pod_security_context]
    %{~if var.build_job_mount_docker_socket~}
      fs_group = ${var.docker_fs_group}
    %{~endif~}
    %{~if var.build_job_run_container_as_user != null~}
      run_as_user: ${var.build_job_run_container_as_user}
    %{~endif~}
    [runners.kubernetes.volumes]
    %{~if var.build_job_mount_docker_socket~}
      [[runners.kubernetes.volumes.host_path]]
        name = "docker-socket"
        mount_path = "/var/run/docker.sock"
        read_only = true
        host_path = "/var/run/docker.sock"
    %{~endif~}
    %{~if var.cache.type == "local"~}
      [[runners.kubernetes.volumes.host_path]]
        name = "cache"
        mount_path = "${var.local_cache_dir}"
        host_path = "${var.local_cache_dir}"
    %{~endif~}
    %{~for name, config in var.build_job_hostmounts~}
      [[runners.kubernetes.volumes.host_path]]
        name = "${name}"
        mount_path = "${lookup(config, "container_path", config.host_path)}"
        host_path = "${config.host_path}"
        read_only = ${lookup(config, "read_only", "false")}
    %{~endfor~}
    %{~if lookup(var.build_job_secret_volumes, "name", null) != null~}
      [[runners.kubernetes.volumes.secret]]
        name = ${lookup(var.build_job_secret_volumes, "name", "")}
        mount_path = ${lookup(var.build_job_secret_volumes, "mount_path", "")}
        read_only = ${lookup(var.build_job_secret_volumes, "read_only", "")}
        [runners.kubernetes.volumes.secret.items]
          %{~for key, value in lookup(var.build_job_secret_volumes, "items", {})~}
            ${key} = ${value}
          %{~endfor~}
    %{~endif~}
EOF
}
