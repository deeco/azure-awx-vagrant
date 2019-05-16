#!/bin/bash

# Vars
awx_host_url="http://192.168.10.20"
awx_username="admin"
awx_password="password"
awx_projects_source_folder="/vagrant/ansible-projects/"
awx_projects_dest_folder="/var/lib/awx/projects"
azure_creds_dev_dub="/vagrant/credentials/azure_ansible_cred_dev_dub.yml"
ssh_public_key_path="$HOME/.ssh/id_rsa.pub"
awx_http_port_check=80
awx_demo_data_import_check="tower-cli instance_group get tower 2> /dev/null"
resource_group="dev-ansible-rg-dublin"
region="westeurope"
inventory="Azure Domain Controller"

# Create SSH key
if [ ! -f "$ssh_public_key_path" ]
then
    echo -e "\nINFO: Started Creating new SSH key..."
    echo -e "\n\n\n" |  ssh-keygen -t rsa -C "dgowran@gmail.com" -N ""
else
    echo -e "\nINFO: SSH key already exists...SKIPPING."
fi
ssh_public_key=`cat "$ssh_public_key_path"`

# Configure Ansible AWX using Tower CLI
echo -e "\nINFO: Started Configuring Ansible AWX using Tower CLI..."

# Configure host - include "http:" as it default to HTTPS
tower-cli config host $awx_host_url

# Disable SSL verification to allow insecure HTTP traffic
tower-cli config verify_ssl false

# Configure login
tower-cli config username $awx_username
tower-cli config password $awx_password

# Wait for AWX Web Server to be online
while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' localhost:$awx_http_port_check)" -ne "200" ]]; do
    echo "INFO: AWX Web Server NOT online yet...waiting 30 seconds"
    sleep 30
done
echo "INFO: AWX Web Server now online...READY"

# Wait for AWX Demo Data import to finish
eval $awx_demo_data_import_check
while [[ $? -ne 0 ]]; do
    echo "INFO: AWX Data Import not complete yet...waiting 5 seconds"
    sleep 5
    eval $awx_demo_data_import_check
done
echo "INFO: AWX Data Import now complete"

# Copy projects folder
if [ -d "$awx_projects_source_folder" ]
then
    echo -e "\nINFO: Copying Ansible Projects folder(s) for AWX..."
    rsync -avz "$awx_projects_source_folder"* $awx_projects_dest_folder
else
    echo -e "\nINFO: Ansible Projects source folder missing...SKIPPING."
fi

# Create project
echo -e "\nINFO: Creating Azure Project in AWX..."
tower-cli project create --name "Azure Project" --description "Azure Playbooks" --scm-type "manual" --local-path "azure-vms" --organization "Default"

# Create Azure Organization Dev Dublin
echo -e "\nINFO: Creating Azure Organization in AWX..."
tower-cli organization create --name "Azure Development Dublin" --description "Azure Org Dublin"

# Create Azure inventory
echo -e "\nINFO: Creating Azure Inventory in AWX..."
tower-cli inventory create --name "Azure Inventory" --description "Azure Inventory" --organization "Azure Development Dublin" --variables "ssh_public_key: \"$ssh_public_key\""

# Create Azure inventory
echo -e "\nINFO: Creating Azure Domain Controller Inventory in AWX..."
tower-cli inventory create --name "Azure Domain Controller" --description "Azure Domain Controller" --organization "Azure Development Dublin" --variables "ansible_winrm_server_cert_validation: ignore"

# Create Azure credential
echo -e "\nINFO: Creating Azure Credential in AWX..."
echo -e "\nINFO: Folder Directory for credentials" $azure_creds_dev_dub
tower-cli credential create --name "Azure Credential Development Dublin" --description "Azure Credential Development Dublin" --organization "Azure Development Dublin" --credential-type "Microsoft Azure Resource Manager" --inputs "@$azure_creds_dev_dub"

# Create Azure credential
echo -e "\nINFO: Creating Windows local Machine Azure Credential in AWX..."
echo -e "\nINFO: Folder Directory for credentials" $azure_creds_dev_dub
tower-cli credential create --name "Windows Credentials" --organization "Azure Development Dublin" --inputs '{"username": "azure_user", "password": "MyPassword123!!!"}' --credential-type "Machine"

# Create Azure Inverntory
echo -e "\nINFO: Creating Azure Inventory"
tower-cli inventory_source create --name "Azure-ansible-resource-group" --credential "Azure Credential Development Dublin" --source "azure_rm" --description "Azure Inventory" --inventory "$inventory" --source-regions "$region" --update-on-launch "true" --overwrite-vars=true --source-vars "resource_groups: \"$resource_group\""

# Create Azure job template for a simple Resource Group
echo -e "\nINFO: Creating job template for a simple Azure Dev Dublin Resource Group..."
# WORKAROUND: you must supply an SSH credential type initially
tower-cli job_template create --name "Azure Dev Dublin Create Resource Group" --description "Azure Dev Dublin Resource Group - Job Template" --inventory "Azure Inventory" --project "Azure Project" --playbook "resource_group_dev.yml" --credential "Windows Credentials"
# WORKAROUND: you can then associate an Azure credential afterwards
tower-cli job_template associate_credential --job-template "Azure Dev Dublin Create Resource Group" --credential "Azure Credential Development Dublin"

# Create Azure job template for a CentOS Linux VM and all required resources
echo -e "\nINFO: Creating job template for a CentOS Linux VM and all required resources in Azure..."
# WORKAROUND: you must supply an SSH credential type initially
tower-cli job_template create --name "Azure Create CentOS Linux VM" --description "Azure CentOS Linux VM - Job Template" --inventory "Azure Inventory" --project "Azure Project" --playbook "centos_vm.yml" --credential "Windows Credentials"
# WORKAROUND: you can then associate an Azure credential afterwards
tower-cli job_template associate_credential --job-template "Azure Create CentOS Linux VM" --credential "Azure Credential Development Dublin"

# Create Azure job template for a Windows VM and all required resources
echo -e "\nINFO: Creating job template for a Windows VM and all required resources in Azure..."
# WORKAROUND: you must supply an SSH credential type initially
tower-cli job_template create --name "Azure Create Windows VM" --description "Azure Windows VM - Job Template" --inventory "Azure Inventory" --project "Azure Project" --playbook "windows_vm.yml" --credential "Windows Credentials"
# WORKAROUND: you can then associate an Azure credential afterwards
tower-cli job_template associate_credential --job-template "Azure Create Windows VM" --credential "Azure Credential Development Dublin"

# Create Azure job template for Consul Client
echo -e "\nINFO: Creating job template for consul client install...."
# WORKAROUND: you must supply an ssh credential type initially
tower-cli job_template create --name "Azure Install Consul Client" --description "Azure Install Consul Client - Job Template" --inventory "Azure Inventory" --project "Azure Project" --playbook "consul_client_install.yml" --credential "Windows Credentials"
# WORKAROUND: you can then associate an Azure credential afterwards
tower-cli job_template associate_credential --job-template "Azure Install Consul Client" --credential "Azure Credential Development Dublin"

# Create Azure job template for a powershell install version 5.1
echo -e "\nINFO: Creating job template Powershell 5.1 in Azure windows VM's..."
# WORKAROUND: you must supply an SSH credential type initially
tower-cli job_template create --name "Azure PowerShell Install" --description "Azure PowerShell Install - Job Template" --inventory "$inventory" --project "Azure Project" --playbook "upgrade_powershell.yml" --credential "Windows Credentials"
# WORKAROUND: you can then associate an Azure credential afterwards
tower-cli job_template associate_credential --job-template "Azure PowerShell Install" --credential "Azure Credential Development Dublin"

# Create Azure job template for a Azure Become
echo -e "\nINFO: Creating job template for a Azure Become and all required resources in Azure..."
# WORKAROUND: you must supply an SSH credential type initially
tower-cli job_template create --name "Azure Become" --description "Azure Become - Job Template" --inventory "$inventory" --project "Azure Project" --playbook "become.yml" --credential "Windows Credentials"
# WORKAROUND: you can then associate an Azure credential afterwards
tower-cli job_template associate_credential --job-template "Azure Become" --credential "Azure Credential Development Dublin"

# Create Azure job template for a Azure Clean
echo -e "\nINFO: Creating job template for a Azure Clean and all required resources in Azure..."
# WORKAROUND: you must supply an SSH credential type initially
tower-cli job_template create --name "Azure Clean" --description "Azure Clean - Job Template" --inventory "$inventory" --project "Azure Project" --playbook "clean.yml" --credential "Windows Credentials"
# WORKAROUND: you can then associate an Azure credential afterwards
tower-cli job_template associate_credential --job-template "Azure Clean" --credential "Azure Credential Development Dublin"

# Create Azure job template for a Azure Domain
echo -e "\nINFO: Creating job template for a Azure Domain and all required resources in Azure..."
# WORKAROUND: you must supply an SSH credential type initially
tower-cli job_template create --name "Azure Domain" --description "Azure Domain - Job Template" --inventory "$inventory" --project "Azure Project" --playbook "domain.yml" --credential "Windows Credentials"
# WORKAROUND: you can then associate an Azure credential afterwards
tower-cli job_template associate_credential --job-template "Azure Domain" --credential "Azure Credential Development Dublin"

# Create Azure job template for a Azure Files
echo -e "\nINFO: Creating job template for a Azure Files and all required resources in Azure..."
# WORKAROUND: you must supply an SSH credential type initially
tower-cli job_template create --name "Azure Files" --description "Azure Files - Job Template" --inventory "$inventory" --project "Azure Project" --playbook "files.yml" --credential "Windows Credentials"
# WORKAROUND: you can then associate an Azure credential afterwards
tower-cli job_template associate_credential --job-template "Azure Files" --credential "Azure Credential Development Dublin"

# Create Azure job template for a Azure Package
echo -e "\nINFO: Creating job template for a Azure Package and all required resources in Azure..."
# WORKAROUND: you must supply an SSH credential type initially
tower-cli job_template create --name "Azure Package" --description "Azure Package - Job Template" --inventory "$inventory" --project "Azure Project" --playbook "packages.yml" --credential "Windows Credentials"
# WORKAROUND: you can then associate an Azure credential afterwards
tower-cli job_template associate_credential --job-template "Azure Package" --credential "Azure Credential Development Dublin"

# Create Azure job template for a Azure Provision
echo -e "\nINFO: Creating job template for a Azure Provision and all required resources in Azure..."
# WORKAROUND: you must supply an SSH credential type initially
tower-cli job_template create --name "Azure Provision" --description "Azure Provision - Job Template" --inventory "Azure Inventory" --project "Azure Project" --playbook "provision.yml" --credential "Windows Credentials"
# WORKAROUND: you can then associate an Azure credential afterwards
tower-cli job_template associate_credential --job-template "Azure Provision" --credential "Azure Credential Development Dublin"

# Create Template Workflow and associate
echo -e "\nINFO: Creating Workflow template for a Azure Provision and all required resources in Azure..."
tower-cli workflow create --name="Azure Domain Controller Workflow" --organization="Azure Development Dublin" --description="Azure Domain Controller Workflow"
tower-cli node create -W "Azure Domain Controller Workflow" --job-template="Azure Provision"
tower-cli node create -W "Azure Domain Controller Workflow" --inventory-source "Azure-ansible-resource-group"
tower-cli node create -W "Azure Domain Controller Workflow" --job-template="Azure PowerShell Install"
tower-cli node create -W "Azure Domain Controller Workflow" --job-template="Azure Domain"
tower-cli node create -W "Azure Domain Controller Workflow" --job-template="Azure Files"
tower-cli node create -W "Azure Domain Controller Workflow" --job-template="Azure Package"
tower-cli node associate_success_node 1 2
tower-cli node associate_success_node 2 3
tower-cli node associate_success_node 3 4
tower-cli node associate_success_node 4 5
tower-cli node associate_success_node 5 6
tower-cli node associate_success_node 7 8
tower-cli node associate_success_node 8 9
tower-cli node associate_success_node 9 10
tower-cli node associate_success_node 10 11
tower-cli node associate_success_node 11 12
