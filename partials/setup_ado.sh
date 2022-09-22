# Set up Azure DevOps repository for CI/CD
configure_ado() {
    echo "Azure Devops source control detected. 
    We will create a pipeline named Workspace Deploy, which publishes the Development version to Production."

    echo "Enter ADO authentication"
    read -p "DevOps URL [dev.azure.com]" ORG_URL
    ORG_URL=${ORG_URL:-dev.azure.com}
    read -p "DevOps Username: " ADO_USER
    read -s -p "DevOps Personal Access Token: " ADO_PAT
    echo 
    [[ $1 = "adf" ]] && DEFAULT_PUBLISH_BRANCH=adf_publish || DEFAULT_PUBLISH_BRANCH=workspace_publish
    read -p "Publish branch name [$DEFAULT_PUBLISH_BRANCH]: " PUBLISH_BRANCH
    PUBLISH_BRANCH=${PUBLISH_BRANCH:-${DEFAULT_PUBLISH_BRANCH}}
    
    if [[ $1 = "adf" ]]; then
        repo_configuration=$(echo $SOURCE_WORKSPACE | jq .repoConfiguration)
    else
        repo_configuration=$(echo $SOURCE_WORKSPACE | jq .workspaceRepositoryConfiguration)
    fi
    ORG_NAME=$(echo $repo_configuration | jq " .accountName" -r)
    PROJECT_NAME=$(echo $repo_configuration | jq " .projectName" -r)
    REPO_NAME=$(echo $repo_configuration | jq " .repositoryName" -r)
    LOCATION=$(echo $TARGET_WORKSPACE | jq .location -r)
    echo $ADO_PAT | az devops login
    az devops configure --defaults organization=https://${ORG_URL}/${ORG_NAME} project=${PROJECT_NAME}
}

add_pipelines_to_git() {
    set +e
    rm -rf ./"${REPO_NAME}"
    git clone https://${ADO_USER}:${ADO_PAT}@${ORG_URL}/${ORG_NAME}/${PROJECT_NAME}/_git/${REPO_NAME} --branch ${PUBLISH_BRANCH} --single-branch
    cd "${REPO_NAME}"
    mkdir .ado
    mkdir .ado/workflows
    cp ../pipelines/deploy-pipeline-$1.yml ./.ado/workflows/deploy-pipeline.yml
    git add .
    git commit -m "Add CI/CD Pipelines"
    git push
    set -e
}

create_deploy_pipeline() {
    TARGET_SUBSCRIPTION_ID="$(echo $TARGET_SUBSCRIPTION | jq .id -r)"
    SERVICE_CONNECTION_NAME=$(echo $service_connection | jq " .name" -r)
    az pipelines create --name "Workspace Deploy" --description "Deploy Workspace resources to production environment" --repository ${REPO_NAME} --branch ${PUBLISH_BRANCH} --repository-type tfsgit --yml-path .ado/workflows/deploy-pipeline.yml --skip-run > /dev/null
    az pipelines variable create --pipeline-name "Workspace Deploy" --name ARM_CONNECTION --value ${SERVICE_CONNECTION_NAME} > /dev/null
    az pipelines variable create --pipeline-name "Workspace Deploy" --name LOCATION --value ${LOCATION} > /dev/null
    az pipelines variable create --pipeline-name "Workspace Deploy" --name RESOURCE_GROUP --value ${TARGET_RESOURCE_GROUP} > /dev/null
    az pipelines variable create --pipeline-name "Workspace Deploy" --name SUBSCRIPTION_ID --value ${TARGET_SUBSCRIPTION_ID} > /dev/null
    az pipelines variable create --pipeline-name "Workspace Deploy" --name SOURCE_WORKSPACE_NAME --value ${SOURCE_WORKSPACE_NAME} > /dev/null
    az pipelines variable create --pipeline-name "Workspace Deploy" --name WORKSPACE_NAME --value ${TARGET_WORKSPACE_NAME} > /dev/null
}


setup_ado () {
    configure_ado $1
    echo "Creating Service Principal..."
    set +e
    app=$(az ad app create --display-name "$PROJECT_NAME-cicd")
    appid=$(echo $app | jq " .appId" -r)
    subid=$(echo $subscription | jq " .id" -r)
    subname=$(echo $subscription | jq " .name" -r)
    tenantid=$(echo $subscription | jq " .tenantId" -r)
    rg=$(echo $TARGET_WORKSPACE | jq " .resourceGroup" -r)
    credential=$(az ad app credential reset --id $appid)
    service_principal=$(az ad sp create --id $appid)
    service_principal=$(az ad sp show --id $appid)
    spid=$(echo $service_principal | jq " .id" -r)
    echo "Assigning required permissions to Service Principal..."
    az role assignment create --assignee $spid \
        --role "Contributor" \
        --scope "/subscriptions/$subid/resourcegroups/$rg" > /dev/null
    if [[ $1 = "syn" ]]; then
        az synapse role assignment create --workspace-name $TARGET_WORKSPACE_NAME --scope workspaces/$TARGET_WORKSPACE_NAME --role "Synapse Administrator" --assignee $spid > /dev/null
    fi
    set -e
    echo "Creating service connection..."
    service_connection=$(AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY=$(echo $credential | jq " .password" -r) az devops service-endpoint azurerm create --azure-rm-service-principal-id $appid --azure-rm-subscription-id $subid --azure-rm-subscription-name "$subname" --azure-rm-tenant-id $tenantid --name cicdtool)
    SERVICE_CONNECTION_NAME=$(echo $service_connection | jq " .name" -r)
    add_pipelines_to_git $1
    create_deploy_pipeline
    echo "
    All done! Check your Azure DevOps project for a pipeline named Workspace Deploy.
    It will replicate your SOURCE workspace to your TARGET workspace"
}