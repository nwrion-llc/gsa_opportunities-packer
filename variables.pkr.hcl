variable "project_id" {
  type        = string
  description = "GCP project ID to build the image in."
}

variable "zone" {
  type        = string
  description = "GCP zone used for the temporary build VM."
  default     = "us-central1-a"
}

variable "network" {
  type        = string
  description = "VPC network for the build VM (leave default for the auto-created default network)."
  default     = "default"
}

variable "subnetwork" {
  type        = string
  description = "Subnetwork for the build VM. Leave empty to let GCE pick one from --network."
  default     = ""
}

variable "use_internal_ip" {
  type        = bool
  description = "Set true if the build environment can only reach GCP over an internal IP (no external IP on the build VM)."
  default     = false
}

variable "source_image_family" {
  type        = string
  description = "Base image family to build from."
  default     = "ubuntu-2204-lts"
}

variable "source_image_project" {
  type        = string
  description = "Project that publishes source_image_family."
  default     = "ubuntu-os-cloud"
}

variable "machine_type" {
  type        = string
  description = "Machine type for the temporary build VM."
  default     = "e2-medium"
}

variable "disk_size" {
  type        = number
  description = "Boot disk size (GB) for the build VM and resulting image."
  default     = 20
}

variable "ssh_username" {
  type        = string
  description = "Temporary SSH user Packer uses to provision the build VM."
  default     = "packer"
}

variable "image_family" {
  type        = string
  description = "Image family the resulting image is published under."
  default     = "gsa-opportunities-app"
}

variable "python_version" {
  type        = string
  description = "Python version to install."
  default     = "3.13"
}

variable "postgres_version" {
  type        = string
  description = "PostgreSQL major version to install."
  default     = "16"
}
