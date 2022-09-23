# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Requests key press so user can read prompts
wait_for_prompt () {
    read -n1 -s -r -p $'Press any key to continue, Ctrl+C to exit.\n' key
    echo
}

# Outputs: $output JSON
api_selection () {
    echo "Listing resources ($1)..."
    items=${2}
    select item_name in $(echo $items | jq '.[].name'); do break; done;
    if [ -z "$item_name" ] 
    then
        echo "Invalid $1 choice. Exiting..." 
        exit 1
    fi
    echo "You chose $item_name\n"
    output=$(echo $items | jq " .[] | select(.name==$item_name)")
}

# Outputs: $subscription JSON, configures CLI
choose_subscription_interactive () {
    wait_for_prompt
    api_selection subscription """$(echo $(az account list) | jq 'map(.name |= gsub(" ";"__"))')"""
    az account set -n $(echo $output | jq .id -r)
    subscription=$output
}

# Outputs: $service string
choose_service_interactive () {
    echo "Please select an Analytics service." 
    api_selection service '[{"name":"Azure_Data_Factory"}, {"name":"Azure_Synapse_Analytics"}]'
    service=$(echo $output | jq .name -r)
}

# Outputs: $workspace JSON
choose_workspace_interactive () {
    if [[ $service == "Azure_Data_Factory" ]]; then
        api_selection factory """$(az datafactory list)"""
        workspace=$output
    elif [[ $service == "Azure_Synapse_Analytics" ]]; then
        api_selection synapse """$(az synapse workspace list)"""
        workspace=$(az synapse workspace show --name $(echo $output | jq .name -r) --resource-group $(echo $output | jq .resourceGroup -r))
    else
        echo "This Analytics service is not currently supported"
    fi
}

# Outputs: $service_connection JSON
choose_service_connection_interactive() {
    echo "Select Service Connection for deploying workspace (must have Contributor access)."
    api_selection service_connection """$(az devops service-endpoint list | jq 'map(select(.type == "azurerm"))')"""
    service_connection=$output
}