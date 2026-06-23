SHELL := /bin/bash

# Load .env if present — exports all non-comment vars including TF_VAR_*
ifneq (,$(wildcard .env))
include .env
export
endif

# Bridge plain env names → TF_VAR_* form Terraform expects
export TF_VAR_vultr_api_key               := $(VULTR_API_KEY)
export TF_VAR_appco_username              := $(APPCO_USERNAME)
export TF_VAR_appco_user_token            := $(APPCO_USER_TOKEN)
export TF_VAR_scc_reg_code                := $(SCC_REG_CODE)
export TF_VAR_prime_artifacts_url         := $(PRIME_ARTIFACTS_URL)
export TF_VAR_suse_observability_reg_code := $(SUSE_OBSERVABILITY_REG_CODE)
export TF_VAR_hf_token                    := $(HF_TOKEN)
export TF_VAR_le_email                    := $(LE_EMAIL)
export TF_VAR_deploy_observability        := $(DEPLOY_OBSERVABILITY)
export TF_VAR_deploy_gpu_operator         := $(DEPLOY_GPU_OPERATOR)
export TF_VAR_deploy_vllm                 := $(DEPLOY_VLLM)
export TF_VAR_observability_profile       := $(OBSERVABILITY_PROFILE)
export TF_VAR_server_type                 := $(SERVER_TYPE)

TF_DIR     := terraform
ANSIBLE_DIR := ansible
# SSH key path is rendered by Terraform after apply (terraform output).
SSH_KEY     = $(shell cd $(TF_DIR) && terraform output -raw ssh_private_key_path 2>/dev/null)

.PHONY: help init plan apply ansible verify credentials destroy clean ssh neuvector-https

help:
	@echo "Targets:"
	@echo "  make init               - terraform init"
	@echo "  make plan               - terraform plan"
	@echo "  make apply              - provision Vultr instance + write Ansible inventory"
	@echo "  make ansible            - run full Ansible site.yml (self-waits for SSH)"
	@echo "  make verify             - confirm all pods are Running or Completed"
	@echo "  make credentials        - print access URLs and credentials again"
	@echo "  make ssh                - ssh into provisioned host"
	@echo "  make neuvector-https    - expose the NeuVector UI over HTTPS (run after manual install)"
	@echo "  make destroy            - tear down the Vultr instance"
	@echo "  make clean              - remove tfplan + generated inventory"

init:
	cd $(TF_DIR) && terraform init -upgrade

plan: init
	cd $(TF_DIR) && terraform plan -out=tfplan

apply: init
	cd $(TF_DIR) && terraform apply -auto-approve

ansible:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml

verify:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags verify

credentials:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags summary

neuvector-https:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml --tags neuvector_ingress

ssh:
	@IP=$$(cd $(TF_DIR) && terraform output -raw instance_ip); \
	ssh -i $(SSH_KEY) root@$$IP

destroy:
	cd $(TF_DIR) && terraform destroy -auto-approve

clean:
	rm -f $(TF_DIR)/tfplan
	rm -f $(ANSIBLE_DIR)/inventory/hosts.ini
