#!/bin/bash

# Configuration with defaults
DEFAULT_USERNAME="admin"
DEFAULT_BASE_URL="https://192.168.2.116" # Base URL for both API and Server

# Function to authenticate with Portainer API and obtain JWT token
authenticate() {
    read -p "Enter Portainer username [$DEFAULT_USERNAME]: " username
    username=${username:-$DEFAULT_USERNAME}
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

# Function to retrieve edge stacks information
get_edge_stacks() {
    local response=$(curl -s -k -X GET \
        -H "Authorization: Bearer $JWT_TOKEN" \
        "${DEFAULT_BASE_URL}:9443/api/edge_stacks")

    echo "$response"
}

# Function to save each stack to a separate file
save_stacks_to_files() {
    local stacks_json="$1"
    local stack_count=$(echo "$stacks_json" | jq length)

    local source_url=$(echo "$DEFAULT_BASE_URL" | sed 's|[^[:alnum:]]|_|g') # Remove non-alphanumeric characters from the URL and replace them with underscores
    local output_dir="./stacks_$source_url"

    mkdir -p "$output_dir"

    for ((i = 0; i < stack_count; i++)); do
        local stack_name=$(echo "$stacks_json" | jq -r ".[$i].Name")
        local stack_file="$output_dir/$stack_name.json"
        echo "Saving stack '$stack_name' to file '$stack_file'"
        echo "$(echo "$stacks_json" | jq ".[$i]")" >"$stack_file"
    done
}

main() {
    echo "Welcome to the Edge Stack Retrieval and Saving Script"

    read -p "Enter Base URL [$DEFAULT_BASE_URL]: " base_url
    base_url=${base_url:-$DEFAULT_BASE_URL}

    DEFAULT_BASE_URL="$base_url"

    authenticate

    edge_stacks=$(get_edge_stacks)
    save_stacks_to_files "$edge_stacks"

    echo "Edge stacks retrieval and saving completed successfully."
}

main "$@"
