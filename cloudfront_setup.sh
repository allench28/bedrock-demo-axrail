#!/bin/bash
set -e

# Default configuration file path
CONFIG_FILE="env-vars.json"

# Check if configuration file is provided as argument
if [ $# -eq 1 ]; then
    CONFIG_FILE="$1"
fi


# Check if the config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file $CONFIG_FILE not found!"
    echo "Please create a JSON file with at least the WEB_BUCKET_NAME field:"
    exit 1
fi

# Function to parse JSON value using pure bash
get_json_value() {
    local json_file="$1"
    local key="$2"
    
    # Read the file content
    local content=$(<"$json_file")
    
    # Remove whitespace and newlines to simplify parsing
    content=$(echo "$content" | tr -d '\n\r\t ' | tr -s ' ')
    
    # Extract value using pattern matching
    local pattern="\"$key\":\"([^\"]+)\""
    if [[ $content =~ $pattern ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Read S3 bucket name from JSON file
S3_BUCKET_NAME=$(get_json_value "$CONFIG_FILE" "WEB_BUCKET_NAME")

# Read WebSocket URL from JSON file
WEBSOCKET_URL=$(get_json_value "$CONFIG_FILE" "WEBSOCKET_URL")

# Validate S3 bucket name exists in the config
if [ -z "$S3_BUCKET_NAME" ]; then
    echo "Error: S3 bucket name not specified in config file"
    exit 1
fi


echo "S3 bucket: $S3_BUCKET_NAME"

# Validate WebSocket URL exists in the config
if [ -z "$WEBSOCKET_URL" ]; then
    echo "Warning: WEBSOCKET_URL not specified in config file"
    echo "Frontend constants.ts will not be updated"
else
    echo "WebSocket URL: $WEBSOCKET_URL"
fi


# Function to check and install required dependencies
install_dependencies() {
    local dependencies_installed=true
    
    echo "Detecting operating system..."
    
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux detection with better distribution support
        if [ -f /etc/debian_version ] || grep -qi 'debian\|ubuntu' /etc/*release; then
            echo "Detected Debian/Ubuntu system"
            PACKAGE_MANAGER="apt-get"
            INSTALL_CMD="sudo apt-get update && sudo apt-get install -y"
        elif [ -f /etc/redhat-release ] || grep -qi 'fedora\|rhel\|centos' /etc/*release; then
            echo "Detected RHEL/CentOS/Fedora system"
            PACKAGE_MANAGER="yum"
            INSTALL_CMD="sudo yum install -y"
        elif [ -f /etc/arch-release ] || grep -qi 'arch' /etc/*release; then
            echo "Detected Arch Linux"
            PACKAGE_MANAGER="pacman"
            INSTALL_CMD="sudo pacman -S --noconfirm"
        elif [ -f /etc/alpine-release ]; then
            echo "Detected Alpine Linux"
            PACKAGE_MANAGER="apk"
            INSTALL_CMD="apk add --no-cache"
        elif [ -f /etc/SuSE-release ] || grep -qi 'suse' /etc/*release; then
            echo "Detected openSUSE/SUSE"
            PACKAGE_MANAGER="zypper"
            INSTALL_CMD="sudo zypper install -y"
        else
            echo "Unknown Linux distribution. Will attempt manual installation methods."
            PACKAGE_MANAGER="unknown"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Detected macOS"
        # Check if Homebrew is installed
        if command -v brew &> /dev/null; then
            PACKAGE_MANAGER="brew"
            INSTALL_CMD="brew install"
        else
            echo "Homebrew not found. Installing Homebrew first..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            
            # Check if Homebrew was installed successfully
            if command -v brew &> /dev/null; then
                PACKAGE_MANAGER="brew"
                INSTALL_CMD="brew install"
                echo "Homebrew installed successfully."
            else
                echo "Failed to install Homebrew. Please install it manually."
                dependencies_installed=false
            fi
        fi
    elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
        echo "Detected Windows environment"
        
        # Check if using WSL or Git Bash or Cygwin
        if [ -f /proc/version ] && grep -qi 'microsoft\|wsl' /proc/version; then
            echo "Running under Windows Subsystem for Linux (WSL)"
            # Check WSL distribution and set package manager
            if grep -qi 'debian\|ubuntu' /etc/*release; then
                PACKAGE_MANAGER="apt-get"
                INSTALL_CMD="sudo apt-get update && sudo apt-get install -y"
            elif grep -qi 'fedora\|rhel\|centos' /etc/*release; then
                PACKAGE_MANAGER="yum"
                INSTALL_CMD="sudo yum install -y"
            else
                echo "Unknown WSL distribution. Will attempt manual installation methods."
                PACKAGE_MANAGER="unknown"
            fi
        else
            echo "Using Windows native environment"
            # For Windows, we'll check if scoop or chocolatey is available
            if command -v scoop &> /dev/null; then
                PACKAGE_MANAGER="scoop"
                INSTALL_CMD="scoop install"
            elif command -v choco &> /dev/null; then
                PACKAGE_MANAGER="choco"
                INSTALL_CMD="choco install -y"
            else
                echo "No package manager found on Windows. Will attempt manual installation."
                PACKAGE_MANAGER="unknown"
            fi
        fi
    else
        echo "Unknown operating system: $OSTYPE"
        echo "Will attempt to check for dependencies directly."
        PACKAGE_MANAGER="unknown"
    fi
    
    # Check and install AWS CLI
    if ! command -v aws &> /dev/null; then
        echo "AWS CLI not found. Attempting to install..."
        
        case $PACKAGE_MANAGER in
            apt-get)
                $INSTALL_CMD awscli
                ;;
            yum)
                $INSTALL_CMD awscli
                ;;
            pacman)
                $INSTALL_CMD aws-cli
                ;;
            zypper)
                $INSTALL_CMD aws-cli
                ;;
            apk)
                $INSTALL_CMD aws-cli
                ;;
            brew)
                $INSTALL_CMD awscli
                ;;
            scoop)
                $INSTALL_CMD aws
                ;;
            choco)
                $INSTALL_CMD awscli
                ;;
            unknown)
                echo "No suitable package manager found for installing AWS CLI."
                echo "Please install AWS CLI manually following the instructions at:"
                echo "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
                
                # Offer direct download for common platforms
                if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                    echo "You can try installing with:"
                    echo "curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
                    echo "unzip awscliv2.zip"
                    echo "sudo ./aws/install"
                elif [[ "$OSTYPE" == "darwin"* ]]; then
                    echo "You can try installing with:"
                    echo "curl 'https://awscli.amazonaws.com/AWSCLIV2.pkg' -o 'AWSCLIV2.pkg'"
                    echo "sudo installer -pkg AWSCLIV2.pkg -target /"
                elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
                    echo "Download and run the Windows installer from:"
                    echo "https://awscli.amazonaws.com/AWSCLIV2.msi"
                fi
                
                dependencies_installed=false
                ;;
        esac
        
        # Verify installation
        if ! command -v aws &> /dev/null; then
            echo "AWS CLI installation failed."
            dependencies_installed=false
        else
            echo "AWS CLI installed successfully."
        fi
    else
        echo "AWS CLI already installed."
    fi
    
    # Check and install npm/Node.js
    if ! command -v npm &> /dev/null; then
        echo "npm not found. Attempting to install Node.js and npm..."
        
        case $PACKAGE_MANAGER in
            apt-get)
                curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
                $INSTALL_CMD nodejs
                ;;
            yum)
                curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
                $INSTALL_CMD nodejs
                ;;
            pacman)
                $INSTALL_CMD nodejs npm
                ;;
            zypper)
                $INSTALL_CMD nodejs npm
                ;;
            apk)
                $INSTALL_CMD nodejs npm
                ;;
            brew)
                $INSTALL_CMD node
                ;;
            scoop)
                $INSTALL_CMD nodejs
                ;;
            choco)
                $INSTALL_CMD nodejs
                ;;
            unknown)
                echo "No suitable package manager found for installing Node.js and npm."
                echo "Please install Node.js and npm manually from https://nodejs.org/"
                
                # Offer NVM as an alternative
                echo "Alternatively, you can try installing NVM (Node Version Manager):"
                echo "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash"
                echo "Then run: nvm install 18"
                
                dependencies_installed=false
                ;;
        esac
        
        # Verify installation
        if ! command -v npm &> /dev/null; then
            echo "npm installation failed."
            dependencies_installed=false
        else
            echo "Node.js and npm installed successfully."
        fi
    else
        echo "npm already installed."
    fi
    
    # Check for jq (JSON processor)
    if ! command -v jq &> /dev/null; then
        echo "jq not found. Attempting to install..."
        
        case $PACKAGE_MANAGER in
            apt-get)
                $INSTALL_CMD jq
                ;;
            yum)
                $INSTALL_CMD jq
                ;;
            pacman)
                $INSTALL_CMD jq
                ;;
            zypper)
                $INSTALL_CMD jq
                ;;
            apk)
                $INSTALL_CMD jq
                ;;
            brew)
                $INSTALL_CMD jq
                ;;
            scoop)
                $INSTALL_CMD jq
                ;;
            choco)
                $INSTALL_CMD jq
                ;;
            unknown)
                echo "No suitable package manager found for installing jq."
                echo "jq will not be installed. JSON validation will be skipped."
                ;;
        esac
        
        # Verify installation
        if ! command -v jq &> /dev/null; then
            echo "jq installation failed. JSON validation will be skipped."
        else
            echo "jq installed successfully."
        fi
    else
        echo "jq already installed."
    fi
    
    if [ "$dependencies_installed" = true ]; then
        echo "All required dependencies are installed."
        return 0
    else
        echo "Some dependencies could not be installed automatically."
        
        # Ask user if they want to continue anyway
        read -p "Do you want to continue with deployment anyway? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Continuing with deployment despite missing dependencies..."
            return 0
        else
            echo "Deployment aborted. Please install missing dependencies manually."
            return 1
        fi
    fi
}

# Function to validate JSON file
validate_json() {
    local json_file="$1"
    
    if command -v jq &> /dev/null; then
        if ! jq empty "$json_file" 2>/dev/null; then
            echo "Error: Invalid JSON format in $json_file"
            echo "JSON content:"
            cat "$json_file"
            return 1
        fi
    else
        echo "Warning: jq not installed. Skipping JSON validation for $json_file"
    fi
    
    return 0
}

# Function to update the constants.ts file with the WebSocket URL
update_constants_file() {
    local frontend_dir="$1"
    local websocket_url="$2"
    local constants_file="$frontend_dir/src/constants/apiEndpoints.tsx"
    
    if [ -z "$websocket_url" ]; then
        echo "WebSocket URL not provided, skipping constants.ts update"
        return 0
    fi
    
    if [ ! -f "$constants_file" ]; then
        echo "Warning: apiEndpoints.tsx file not found at $constants_file"
        echo "Searching for constants.tsx in the project..."
        
        # Try to find the constants.ts file
        local found_file=$(find "$frontend_dir" -name "apiEndpoints.tsx" | head -1)
        
        if [ -n "$found_file" ]; then
            constants_file="$found_file"
            echo "Found apiEndpoints.tsx at: $constants_file"
        else
            echo "Error: apiEndpoints.ts file not found in the project"
            return 1
        fi
    fi
    
    echo "Updating WebSocket URL in $constants_file"
    
    # Create backup of original file
    cp "$constants_file" "${constants_file}.bak"
    
    # Replace <WEBSOCKET_URL> placeholder with the actual WebSocket URL
    sed -i.tmp "s|<WEBSOCKET_URL>|$websocket_url|g" "$constants_file"
    
    echo "constants.ts file updated successfully"
    echo "Original backup saved at ${constants_file}.bak"
    
    # Remove temporary files
    rm -f "${constants_file}.tmp"
    
    return 0
}

# Other configuration variables (default values or from command line)
REGION=${REGION:-"us-east-1"}
CLOUDFRONT_COMMENT=${CLOUDFRONT_COMMENT:-"Frontend distribution"}
FRONTEND_DIR="axr-chatbot"
BUILD_DIR=${BUILD_DIR:-"./dist"}

# Install missing dependencies
echo "Checking for required dependencies..."
if ! install_dependencies; then
    echo "Failed to install some dependencies. Please install them manually."
    exit 1
fi

echo "=== Starting deployment process ==="
echo "Using S3 bucket from config: $S3_BUCKET_NAME"
if [ -n "$WEBSOCKET_URL" ]; then
    echo "Using WebSocket URL from config: $WEBSOCKET_URL"
fi
echo "Region: $REGION"
echo "Frontend directory: $FRONTEND_DIR"
echo "Build directory: $BUILD_DIR"

# Update constants.ts before building
if [ -n "$WEBSOCKET_URL" ]; then
    echo "=== Updating constants.ts with WebSocket URL ==="
    if ! update_constants_file "$FRONTEND_DIR" "$WEBSOCKET_URL"; then
        echo "Warning: Failed to update constants.ts file"
        echo "Build will proceed with existing WebSocket URL"
        
        # Ask user if they want to continue anyway
        read -p "Do you want to continue with deployment anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Deployment aborted."
            exit 1
        fi
    fi
fi

# Step 1: Build the frontend
echo "=== Building frontend ==="
cd "$FRONTEND_DIR"
echo "Installing dependencies..."
npm install
echo "Building project..."
npm run build
cd - > /dev/null

# Step 2: Create S3 bucket if it doesn't exist
echo "=== Setting up S3 bucket ==="
if ! aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
    echo "Creating S3 bucket: $S3_BUCKET_NAME"
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$S3_BUCKET_NAME" \
            --region "$REGION"
    else
        aws s3api create-bucket \
            --bucket "$S3_BUCKET_NAME" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
    
    # Configure bucket for static website hosting
    aws s3 website "s3://$S3_BUCKET_NAME" --index-document index.html --error-document index.html
fi


echo "=== Uploading build files to S3 ==="
echo "Uploading content from $FRONTEND_DIR/$BUILD_DIR to s3://$S3_BUCKET_NAME"
aws s3 sync "$FRONTEND_DIR/$BUILD_DIR" "s3://$S3_BUCKET_NAME" --delete

echo "Setting appropriate cache control headers..."

echo "Files uploaded successfully to S3 bucket: $S3_BUCKET_NAME"

# Step 3: Create Origin Access Identity for CloudFront
DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Origins.Items[0].DomainName=='$S3_BUCKET_NAME.s3.amazonaws.com'].Id" --output text)

if [ -n "$DISTRIBUTION_ID" ] && [ "$DISTRIBUTION_ID" != "None" ]; then
    echo "Found existing distribution: $DISTRIBUTION_ID. Disabling it first..."
    
    # Get the current config and ETag
    CONFIG_RESPONSE=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID")
    ETAG=$(echo "$CONFIG_RESPONSE" | grep -o '"ETag": "[^"]*' | cut -d'"' -f4)
    
    # Disable the distribution (required before deletion)
    echo "$CONFIG_RESPONSE" | sed 's/"Enabled": true/"Enabled": false/' > disabled-dist.json
    
    # Clean up the JSON for AWS CLI
    sed -i.bak '/"ETag"/d' disabled-dist.json
    sed -i.bak 's/"DistributionConfig": //g' disabled-dist.json
    
    # Validate JSON before using it
    if ! validate_json disabled-dist.json; then
        echo "Skipping distribution update due to invalid JSON. Continuing with other steps..."
    else
        # Update the distribution to disable it
        aws cloudfront update-distribution --id "$DISTRIBUTION_ID" --if-match "$ETAG" --distribution-config file://disabled-dist.json
        
        echo "Distribution is being disabled. This may take 15-30 minutes."
        echo "After it's disabled, you may delete it with:"
        echo "aws cloudfront delete-distribution --id $DISTRIBUTION_ID --if-match \$(aws cloudfront get-distribution --id $DISTRIBUTION_ID --query ETag --output text)"
    fi
    
    echo "Proceeding to create a new distribution..."
fi

# Create a new Origin Access Identity
echo "Creating new Origin Access Identity..."
OAI_RESULT=$(aws cloudfront create-cloud-front-origin-access-identity \
    --cloud-front-origin-access-identity-config CallerReference="$(date +%s)",Comment="OAI for $S3_BUCKET_NAME")
OAI_ID=$(echo "$OAI_RESULT" | grep -o '"Id": "[^"]*' | cut -d'"' -f4)

echo "Created OAI with ID: $OAI_ID"

# Create a new CloudFront distribution with the OAI
echo "Creating new CloudFront distribution with OAI..."
cat > new-dist-config.json << EOF
{
    "CallerReference": "$(date +%s)",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3Origin",
                "DomainName": "$S3_BUCKET_NAME.s3.amazonaws.com",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                "S3OriginConfig": {
                    "OriginAccessIdentity": "origin-access-identity/cloudfront/$OAI_ID"
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "Compress": true,
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            },
            "Headers": {
                "Quantity": 0
            },
            "QueryStringCacheKeys": {
                "Quantity": 0
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000
    },
    "Comment": "Distribution for $S3_BUCKET_NAME",
    "Enabled": true,
    "DefaultRootObject": "index.html",
    "CustomErrorResponses": {
        "Quantity": 1,
        "Items": [
            {
                "ErrorCode": 404,
                "ResponsePagePath": "/index.html",
                "ResponseCode": "200",
                "ErrorCachingMinTTL": 300
            }
        ]
    }
}
EOF

# Validate JSON before using it
if ! validate_json new-dist-config.json; then
    echo "Failed to create CloudFront distribution due to invalid JSON. Exiting..."
    exit 1
fi

# Create the CloudFront distribution using file:// syntax
NEW_DIST=$(aws cloudfront create-distribution --distribution-config file://new-dist-config.json)
NEW_DIST_ID=$(echo "$NEW_DIST" | grep -o '"Id": "[^"]*' | head -1 | cut -d'"' -f4)
NEW_DIST_DOMAIN=$(echo "$NEW_DIST" | grep -o '"DomainName": "[^"]*' | head -1 | cut -d'"' -f4)

echo "Created new CloudFront distribution with ID: $NEW_DIST_ID"
echo "CloudFront domain: $NEW_DIST_DOMAIN"

sleep 10

# Update bucket policy to allow CloudFront OAI access
echo "Updating bucket policy to restrict access to CloudFront OAI..."
cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontOAIAccess",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity $OAI_ID"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$S3_BUCKET_NAME/*"
        }
    ]
}
EOF

# Validate JSON before using it
if ! validate_json bucket-policy.json; then
    echo "Failed to update bucket policy due to invalid JSON. Exiting..."
    exit 1
fi

aws s3api put-bucket-policy --bucket "$S3_BUCKET_NAME" --policy file://bucket-policy.json

# Make sure public access is blocked
aws s3api put-public-access-block \
    --bucket "$S3_BUCKET_NAME" \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "S3 bucket access is now restricted to CloudFront only"

# Skip the redundant CloudFront distribution creation since we already created one above
echo "=== CloudFront distribution already created ==="
echo "CloudFront distribution ID: $NEW_DIST_ID"
echo "CloudFront domain: $NEW_DIST_DOMAIN"

# Create an invalidation to ensure new content is served
aws cloudfront create-invalidation --distribution-id "$NEW_DIST_ID" --paths "/*"
echo "CloudFront cache invalidated"

echo "=== Deployment completed successfully ==="
echo "Your website is available at: https://$NEW_DIST_DOMAIN"
echo "Note: It may take up to 15 minutes for CloudFront distribution to fully deploy"

# Clean up temporary files
# rm -f disabled-dist.json disabled-dist.json.bak new-dist-config.json bucket-policy.json
# rm -f bedrock-trust-policy.json bedrock-permissions-policy.json bedrock-opensearch-trust.json
# rm -f security-policy.json network-policy.json access-policy.json index-config.json
# rm -f kb-config.json storage.json storage2.json s3-source-config.json web-crawler-config.json prompt_config.json
# rm -f create_index.py verify_index.py create_index_managed.py


echo "Temporary files cleaned up"
