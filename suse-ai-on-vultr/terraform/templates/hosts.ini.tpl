[suse_ai]
${instance_ip} ansible_user=root ansible_ssh_private_key_file=${ssh_private_key_path}

[suse_ai:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
node_ip=${instance_ip}
appco_username=${appco_username}
appco_user_token=${appco_user_token}
scc_reg_code=${scc_reg_code}
prime_artifacts_url=${prime_artifacts_url}
suse_observability_reg_code=${suse_observability_reg_code}
hf_token=${hf_token}
le_email=${le_email}
deploy_observability=${deploy_observability}
deploy_gpu_operator=${deploy_gpu_operator}
deploy_vllm=${deploy_vllm}
observability_profile=${observability_profile}
