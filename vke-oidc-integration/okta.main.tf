# Setup OKTA groups
resource "okta_group" "k8s_admin_group" {
  name        = "k8s-admins"
  description = "Users who can access k8s cluster as admins"
}

resource "okta_group" "k8s_restricted_users_group" {
  name        = "k8s-restricted-users"
  description = "Users who can only view pods and services in default namespace"
}

# Assign users to the groups
data "okta_user" "admin" {
  search {
    name  = "profile.email"
    value = var.admin_email
  }
}

resource "okta_group_memberships" "admin_user" {
  group_id = okta_group.k8s_admin_group.id
  users = [
    data.okta_user.admin.id
  ]
}

data "okta_user" "restricted_user" {
  search {
    name  = "profile.email"
    value = var.restricted_email
  }
}

resource "okta_group_memberships" "restricted_user" {
  group_id = okta_group.k8s_restricted_users_group.id
  users = [
    data.okta_user.restricted_user.id
  ]
}

# Create an OIDC application
resource "okta_app_oauth" "k8s_oidc" {
  label                      = "VKE OIDC"
  type                       = "web" # this is important
  pkce_required = true
  token_endpoint_auth_method = "client_secret_post" 
  grant_types = [
    "authorization_code"
  ]
  response_types = ["code"]
  redirect_uris = [
    "http://localhost:8000",
    "http://localhost:18000"
  ]
  post_logout_redirect_uris = [
    "http://localhost:8000",
  ]
}

output "k8s_oidc_client_id" {
  value = okta_app_oauth.k8s_oidc.client_id
}

# Assign groups to the OIDC application
resource "okta_app_group_assignments" "k8s_oidc_group" {
  app_id = okta_app_oauth.k8s_oidc.id
  group {
    id = okta_group.k8s_admin_group.id
  }
  group {
    id = okta_group.k8s_restricted_users_group.id
  }
}

# Create an authorization server
resource "okta_auth_server" "oidc_auth_server" {
  name      = "k8s-auth"
  audiences = ["http:://localhost:8000"]
}

output "k8s_oidc_issuer_url" {
  value = okta_auth_server.oidc_auth_server.issuer
}

output "k8s_oidc_client_secret" {
  value = okta_app_oauth.k8s_oidc.client_secret
  sensitive = true
}

# Add claims to the authorization server
resource "okta_auth_server_claim" "auth_claim" {
  name                    = "groups"
  auth_server_id          = okta_auth_server.oidc_auth_server.id
  always_include_in_token = true
  claim_type              = "IDENTITY"
  group_filter_type       = "STARTS_WITH"
  value                   = "k8s-"
  value_type              = "GROUPS"
}

# Add policy and rule to the authorization server
resource "okta_auth_server_policy" "auth_policy" {
  name             = "k8s_policy"
  auth_server_id   = okta_auth_server.oidc_auth_server.id
  description      = "Policy for allowed clients"
  priority         = 1
  client_whitelist = [okta_app_oauth.k8s_oidc.id]
}

resource "okta_auth_server_policy_rule" "auth_policy_rule" {
  name           = "AuthCode + PKCE"
  auth_server_id = okta_auth_server.oidc_auth_server.id
  policy_id      = okta_auth_server_policy.auth_policy.id
  access_token_lifetime_minutes = 120
  priority       = 1
  grant_type_whitelist = [
    "authorization_code"
  ]
  scope_whitelist = ["*"]
  group_whitelist = ["EVERYONE"]
}
