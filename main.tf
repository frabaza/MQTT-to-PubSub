# main.tf

# Provider configuration
provider "google" {
  project = var.project_id
  region  = var.region
}

# Variables
variable "project_id" {
  description = "Your GCP project ID"
  type        = string
  default     = "vm-bridge-451619"
}

variable "region" {
  description = "GCP region for deployment"
  type        = string
  default     = "us-central1"
}

variable "mqtt_broker" {
  description = "HiveMQ broker address"
  type        = string
  default     = "test.mosquitto.org"
}

variable "mqtt_port" {
  description = "HiveMQ broker port"
  type        = number
  default     = 1883
}

variable "mqtt_topic" {
  description = "MQTT topic to subscribe to"
  type        = string
  default     = "prueba/mqtt/fernando"
}

# Enable necessary APIs
resource "google_project_service" "compute_api" {
  service = "compute.googleapis.com"
}

resource "google_project_service" "pubsub_api" {
  service = "pubsub.googleapis.com"
}

resource "google_project_service" "artifactregistry_api" {
  service = "artifactregistry.googleapis.com"
}

# Create Artifact Registry repository
resource "google_artifact_registry_repository" "mqtt_bridge_repo" {
  location      = var.region
  repository_id = "mqtt-bridge-repo"
  format        = "DOCKER"
  description   = "Repository for MQTT bridge container"
  depends_on    = [google_project_service.artifactregistry_api]
}

# Create a Pub/Sub topic
resource "google_pubsub_topic" "machine_data_topic" {
  name    = "pubsub_prueba"
  depends_on = [google_project_service.pubsub_api]
}

# Service account for the VM
resource "google_service_account" "bridge_sa" {
  account_id   = "mqtt-bridge-sa"
  display_name = "MQTT Bridge Service Account"
}

# Grant Pub/Sub Publisher role to the service account
resource "google_pubsub_topic_iam_member" "bridge_pubsub_publisher" {
  topic  = google_pubsub_topic.machine_data_topic.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.bridge_sa.email}"
}

# Grant Artifact Registry Reader role to the service account
resource "google_artifact_registry_repository_iam_member" "bridge_ar_reader" {
  location   = google_artifact_registry_repository.mqtt_bridge_repo.location
  repository = google_artifact_registry_repository.mqtt_bridge_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.bridge_sa.email}"
}

# Deploy the VM
resource "google_compute_instance" "mqtt_bridge_vm" {
  name         = "mqtt-bridge-vm"
  machine_type = "e2-micro"
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  # Startup script to install Docker and run the container
metadata_startup_script = <<-EOF
  #!/bin/bash
  set -e  # Exit on error
  echo "Starting metadata script" > /var/log/startup.log
  apt-get update && apt-get install -y docker.io >> /var/log/startup.log 2>&1 || echo "Failed to install Docker" >> /var/log/startup.log
  systemctl enable docker >> /var/log/startup.log 2>&1 || echo "Failed to enable Docker" >> /var/log/startup.log
  systemctl start docker >> /var/log/startup.log 2>&1 || echo "Failed to start Docker" >> /var/log/startup.log
  sleep 10
  echo "Adding user to docker group" >> /var/log/startup.log
  usermod -aG docker Fer >> /var/log/startup.log 2>&1 || echo "Failed to add user to docker group" >> /var/log/startup.log
  echo "Configuring Docker auth" >> /var/log/startup.log
  gcloud auth configure-docker us-central1-docker.pkg.dev --project=vm-bridge-451619 >> /var/log/startup.log 2>&1 || echo "Failed to configure Docker auth" >> /var/log/startup.log
  echo "Pulling Docker image" >> /var/log/startup.log
  until docker pull us-central1-docker.pkg.dev/${var.project_id}/mqtt-bridge-repo/mqtt-bridge:latest; do
    echo "Waiting for image..." >> /var/log/startup.log
    sleep 5
  done >> /var/log/startup.log 2>&1 || echo "Failed to pull image" >> /var/log/startup.log
  echo "Running container" >> /var/log/startup.log
  docker run -d --restart=always \
    -e MQTT_BROKER="${var.mqtt_broker}" \
    -e MQTT_PORT="${var.mqtt_port}" \
    -e MQTT_TOPIC="${var.mqtt_topic}" \
    -e PUBSUB_TOPIC="projects/${var.project_id}/topics/${google_pubsub_topic.machine_data_topic.name}" \
    us-central1-docker.pkg.dev/${var.project_id}/mqtt-bridge-repo/mqtt-bridge:latest >> /var/log/startup.log 2>&1 || echo "Failed to start container" >> /var/log/startup.log
  echo "Script completed" >> /var/log/startup.log
EOF

  service_account {
    email  = google_service_account.bridge_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [
    google_project_service.compute_api,
    google_project_service.pubsub_api,
    google_project_service.artifactregistry_api,
    google_artifact_registry_repository.mqtt_bridge_repo
  ]
}

# Outputs
output "vm_external_ip" {
  value = google_compute_instance.mqtt_bridge_vm.network_interface[0].access_config[0].nat_ip
}

output "pubsub_topic_name" {
  value = google_pubsub_topic.machine_data_topic.name
}