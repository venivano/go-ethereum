
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.default.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.default.master_auth[0].cluster_ca_certificate)

  ignore_annotations = [
    "^autopilot\\.gke\\.io\\/.*",
    "^cloud\\.google\\.com\\/.*"
  ]
}

resource "kubernetes_secret" "dockerconfigjson" {
  metadata {
    name = "dockerconfigjson-github-com"
    labels = {
      lime = "true"
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = "${file("${".dockerconfigjson"}")}"
  }
}

resource "kubernetes_deployment_v1" "default" {
  metadata {
    name = "lime-deployment"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "lime"
      }
    }

    template {
      metadata {
        labels = {
          app = "lime"
        }
      }

      spec {
        container {
          image = "ghcr.io/venivano/go-ethereum:contracts"
          name  = "lime-container"

          port {
            container_port = 8546
            name           = "lime-svc"
          }

          security_context {
            allow_privilege_escalation = false
            privileged                 = false
            read_only_root_filesystem  = false

            capabilities {
              add  = []
              drop = ["NET_RAW"]
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = "live-svc"

              http_header {
                name  = "X-Custom-Header"
                value = "Awesome"
              }
            }

            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }

        security_context {
          run_as_non_root = true

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        toleration {
          effect   = "NoSchedule"
          key      = "kubernetes.io/arch"
          operator = "Equal"
          value    = "amd64"
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "default" {
  metadata {
    name = "lime-app-loadbalancer"
    annotations = {
      "networking.gke.io/load-balancer-type" = "Internal"
    }
  }

  spec {
    selector = {
      app = kubernetes_deployment_v1.default.spec[0].selector[0].match_labels.app
    }

    ip_family_policy = "RequireDualStack"

    port {
      port        = 80
      target_port = kubernetes_deployment_v1.default.spec[0].template[0].spec[0].container[0].port[0].name
    }

    type = "LoadBalancer"
  }

  depends_on = [time_sleep.wait_service_cleanup]
}

resource "time_sleep" "wait_service_cleanup" {
  depends_on = [google_container_cluster.default]

  destroy_duration = "180s"
}
