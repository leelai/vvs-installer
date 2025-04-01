#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
INSTALL_DIR="/usr/local/bin"
TEMP_DIR="$(mktemp -d)"
BINARY_NAME="vvs"
GITHUB_REPO="leelai/vvs-cli"
CLEANUP_FILES=()
# Add log file for detailed error tracking
LOG_FILE="${TEMP_DIR}/vvs_install_log.txt"
ERROR_OCCURRED=false
ERROR_MESSAGE=""

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}" >> "${LOG_FILE}"
}

# Function to handle errors
handle_error() {
    local message="$1"
    local exit_code="${2:-1}"
    ERROR_OCCURRED=true
    ERROR_MESSAGE="${message}"
    log_message "ERROR" "${message}"
    echo -e "${RED}ERROR: ${message}${NC}" >&2
    return "${exit_code}"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [options]

Options:
  -v, --version VERSION   Install specific version (default: latest)
  -u, --uninstall         Uninstall vvs-cli
  -h, --help              Show this help message

EOF
    exit 0
}

# Function to cleanup on error
cleanup() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    
    # Remove temporary directory
    if [ -d "$TEMP_DIR" ]; then
        # Save log file if an error occurred
        if [ "$ERROR_OCCURRED" = true ] && [ -f "$LOG_FILE" ]; then
            ERROR_LOG="/tmp/vvs_install_error_$(date +%Y%m%d%H%M%S).log"
            cp "$LOG_FILE" "$ERROR_LOG"
            echo -e "${YELLOW}Installation log saved to ${ERROR_LOG}${NC}"
        fi
        rm -rf "$TEMP_DIR"
    fi
    
    # Remove any additional files created during installation
    for file in "${CLEANUP_FILES[@]}"; do
        if [ -e "$file" ]; then
            rm -f "$file"
        fi
    done
    
    if [ "$1" != "0" ]; then
        echo -e "${RED}Installation failed. All temporary files have been removed.${NC}"
        if [ "$ERROR_OCCURRED" = true ] && [ -n "$ERROR_MESSAGE" ]; then
            echo -e "${RED}Error details: ${ERROR_MESSAGE}${NC}"
            echo -e "${YELLOW}For troubleshooting, please report this error and provide the log file:${NC}"
            echo -e "${YELLOW}${ERROR_LOG}${NC}"
            echo -e "${YELLOW}You can also report the issue at: https://github.com/${GITHUB_REPO}/issues${NC}"
        else
            # Try to identify common issues if no specific error was caught
            echo -e "${YELLOW}Common installation issues:${NC}"
            echo -e "${YELLOW}- Network connectivity problems${NC}"
            echo -e "${YELLOW}- GitHub rate limiting${NC}"
            echo -e "${YELLOW}- Permission issues with sudo${NC}"
            echo -e "${YELLOW}- Incorrect version specified${NC}"
            echo -e "${YELLOW}Please try again or report the issue at: https://github.com/${GITHUB_REPO}/issues${NC}"
        fi
    fi
}

# Set trap for cleanup on exit
trap 'cleanup $?' EXIT

# Function to check if command exists
command_exists() {
    command -v "$1" > /dev/null 2>&1
}

# Function to detect OS and architecture
detect_os_and_arch() {
    # Detect OS
    OS="$(uname -s)"
    log_message "INFO" "Detected operating system: ${OS}"
    case "${OS}" in
        Darwin*)
            OS="darwin"
            ;;
        Linux*)
            OS="linux"
            ;;
        *)
            handle_error "Unsupported operating system: ${OS}"
            exit 1
            ;;
    esac

    # Detect architecture
    ARCH="$(uname -m)"
    log_message "INFO" "Detected architecture: ${ARCH}"
    case "${ARCH}" in
        x86_64*)
            ARCH="amd64"
            ;;
        arm64*|aarch64*)
            ARCH="arm64"
            ;;
        *)
            handle_error "Unsupported architecture: ${ARCH}"
            exit 1
            ;;
    esac

    echo -e "${BLUE}Detected OS: ${OS}, Architecture: ${ARCH}${NC}"
    log_message "INFO" "Using OS: ${OS}, Architecture: ${ARCH} for download"
}

# Function to check if vvs-cli is installed
is_installed() {
    if command_exists vvs; then
        return 0
    else
        return 1
    fi
}

# Function to uninstall vvs-cli
uninstall() {
    if is_installed; then
        echo -e "${YELLOW}Uninstalling vvs-cli...${NC}"
        sudo rm -f "${INSTALL_DIR}/${BINARY_NAME}"
        echo -e "${GREEN}vvs-cli has been uninstalled successfully.${NC}"
    else
        echo -e "${YELLOW}vvs-cli is not installed.${NC}"
    fi
    exit 0
}

# Function to get the latest release version
get_latest_version() {
    log_message "INFO" "Attempting to get latest release version from GitHub"
    
    if command_exists curl; then
        LATEST_VERSION=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>> "${LOG_FILE}" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    elif command_exists wget; then
        LATEST_VERSION=$(wget -qO- "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>> "${LOG_FILE}" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    else
        handle_error "Neither curl nor wget is installed. Please install one of them and try again."
        exit 1
    fi

    if [ -z "$LATEST_VERSION" ]; then
        handle_error "Unable to determine latest version. GitHub API may be rate limited or unavailable."
        exit 1
    fi

    log_message "INFO" "Latest version determined to be: $LATEST_VERSION"
    echo "$LATEST_VERSION"
}

# Function to download file
download_file() {
    local url="$1"
    local output_file="$2"
    
    echo -e "${BLUE}Downloading from $url${NC}"
    log_message "INFO" "Downloading from $url to $output_file"
    
    if command_exists curl; then
        if ! curl -L -o "$output_file" "$url" 2>> "${LOG_FILE}"; then
            handle_error "Failed to download $url using curl"
            exit 1
        fi
    elif command_exists wget; then
        if ! wget -O "$output_file" "$url" 2>> "${LOG_FILE}"; then
            handle_error "Failed to download $url using wget"
            exit 1
        fi
    else
        handle_error "Neither curl nor wget is installed. Please install one of them and try again."
        exit 1
    fi
    
    # Check if file was downloaded successfully
    if [ ! -s "$output_file" ]; then
        handle_error "Downloaded file is empty or does not exist: $output_file"
        exit 1
    fi
    
    log_message "INFO" "Successfully downloaded from $url"
}

# Function to verify SHA256 checksum
verify_checksum() {
    local file="$1"
    local expected_checksum="$2"
    
    echo -e "${BLUE}Verifying checksum...${NC}"
    log_message "INFO" "Verifying SHA256 checksum for file: $file"
    log_message "INFO" "Expected checksum: $expected_checksum"
    
    if command_exists shasum; then
        CHECKSUM=$(shasum -a 256 "$file" | awk '{print $1}')
        log_message "INFO" "Using shasum for checksum verification"
    elif command_exists sha256sum; then
        CHECKSUM=$(sha256sum "$file" | awk '{print $1}')
        log_message "INFO" "Using sha256sum for checksum verification"
    else
        log_message "WARNING" "Neither shasum nor sha256sum is installed. Skipping checksum verification."
        echo -e "${YELLOW}Warning: Neither shasum nor sha256sum is installed. Skipping checksum verification.${NC}"
        return 0
    fi
    
    log_message "INFO" "Calculated checksum: $CHECKSUM"
    
    if [ "$CHECKSUM" != "$expected_checksum" ]; then
        handle_error "Checksum verification failed! Expected: $expected_checksum, Got: $CHECKSUM"
        echo -e "${RED}Expected: $expected_checksum${NC}"
        echo -e "${RED}Got: $CHECKSUM${NC}"
        exit 1
    fi
    
    log_message "INFO" "Checksum verification passed"
    echo -e "${GREEN}Checksum verification passed.${NC}"
}

# Function to check PATH
check_path() {
    if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
        echo -e "${YELLOW}Warning: ${INSTALL_DIR} is not in your PATH.${NC}"
        echo -e "${YELLOW}You may need to add the following to your shell profile:${NC}"
        echo -e "${BLUE}export PATH=\$PATH:${INSTALL_DIR}${NC}"
    fi
}

# Parse command line arguments
VERSION=""
UNINSTALL=false

while [ $# -gt 0 ]; do
    case "$1" in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -u|--uninstall)
            UNINSTALL=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Uninstall if requested
if [ "$UNINSTALL" = true ]; then
    uninstall
fi

# Detect OS and architecture
detect_os_and_arch

# Set version to install
if [ -z "$VERSION" ]; then
    VERSION=$(get_latest_version)
    echo -e "${BLUE}Installing latest version: ${VERSION}${NC}"
else
    echo -e "${BLUE}Installing specified version: ${VERSION}${NC}"
fi

# Define file names
BINARY_FILE="${BINARY_NAME}-${OS}-${ARCH}"
BINARY_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${BINARY_FILE}"
CHECKSUM_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/checksums.txt"

# Download binary
BINARY_PATH="${TEMP_DIR}/${BINARY_FILE}"
download_file "$BINARY_URL" "$BINARY_PATH"
CLEANUP_FILES+=("$BINARY_PATH")

# Download checksum file
CHECKSUM_FILE="${TEMP_DIR}/checksums.txt"
download_file "$CHECKSUM_URL" "$CHECKSUM_FILE"
CLEANUP_FILES+=("$CHECKSUM_FILE")

# Extract expected checksum
echo -e "${BLUE}Extracting checksum from ${CHECKSUM_FILE}...${NC}"
log_message "INFO" "Extracting checksum from ${CHECKSUM_FILE} for binary ${BINARY_FILE}"

# Show checksum file contents for debugging
echo -e "${YELLOW}Checksum file contents:${NC}"
cat "$CHECKSUM_FILE"
log_message "INFO" "Checksum file contents:\n$(cat "$CHECKSUM_FILE")"

EXPECTED_CHECKSUM=$(grep "${BINARY_FILE}" "$CHECKSUM_FILE" | awk '{print $1}')
if [ -z "$EXPECTED_CHECKSUM" ]; then
    # More detailed error for checksum not found
    handle_error "Unable to find checksum for ${BINARY_FILE} in checksums.txt."
    echo -e "${YELLOW}Debug info:${NC}"
    echo -e "${YELLOW}- Binary file looking for: ${BINARY_FILE}${NC}"
    echo -e "${YELLOW}- Checksum file path: ${CHECKSUM_FILE}${NC}"
    echo -e "${YELLOW}- Checksum file size: $(wc -c "$CHECKSUM_FILE" | awk '{print $1}') bytes${NC}"
    echo -e "${YELLOW}- grep command used: grep \"${BINARY_FILE}\" \"$CHECKSUM_FILE\"${NC}"
    echo -e "${YELLOW}- Number of lines in checksum file: $(wc -l "$CHECKSUM_FILE" | awk '{print $1}')${NC}"
    
    # Try a more flexible search for debugging purposes
    echo -e "${YELLOW}Attempting broader search in checksum file:${NC}"
    grep -i "$(echo ${BINARY_FILE} | cut -d'-' -f1)" "$CHECKSUM_FILE" || echo -e "${YELLOW}No results found.${NC}"
    
    log_message "ERROR" "Checksum extraction failed. Binary file: ${BINARY_FILE}, File exists: $(test -f "$CHECKSUM_FILE" && echo "Yes" || echo "No"), File size: $(wc -c "$CHECKSUM_FILE" 2>/dev/null | awk '{print $1}') bytes"
    exit 1
fi

log_message "INFO" "Found checksum: ${EXPECTED_CHECKSUM} for ${BINARY_FILE}"

# Verify checksum
verify_checksum "$BINARY_PATH" "$EXPECTED_CHECKSUM"

# Install binary
echo -e "${BLUE}Installing vvs-cli to ${INSTALL_DIR}...${NC}"
chmod +x "$BINARY_PATH"
sudo mv "$BINARY_PATH" "${INSTALL_DIR}/${BINARY_NAME}"

# Check if installation was successful
if is_installed; then
    echo -e "${GREEN}vvs-cli has been installed successfully!${NC}"
    VVS_VERSION=$(vvs --version)
    echo -e "${GREEN}Installed version: ${VVS_VERSION}${NC}"
    
    # Check PATH
    check_path
    
    echo -e "${GREEN}You can now use vvs-cli by running 'vvs' in your terminal.${NC}"
else
    echo -e "${RED}Installation failed. Please check the errors above.${NC}"
    exit 1
fi

# Cleanup is handled by the trap
exit 0