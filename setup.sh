# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

set -e

source ./partials/interactive_prompts.sh
source ./partials/setup_ado.sh

echo "
############################################################
Welcome to the Analytics CI/CD Setup Tool.
############################################################

Use this to quickly and interactively set up a CI/CD template for your Analytics environment
Before you continue, make sure you:

- Are logged in with the Azure CLI in the desired Tenant
- Have both a development and a production environment to set up CI/CD between them
- Have configured Git integration in the development environment
- We currently support:
    - Azure Data Factory with Azure DevOps
    - Azure Synapse Analytics with Azure DevOps

" 
choose_service_interactive # --> $service
echo "Please select the subscription that contains SOURCE workspace." 
choose_subscription_interactive # --> $subscription
SOURCE_SUBSCRIPTION=$subscription
echo "Select SOURCE workspace."
choose_workspace_interactive # --> $workspace
SOURCE_WORKSPACE=$workspace

echo "Select the subscription that contains TARGET workspace."
choose_subscription_interactive # --> $subscription
TARGET_SUBSCRIPTION=$subscription
echo "Select TARGET workspace."
choose_workspace_interactive # --> $workspace
TARGET_WORKSPACE=$workspace

SOURCE_WORKSPACE_NAME=$(echo $SOURCE_WORKSPACE | jq " .name" -r)
TARGET_WORKSPACE_NAME=$(echo $TARGET_WORKSPACE | jq " .name" -r)
TARGET_RESOURCE_GROUP=$(echo $TARGET_WORKSPACE | jq " .resourceGroup" -r)

if [[ $(echo $SOURCE_WORKSPACE | jq .repoConfiguration.type -r) == "FactoryVSTSConfiguration" ]]; then
    setup_ado adf
elif [[ $(echo $SOURCE_WORKSPACE | jq .workspaceRepositoryConfiguration.type -r) == "WorkspaceVSTSConfiguration" ]]; then
    setup_ado syn
else
    echo "This repo configuration is not currently supported"
fi