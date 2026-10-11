provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "urban-alert"
      Service   = "geoespacial"
      ManagedBy = "terraform"
      Stack     = "platform"
    }
  }
}
