location          = "eastus2"
azure_environment = "public"

# Github Configuration
owner      = "scottdeland"
repo       = "docker-images"
github_pat = "***update-token-here***"

# Runner Configuration
runner_name     = "ghinfra"
container_image = "ghcr.io/scottdeland/docker-images/gh-runner:latest"
