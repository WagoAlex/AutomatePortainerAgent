#!/bin/bash

# Configuration with defaults
DEFAULT_USERNAME="admin"
DEFAULT_BASE_URL="https://192.168.2.202" # Default base URL for Portainer
DEFAULT_DOWNLOAD_DIR="./" # Default download directory

# Function to authenticate with Portainer API and obtain JWT token
authenticate() {
    echo "" # Add a new line
    read -p "Enter Portainer server name or IP address [$DEFAULT_BASE_URL]: " server_name
    DEFAULT_BASE_URL=${server_name:-$DEFAULT_BASE_URL}

    read -sp "Enter Portainer username [$DEFAULT_USERNAME]: " username
    username=${username:-$DEFAULT_USERNAME}
    echo ""
    read -sp "Enter Portainer password: " password
    echo ""

    local response=$(curl -s -k -X POST \
        -H "Content-Type: application/json" \
        -d "{\"Username\":\"$username\",\"Password\":\"$password\"}" \
        "${DEFAULT_BASE_URL}:9443/api/auth")

    JWT_TOKEN=$(echo "$response" | jq -r '.jwt')

    if [ -z "$JWT_TOKEN" ] || [ "$JWT_TOKEN" == "null" ]; then
        echo "Failed to obtain JWT token. Check your username and password."
        exit 1
    fi
}

# Function to create download directory based on server name
create_download_dir() {
    local server_name=$1
    # Remove the protocol and replace slashes with underscores, remove trailing slash if present
    local formatted_server_name="${server_name/https:\/\//https__}"
    formatted_server_name="${formatted_server_name%/}"
    mkdir -p "$formatted_server_name"
    echo "$formatted_server_name"
}

# Function to download specified edge stacks
download_selected_stacks() {
    local download_dir=$1
    shift # Remove the first argument, which is the download directory
    local selected_ids=("$@")

    for stack_id in "${selected_ids[@]}"; do
        local stack_content=$(curl -s -k -X GET \
            -H "Authorization: Bearer $JWT_TOKEN" \
            "${DEFAULT_BASE_URL}:9443/api/edge_stacks/$stack_id/file")
        local stack_name=$(curl -s -k -X GET \
            -H "Authorization: Bearer $JWT_TOKEN" \
            "${DEFAULT_BASE_URL}:9443/api/edge_stacks/$stack_id" | jq -r '.Name')

        if [ "$stack_name" == "null" ]; then
            echo "Failed to download stack with ID '$stack_id': Stack does not exist."
            continue
        fi

        # Format stack content to Docker Compose YAML format
        formatted_content=$(echo "$stack_content" | jq -r '.StackFileContent' | sed 's/\\n/\n/g' | sed 's/\\\\/\\/g')

        echo -e "$formatted_content" > "$download_dir/$stack_name.yml"
        echo "Stack '$stack_name' downloaded to '$download_dir'."
    done
}

# Function to list available stacks and prompt user for selection
select_stacks_to_download() {
    local stacks_response=$(curl -s -k -X GET \
        -H "Authorization: Bearer $JWT_TOKEN" \
        "${DEFAULT_BASE_URL}:9443/api/edge_stacks")

    local stack_ids=($(echo "$stacks_response" | jq -r '.[] | .Id'))
    local stack_names=($(echo "$stacks_response" | jq -r '.[] | .Name'))

    echo "Available stacks for download:"
    for i in "${!stack_ids[@]}"; do
        echo "  ${stack_names[i]} (ID: ${stack_ids[i]})"
    done

    read -p "Enter the IDs of the stacks you want to download (comma-separated), or enter 'all' to download all stacks: " selected_ids_input
    if [ "$selected_ids_input" == "all" ]; then
        selected_ids=("${stack_ids[@]}")
    else
        IFS=',' read -r -a selected_ids <<< "$selected_ids_input"
    fi

    download_selected_stacks "$download_dir" "${selected_ids[@]}"
}

main() {
    echo "Welcome to the Portainer Stack Downloader"

    authenticate

    download_dir=$(create_download_dir "$DEFAULT_BASE_URL")
    echo "All stack files will be downloaded to: $download_dir"

    select_stacks_to_download

    echo "Download completed successfully."
}

main
