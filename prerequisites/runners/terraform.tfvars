location          = "useast2"
azure_environment = "public" # or "usgovernment"

# Github Configuration
owner      = "scottdeland"
repo       = "myrepo"
github_pat = "use TF_VAR_github_pat environment variable to set the value for security reasons"

# Runner Configuration
runner_name              = "azuredevrunner"
subnet_name              = "default2"
vnet_resource_group_name = "testvnet"
virtual_network_name     = "testvnet"
container_image          = "ghcr.io/scottdeland/docker-images/gh-runner:latest"
