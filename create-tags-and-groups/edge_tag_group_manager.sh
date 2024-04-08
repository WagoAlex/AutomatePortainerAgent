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

create_groups() {
    local group_file="$1"
    local idle_tag_id=$(curl -s -k -X GET \
        -H "Authorization: Bearer $JWT_TOKEN" \
        "${DEFAULT_BASE_URL}:9443/api/tags" | jq -r '.[] | select(.Name == "idle") | .ID')

    echo "Tag ID for 'idle': $idle_tag_id"

    while IFS= read -r group_name; do
        local payload=$(cat <<EOF
{
  "dynamic": true,
  "endpoints": [0],
  "name": "${group_name}",
  "partialMatch": true,
  "tagIDs": [$idle_tag_id]
}
EOF
)

        echo "Payload for group '$group_name':"
        echo "$payload"

        local response=$(curl -s -k -X POST \
            -H "Authorization: Bearer $JWT_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "${DEFAULT_BASE_URL}:9443/api/edge_groups")

        echo "Response for group '$group_name':"
        echo "$response"

        local group_id=$(echo "$response" | jq -r '.Id')
        if [ -z "$group_id" ] || [ "$group_id" == "null" ]; then
            echo "Failed to create group '$group_name'."
        else
            echo "Group '$group_name' created with ID: $group_id."
        fi
    done < "$group_file"
}

main() {
    echo "Welcome to the Group and Tag Creation Script"

    read -p "Enter Base URL [$DEFAULT_BASE_URL]: " base_url
    base_url=${base_url:-$DEFAULT_BASE_URL}

    authenticate

    # Create groups
    group_file="groupnames.txt"
    tag_file="tagnames.txt"
    create_groups "$group_file" "$tag_file"

    echo "Setup completed successfully."
}

main "$@"
