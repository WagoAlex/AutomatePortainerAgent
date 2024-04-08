#!/bin/bash

# Configuration with defaults
DEFAULT_USERNAME="admin"
DEFAULT_USER_ENTRY_BASE="wago-edge-"
DEFAULT_TAGS="1,2,3" # Comma-separated list of default tag IDs
DEFAULT_GROUP_ID="1"
DEFAULT_NUM_ENVIRONMENTS="1"
DEFAULT_BASE_URL="https://192.168.2.202" # Base URL for both API and Server

# Function to check and perform installation
perform_installation() {
    # Check if installation flag exists
    local install_flag="./packages/.install_flag"

    if [ -f "$install_flag" ]; then
        echo "Installation already performed. Skipping."
        return 0
    fi

    # Change to the directory where the script is located
    cd "$(dirname "$0")" || exit

    # Define the directory where the .deb files are stored (relative to the script directory)
    local deb_directory="./packages"

    if [ ! -d "$deb_directory" ]; then
        echo "Error: The directory $deb_directory does not exist."
        exit 1
    fi

    # Check if any .deb files are present
    if ! ls "$deb_directory"/*.deb &> /dev/null; then
        echo "No .deb files found in $deb_directory. Skipping installation."
        return 0
    fi

    # Install the .deb files using dpkg
    echo "Installing .deb files..."
    sudo dpkg -i "$deb_directory"/*.deb &> /dev/null

    # Check if installation was successful
    if [ $? -eq 0 ]; then
        echo "Installation completed successfully."
        # Create installation flag
        touch "$install_flag"
    else
        echo "Error: Installation failed."
        exit 1
    fi
}

# Function to generate a shortened UUID
generate_short_uuid() {
    uuidgen | cut -c 1-6
}

# Function to authenticate with Portainer API and obtain JWT token
authenticate() {
    read -p "Enter Portainer username [$DEFAULT_USERNAME]: " username
    username=${username:-$DEFAULT_USERNAME}
    read -sp "Enter Portainer password: " password
    echo ""

    local response=$(curl -s -k -X POST \
        -H "Content-Type: application/json" \
        -d "{\"Username\":\"$username\",\"Password\":\"$password\"}" \
        "${API_URL}/api/auth")

    jwt_token=$(echo "$response" | jq -r '.jwt')

    if [ -z "$jwt_token" ] || [ "$jwt_token" == "null" ]; then
        echo "Failed to obtain JWT token. Check your username and password."
        exit 1
    fi
}

# Function to fetch and display available tags
fetch_and_display_tags() {
    echo "Fetching available tags..."
    local response=$(curl -s -k -X GET \
        -H "Authorization: Bearer $jwt_token" \
        "${API_URL}/api/tags")

    echo "Available tags:"
    echo "$response" | jq -r '.[] | "\(.ID)\t\(.Name)"'
    echo # Add an extra line for readability
}

# Function to fetch and display available edge groups
fetch_and_display_endpoint_groups() {
    echo "Fetching available endpoint groups..."
    local response=$(curl -s -k -X GET \
        -H "Authorization: Bearer $jwt_token" \
        "${API_URL}/api/endpoint_groups")

    echo "Available edge groups:"
    echo "$response" | jq -r '.[] | "\(.Id)\t\(.Name)"'
    echo # Add an extra line for readability
}

# Function to check if the endpoint exists (by name)
check_endpoint_exists() {
    local token="$1"
    local endpoint_name="$2"
    local response=$(curl -s -k -X GET \
        -H "Authorization: Bearer $token" \
        "${API_URL}/api/endpoints")

    if echo "$response" | jq -e '.[] | select(.Name == "'"$endpoint_name"'")' > /dev/null; then
        echo "Endpoint '$endpoint_name' exists."
        return 0
    else
        echo "Endpoint '$endpoint_name' does not exist. Proceeding to create..."
        return 1
    fi
}

# Function to create an endpoint and save Edge information
create_endpoint_and_save_edge_info() {
    local token="$1"
    local group_id="$2"
    local user_entry="$3"
    local tags="$4"
    local batch_uuid="$5"
    local file_name="edge_info_${batch_uuid}.csv"

    local response=$(curl -s -k -X POST \
        -H "Authorization: Bearer $token" \
        -F "Name=${user_entry}" \
        -F "EndpointCreationType=4" \
        -F "URL=${SERVER_URL}:9443" \
        -F "GroupId=${group_id}" \
        -F "TagIds=[${tags}]" \
        -F "EdgeCheckinInterval=0" \
        -F "TLS=true" \
        -F "TLSSkipVerify=true" \
        -F "TLSSkipClientVerify=true" \
        "${API_URL}/api/endpoints")

    local endpoint_id=$(echo "$response" | jq -r '.Id')
    local edge_id=$(echo "$response" | jq -r '.EdgeID')
    local edge_key=$(echo "$response" | jq -r '.EdgeKey')

    if [ -z "$endpoint_id" ] || [ "$endpoint_id" == "null" ]; then
        echo "Failed to create endpoint. Response: $response"
        exit 1
    else
        echo -e "${user_entry}\t${edge_id}\t${edge_key}" >> "$file_name"
        echo "Endpoint '${user_entry}' created with ID: $endpoint_id. Edge information saved to '$file_name'."
    fi
}

# New function to handle the creation logic based on user input
create_environments() {
    local auto_mode=$1
    local semi_auto_count=$2

    for ((i = 1; i <= num_environments; i++)); do
        echo "Creating environment $i of $num_environments"
        local user_entry="${DEFAULT_USER_ENTRY_BASE}${i}-${batch_uuid}"

        if [[ "$auto_mode" == "yes" ]] || ( [[ "$auto_mode" == "semi" ]] && [[ $i -le $semi_auto_count ]] ); then
            # Auto or Semi-Auto Mode
            echo "Using auto/semi-auto configuration for environment $i"
        else
            # Manual Mode
            echo "Using manual configuration for environment $i"
            read -p "Enter Group ID: " group_id
            read -p "Enter tags (comma-separated): " tags
        fi

        check_endpoint_exists "$jwt_token" "$user_entry"
        if [ $? -eq 1 ]; then
            create_endpoint_and_save_edge_info "$jwt_token" "$group_id" "$user_entry" "$tags" "$batch_uuid"
        fi
    done
}

main() {
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m' # No Color

    echo "Welcome to the Portainer Edge Agent Setup Script"


    # Check if jq, curl, and uuidgen are already installed
    if command -v jq &> /dev/null && command -v curl &> /dev/null && command -v uuidgen &> /dev/null; then
        echo -e "${GREEN}Required packages are installed.${NC}"
    else
        # Dependency check for jq
        if ! command -v jq &> /dev/null; then
            echo -e "${RED}jq is not installed. Please install jq to continue.${NC}"
            exit 1
        fi

        # Dependency check for curl
        if ! command -v curl &> /dev/null; then
            echo -e "${RED}curl is not installed. Please install curl to continue.${NC}"
            exit 1
        fi

        if ! command -v uuidgen &> /dev/null; then
            echo -e "${RED}uuidgen is not installed. Please install uuid-runtime to continue.${NC}"
            exit 1
        fi

        # Perform installation
        perform_installation
    fi


    read -p "Enter Base URL [$DEFAULT_BASE_URL]: " base_url
    base_url=${base_url:-$DEFAULT_BASE_URL}
    API_URL="${base_url}:9443"
    SERVER_URL="${base_url}"

    authenticate
    fetch_and_display_endpoint_groups
    fetch_and_display_tags

    read -p "How many environments do you want to create? [$DEFAULT_NUM_ENVIRONMENTS]: " num_environments
    num_environments=${num_environments:-$DEFAULT_NUM_ENVIRONMENTS}
    local batch_uuid=$(generate_short_uuid)

    read -p "Enter the base name for environments [$DEFAULT_USER_ENTRY_BASE]: " user_entry_base
    DEFAULT_USER_ENTRY_BASE=${user_entry_base:-$DEFAULT_USER_ENTRY_BASE}

    read -p "Do you want to apply the same Group ID and Tags ID for all environments? (yes/auto, semi-auto, no/manual): " apply_mode

    # Ask for environments creation mode (auto,semi-auto,manual)
    if [[ "$apply_mode" == "yes" || "$apply_mode" == "y" || "$apply_mode" == "auto" ]]; then
        read -p "Enter Group ID [$DEFAULT_GROUP_ID]: " group_id
        group_id=${group_id:-$DEFAULT_GROUP_ID}
        read -p "Enter tags (comma-separated) [$DEFAULT_TAGS]: " tags
        tags=${tags:-$DEFAULT_TAGS}
        create_environments "yes" 0
    elif [[ "$apply_mode" == "semi-auto" || "$apply_mode" == "s" ]]; then
        read -p "How many environments will have the same config? " semi_auto_count
        read -p "Enter Group ID [$DEFAULT_GROUP_ID]: " group_id
        group_id=${group_id:-$DEFAULT_GROUP_ID}
        read -p "Enter tags (comma-separated) [$DEFAULT_TAGS]: " tags
        tags=${tags:-$DEFAULT_TAGS}
        create_environments "semi" $semi_auto_count
    else
        group_id=""
        tags=""
        create_environments "no" 0
    fi
    echo "Setup completed successfully. All edge information saved in 'edge_info_${batch_uuid}.csv'."
}

main "$@"
