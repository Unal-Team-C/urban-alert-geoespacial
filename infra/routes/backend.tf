terraform {
  backend "s3" {
    bucket       = "urban-alert-tfstate-348364742283"
    key          = "geoespacial/routes.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
