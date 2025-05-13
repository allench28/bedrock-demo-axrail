#!/bin/bash

# Variables - Update these before running the script
REGION="us-east-1"
AWS_ACCOUNT_ID="926866439735"
ECR_REPO_NAME="demo_lambda"
ECR_IMAGE_TAG="latest"
LAMBDA_NAME="my-websocket-lambda"
API_NAME="MyWebSocketAPI"
KNOWLEDGE_BASE_NAME="MyBedrockKB"
S3_BUCKET_NAME="my-bedrock-kb-$(date +%s)"  # Generates a unique bucket name
WEB_BUCKET_NAME="web-portal-$(date +%s)"
# S3_BUCKET_NAME="my-bedrock-kb"  # Generates a unique bucket name

WEB_CRAWLER_URL="https://www.axrail.com/about-us"
CRAWLER_ROLE_NAME="BedrockCrawlerRole"
LAMBDA_ROLE_NAME="LambdaAdminRole"

ROLE_NAME="BedrockKnowledgeBaseServiceRole"
POLICY_NAME="BedrockKnowledgeBasePermissions"
KNOWLEDGE_BASE_NAME="BedrockKnowledgeBase"
COLLECTION_NAME="kb-collection"
EMBED_MODEL_ARN="arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"

# Configuration variables - MODIFY THESE
CLUSTER_IDENTIFIER="my-redshift-cluster"
DB_NAME="mydb"
MASTER_USERNAME="admin"
MASTER_PASSWORD="YourStrongPassword123!"  # CHANGE THIS to a secure password
NODE_TYPE="ra3.xlplus"
CLUSTER_TYPE="single-node"                # Options: single-node or multi-node
NODE_COUNT=1                              # Only relevant for multi-node clusters
SUBNET_GROUP_NAME="redshift-default-subnet-group"
PUBLICLY_ACCESSIBLE=true                  # Set to false if you don't want the cluster to be publicly accessible



install_pip_if_needed() {
  if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
    echo "pip/pip3 not found. Attempting to install..."
    
    # Check which package manager is available
    if command -v apt-get &> /dev/null; then
      echo "Detected Debian/Ubuntu. Installing pip..."
      sudo apt-get update && sudo apt-get install -y python3-pip
    elif command -v yum &> /dev/null; then
      echo "Detected CentOS/RHEL/Amazon Linux. Installing pip..."
      sudo yum install -y python3-pip
    elif command -v brew &> /dev/null; then
      echo "Detected macOS. Installing python (includes pip)..."
      brew install python
    else
      echo "ERROR: Could not detect package manager. Please install pip manually and run the script again."
      exit 1
    fi
    
    # Verify installation
    if command -v pip3 &> /dev/null; then
      echo "pip3 installed successfully."
    else
      echo "ERROR: pip installation failed. Please install pip manually and run the script again."
      exit 1
    fi
  else
    echo "pip/pip3 is already installed."
  fi
}

# Then replace your existing pip check with this call
# Around line 420-430 where you currently check for pip

# Call the function to install pip if needed
install_pip_if_needed


export AWS_DEFAULT_REGION=us-east-1

echo "Installing AWS CLI 1.38.18..."
pip install awscli==1.38.18 --user

# Verify installation
echo "Verifying installation..."
aws --version

# Step 1: Create IAM Role for Lambda with Admin Access
echo "Creating IAM role for Lambda if it doesn't exist..."
if ! aws iam get-role --role-name $LAMBDA_ROLE_NAME > /dev/null 2>&1; then
    LAMBDA_ROLE_ARN=$(aws iam create-role --role-name $LAMBDA_ROLE_NAME \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "lambda.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --query 'Role.Arn' --output text)

    aws iam put-role-policy --role-name $LAMBDA_ROLE_NAME \
        --policy-name LambdaECRAccessPolicy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "ecr:GetDownloadUrlForLayer",
                        "ecr:BatchGetImage",
                        "ecr:BatchCheckLayerAvailability"
                    ],
                    "Resource": "*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "ecr:GetAuthorizationToken"
                    ],
                    "Resource": "*"
                }
            ]
        }'

    echo "Attaching AdministratorAccess policy to Lambda role..."
    sleep 5 # Add delay to allow role propagation

    aws iam attach-role-policy --role-name $LAMBDA_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

    echo "Lambda IAM role created: $LAMBDA_ROLE_ARN"
else
    LAMBDA_ROLE_ARN=$(aws iam get-role --role-name $LAMBDA_ROLE_NAME --query 'Role.Arn' --output text)
    echo "Lambda IAM role already exists: $LAMBDA_ROLE_ARN"
fi

USERNAME="axrail_user"
CURRENT_AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
DEFAULT_PASSWORD="axr-$CURRENT_AWS_ACCOUNT_ID"

echo "Creating IAM user: $USERNAME"
aws iam create-user --user-name "$USERNAME"

# Create login profile with password reset required
aws iam create-login-profile \
    --user-name "$USERNAME" \
    --password "$DEFAULT_PASSWORD" \
    --password-reset-required

# Attach Administrator Access Policy
aws iam attach-user-policy \
    --user-name "$USERNAME" \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Step 2: Create Lambda Function from ECR Image
ECR_IMAGE_URI="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO_NAME:$ECR_IMAGE_TAG"
CROSS_LAMBDA_ROLE_ARN="arn:aws:iam::926866439735:role/ECR_Shared_Role"

ORIGINAL_AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
ORIGINAL_AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
ORIGINAL_AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN

# Assume cross-account role for ECR access
ECR_CREDENTIALS=$(aws sts assume-role \
  --role-arn $CROSS_LAMBDA_ROLE_ARN \
  --role-session-name ECRPullSession \
  --output json)

ECR_ACCESS_KEY=$(echo $ECR_CREDENTIALS | jq -r '.Credentials.AccessKeyId')
ECR_SECRET_KEY=$(echo $ECR_CREDENTIALS | jq -r '.Credentials.SecretAccessKey')
ECR_SESSION_TOKEN=$(echo $ECR_CREDENTIALS | jq -r '.Credentials.SessionToken')

# Use credentials for ECR login
AWS_ACCESS_KEY_ID=$ECR_ACCESS_KEY AWS_SECRET_ACCESS_KEY=$ECR_SECRET_KEY AWS_SESSION_TOKEN=$ECR_SESSION_TOKEN \
  aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Pull the image if needed
# docker pull $ECR_IMAGE_URI

# Restore original credentials for Lambda creation
export AWS_ACCESS_KEY_ID=$ORIGINAL_AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$ORIGINAL_AWS_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN=$ORIGINAL_AWS_SESSION_TOKEN


echo "Creating Lambda function if it doesn't exist..."
if ! aws lambda get-function --function-name $LAMBDA_NAME > /dev/null 2>&1; then
    aws lambda create-function --function-name $LAMBDA_NAME \
        --package-type Image \
        --code ImageUri=$ECR_IMAGE_URI \
        --role $LAMBDA_ROLE_ARN  \
        --region $REGION \
        --timeout 30 \
        --memory-size 128

    LAMBDA_ARN=$(aws lambda get-function --function-name $LAMBDA_NAME --query 'Configuration.FunctionArn' --output text)
    echo "Lambda function created: $LAMBDA_ARN"
    
else
    LAMBDA_ARN=$(aws lambda get-function --function-name $LAMBDA_NAME --query 'Configuration.FunctionArn' --output text)
    echo "Lambda function already exists: $LAMBDA_ARN"
fi

sleep 5 # Add delay to allow role propagation

# Step 3: Create WebSocket API
API_ID=$(aws apigatewayv2 create-api --name $API_NAME \
    --protocol-type WEBSOCKET \
    --route-selection-expression '$request.body.action' \
    --region $REGION \
    --query 'ApiId' --output text)

# Create a WebSocket route
echo "Creating WebSocket routes..."

# Create API Gateway Integration with Lambda

INTEGRATION_ID=$(aws apigatewayv2 create-integration --api-id $API_ID \
    --integration-type AWS_PROXY \
    --integration-method POST \
    --integration-uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
    --region $REGION \
    --query 'IntegrationId' --output text)

echo "Created Lambda integration with ID: $INTEGRATION_ID"

# Configure routes with Lambda integration
echo "Configuring routes to use Lambda integration..."

# Create $connect route
CONNECT_ROUTE_ID=$(aws apigatewayv2 create-route --api-id $API_ID \
    --route-key "\$connect" \
    --authorization-type NONE \
    --region $REGION \
    --query 'RouteId' --output text)

# Update $connect route with integration
aws apigatewayv2 update-route --api-id $API_ID \
    --route-id $CONNECT_ROUTE_ID \
    --target "integrations/$INTEGRATION_ID" \
    --region $REGION

echo "Created and configured \$connect route"

# Create $disconnect route
DISCONNECT_ROUTE_ID=$(aws apigatewayv2 create-route --api-id $API_ID \
    --route-key "\$disconnect" \
    --authorization-type NONE \
    --region $REGION \
    --query 'RouteId' --output text)

# Update $disconnect route with integration
aws apigatewayv2 update-route --api-id $API_ID \
    --route-id $DISCONNECT_ROUTE_ID \
    --target "integrations/$INTEGRATION_ID" \
    --region $REGION

echo "Created and configured \$disconnect route"

# Create $default route
DEFAULT_ROUTE_ID=$(aws apigatewayv2 create-route --api-id $API_ID \
    --route-key "\$default" \
    --authorization-type NONE \
    --region $REGION \
    --query 'RouteId' --output text)

# Update $default route with integration
aws apigatewayv2 update-route --api-id $API_ID \
    --route-id $DEFAULT_ROUTE_ID \
    --target "integrations/$INTEGRATION_ID" \
    --region $REGION

echo "Created and configured \$default route"

# Add Lambda permission for $default route
echo "Adding Lambda permission for route..."
aws lambda add-permission \
    --function-name $(echo $LAMBDA_ARN | cut -d':' -f7) \
    --statement-id apigateway-websocket-default-$(date +%s) \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$(echo $LAMBDA_ARN | cut -d':' -f5):$API_ID/*/*" \
    --region $REGION

# Deploy the API to a stage
echo "Deploying WebSocket API to 'production' stage..."
DEPLOYMENT_ID=$(aws apigatewayv2 create-deployment --api-id $API_ID \
    --region $REGION \
    --query 'DeploymentId' --output text)

# Create a stage
STAGE_NAME="production"
aws apigatewayv2 create-stage --api-id $API_ID \
    --deployment-id $DEPLOYMENT_ID \
    --stage-name $STAGE_NAME \
    --region $REGION

# Get the WebSocket URL
WEBSOCKET_URL="wss://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE_NAME"
echo "WebSocket API deployed successfully!"
echo "WebSocket URL: $WEBSOCKET_URL"


# Step 4: Create S3 Bucket for Bedrock Knowledge Base
echo "Creating S3 bucket..."
aws s3api create-bucket --bucket $S3_BUCKET_NAME --region $REGION 
aws s3api create-bucket --bucket $WEB_BUCKET_NAME --region $REGION

echo "S3 bucket created: $S3_BUCKET_NAME"
echo "web portal S3 bucket created: $WEB_BUCKET_NAME"

# Step 5: Create Bedrock Knowledge Base with OpenSearch Serverless
# Create the trust policy JSON
echo "Creating trust policy..."
cat > bedrock-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "bedrock.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the permissions policy JSON
echo "Creating permissions policy..."
cat > bedrock-permissions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:CreateKnowledgeBase",
                "bedrock:GetKnowledgeBase",
                "bedrock:UpdateKnowledgeBase",
                "bedrock:DeleteKnowledgeBase",
                "bedrock:ListKnowledgeBases",
                "bedrock:TagResource",
                "bedrock:UntagResource",
                "bedrock:ListTagsForResource",
                "bedrock:CreateDataSource",
                "bedrock:GetDataSource",
                "bedrock:UpdateDataSource",
                "bedrock:DeleteDataSource",
                "bedrock:ListDataSources",
                "bedrock:StartIngestionJob",
                "bedrock:GetIngestionJob",
                "bedrock:ListIngestionJobs"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::*",
                "arn:aws:s3:::*/*"
            ]
        },
         {
            "Effect": "Allow",
            "Action": [
                "aoss:APIAccessAll",
                "aoss:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
# Create the IAM role
# echo "Creating IAM role..."

if ! aws iam get-role --role-name $ROLE_NAME > /dev/null 2>&1; then
    echo "Creating new role: $ROLE_NAME"
    ROLE_ARN=$(aws iam create-role --role-name $ROLE_NAME \
    --assume-role-policy-document file://bedrock-trust-policy.json \
    --query 'Role.Arn' --output text)

    if [ $? -eq 0 ]; then
        echo "Role created successfully: $ROLE_ARN"
    else
        echo "Failed to create role"
    fi

    sleep 5 # Add delay to allow role propagation

    # Attach the permissions policy to the role
    echo "Attaching permissions policy to role..."
    aws iam put-role-policy --role-name $ROLE_NAME \
        --policy-name $POLICY_NAME \
        --policy-document file://bedrock-permissions-policy.json

    if [ $? -eq 0 ]; then
        echo "Policy attached successfully"
    else
        echo "Failed to attach policy"
    fi

else
    echo "Role already exists, getting role ARN..."
    ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)
    echo "Existing Role ARN: $ROLE_ARN"
fi

echo "CHECK ROLE ARN: $ROLE_ARN"
# Step 2: Create encryption policy FIRST, before creating the collection
echo "Creating security policy 1..."
cat > security-policy.json << EOF
{
  "Rules": [
    {
      "ResourceType": "collection",
      "Resource": ["collection/$COLLECTION_NAME"]
    }
  ],
  "AWSOwnedKey": true
}
EOF

aws opensearchserverless create-security-policy \
  --name "${COLLECTION_NAME}-security-policy" \
  --type "encryption" \
  --policy file://security-policy.json \
  --region $REGION

echo "Encryption security policy created"

aws opensearchserverless create-collection \
  --name $COLLECTION_NAME \
  --type "VECTORSEARCH" \
  --region $REGION


echo "Waiting for collection to be active..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT+1))
  echo "Checking collection status (attempt $ATTEMPT of $MAX_ATTEMPTS)..."
  
  # Use list-collections instead and filter for our collection
  COLLECTION_INFO=$(aws opensearchserverless list-collections \
    --region $REGION \
    --output json)
  
  echo "Collection info: $COLLECTION_INFO"
  # Check if our collection is in the list
   if [ -n "$COLLECTION_INFO" ]; then
    # Use a safer jq approach
    if command -v jq > /dev/null; then
      # Look for a specific collection by name and get its status
      STATUS=$(echo "$COLLECTION_INFO" | jq -r --arg name "$COLLECTION_NAME" '.collectionSummaries[] | select(.name == $name) | .status // "NOT_FOUND"')
      
      # If jq didn't find the collection or status
      if [ -z "$STATUS" ] || [ "$STATUS" == "null" ] || [ "$STATUS" == "NOT_FOUND" ]; then
        echo "Collection not found in list yet, waiting..."
      else
        echo "Collection status: $STATUS"
        
        if [ "$STATUS" == "ACTIVE" ]; then
          echo "Collection is now active!"
          break
        else
          echo "Collection is in $STATUS state, continuing to wait..."
        fi
      fi
    else
      # Fallback if jq is not available
      if echo "$COLLECTION_INFO" | grep -q "\"name\": \"$COLLECTION_NAME\""; then
        STATUS=$(echo "$COLLECTION_INFO" | grep -A 10 "\"name\": \"$COLLECTION_NAME\"" | grep "\"status\":" | head -1 | sed 's/.*"status": "\([^"]*\)".*/\1/')
        echo "Collection status: $STATUS"
        
        if [ "$STATUS" == "ACTIVE" ]; then
          echo "Collection is now active!"
          break
        fi
      else
        echo "Collection not found in list yet, waiting..."
      fi
    fi
  else
    echo "No collections found, waiting..."
  fi
  
  if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "Maximum attempts reached. Proceeding anyway..."
  fi
  
  sleep 30
done

cat > network-policy.json << EOF
[{
  "Rules": [
    {
      "ResourceType": "dashboard",
      "Resource": ["collection/$COLLECTION_NAME"]
    },
    {
      "ResourceType": "collection",
      "Resource": ["collection/$COLLECTION_NAME"]
    }
  ],
  "AllowFromPublic": true
}]
EOF

echo "Creating network policy..."
aws opensearchserverless create-security-policy \
  --name "${COLLECTION_NAME}-network-policy" \
  --type "network" \
  --policy file://network-policy.json \
  --region $REGION

# Step 5: Create data access policy for the collection

CURRENT_ROLE_ARN=$(aws sts get-caller-identity --query "Arn" --output text)
echo "Check role: $ROLE_ARN  $CURRENT_ROLE_ARN"

cat > access-policy.json << EOF
[{
  "Rules": [
    {
      "ResourceType": "collection",
      "Resource": ["collection/*"],
      "Permission": [
        "aoss:*"
      ]
    },
    {
      "ResourceType": "index",
      "Resource": ["index/*/*"],
      "Permission": [
        "aoss:*"
      ]
    }
  ],
  "Principal": ["$ROLE_ARN", "$CURRENT_ROLE_ARN"]
}]
EOF

echo "Creating data access policy..."
aws opensearchserverless create-access-policy \
  --name "${COLLECTION_NAME}-access-policy" \
  --type "data" \
  --policy file://access-policy.json \
  --region $REGION

# Get collection endpoint and ARN
COLLECTION_ENDPOINT=$(aws opensearchserverless batch-get-collection \
  --names $COLLECTION_NAME \
  --region $REGION \
  --query 'collectionDetails[0].collectionEndpoint' \
  --output text)

COLLECTION_ARN=$(aws opensearchserverless batch-get-collection \
  --names "$COLLECTION_NAME" \
  --region $REGION \
  --query 'collectionDetails[0].arn' \
  --output text)

# After you've created your data access policy and obtained the collection endpoint

echo "Creating index in OpenSearch Serverless..."
sleep 10


# First, create a JSON file with the index configuration
cat > index-config.json << EOF
{
    "settings": {
        "index.knn": "true",
        "number_of_shards": 1,
        "knn.algo_param.ef_search": 512,
        "number_of_replicas": 0
    },
    "mappings": {
        "properties": {
            "vector": {
                "type": "knn_vector",
                "dimension": 1024,
                "method": {
                    "name": "hnsw",
                    "engine": "faiss",
                    "space_type": "l2"
                }
            },
            "text": {"type": "text"},
            "text-metadata": {"type": "text"}
        }
    }
}
EOF
sleep 50
# Define index name
INDEX_NAME="kb-index"

# Create the index using AWS CLI with a signed HTTP request
# First, get temporary credentials for the collection
echo "Creating index '$INDEX_NAME' in collection '$COLLECTION_NAME'..."

if command -v pip &> /dev/null; then
    pip install awscurl
elif command -v pip3 &> /dev/null; then
    pip3 install awscurl
else
    echo "Error: pip or pip3 is not installed. Please install Python and pip first."
    echo "For Ubuntu/Debian: sudo apt-get update && sudo apt-get install -y python3-pip"
    echo "For CentOS/RHEL: sudo yum install -y python3-pip"
    echo "For macOS: brew install python"
    exit 1
fi

sleep 20

# Use awscurl if available (this handles AWS SigV4 signing)
if command -v awscurl &> /dev/null; then
  awscurl --region $REGION \
    --service aoss \
    -X PUT "$COLLECTION_ENDPOINT/$INDEX_NAME" \
    -H "Content-Type: application/json" \
    -d @index-config.json
else
  # Alternative approach using Python if awscurl is not available
  echo "awscurl not found. Using Python for index creation..."
  
  cat > create_index.py << EOF
import boto3
import requests
import json
from requests_aws4auth import AWS4Auth

# Configuration
region = '$REGION'
service = 'aoss'
collection_endpoint = '$COLLECTION_ENDPOINT'
index_name = '$INDEX_NAME'

# Create AWS4Auth instance
credentials = boto3.Session().get_credentials()
awsauth = AWS4Auth(
    credentials.access_key,
    credentials.secret_key,
    region,
    service,
    session_token=credentials.token
)

# Load index configuration
with open('index-config.json', 'r') as f:
    index_config = json.load(f)

# Create the index
url = f'{collection_endpoint}/{index_name}'
headers = {'Content-Type': 'application/json'}
response = requests.put(url, auth=awsauth, json=index_config, headers=headers)

# Print the response
print(f"Status code: {response.status_code}")
print(f"Response: {response.text}")
EOF

  # Install required Python packages if necessary
  pip install boto3 requests requests-aws4auth --quiet

  # Run the Python script
  python create_index.py
fi

echo "Index creation complete."

# Verify the index has been created
echo "Verifying index creation..."
if command -v awscurl &> /dev/null; then
  awscurl --region $REGION \
    --service aoss \
    -X GET "$COLLECTION_ENDPOINT/_cat/indices?v"
else
  # Alternative verification using Python
  cat > verify_index.py << EOF
import boto3
import requests
from requests_aws4auth import AWS4Auth

# Configuration
region = '$REGION'
service = 'aoss'
collection_endpoint = '$COLLECTION_ENDPOINT'

# Create AWS4Auth instance
credentials = boto3.Session().get_credentials()
awsauth = AWS4Auth(
    credentials.access_key,
    credentials.secret_key,
    region,
    service,
    session_token=credentials.token
)

# Check indices
url = f'{collection_endpoint}/_cat/indices?v'
response = requests.get(url, auth=awsauth)

# Print the response
print(f"Status code: {response.status_code}")
print(f"Available indices:")
print(response.text)
EOF

  # Run the Python verification script
  python verify_index.py
fi

sleep 120

# Step 6: Create the Bedrock Knowledge Base
echo "Creating Bedrock Knowledge Base..."

# Create knowledge base configuration file
cat > kb-config.json << EOF
{
   "type": "VECTOR",
   "vectorKnowledgeBaseConfiguration": {
        "embeddingModelArn": "$EMBED_MODEL_ARN",
        "embeddingModelConfiguration": {
            "bedrockEmbeddingModelConfiguration": {
                "dimensions": 1024
            }
        }
    }
}
EOF

sleep 10 
cat > storage.json << EOF
{
 "opensearchServerlessConfiguration": {
    "collectionArn": "$COLLECTION_ARN",
    "fieldMapping": {
        "metadataField": "text-metadata",
        "textField": "text",
        "vectorField": "vector"
        },
    "vectorIndexName": "$INDEX_NAME"
    },
 "type": "OPENSEARCH_SERVERLESS"
}
EOF

echo "check collection $COLLECTION_ARN"

sleep 5 

KNOWLEDGE_BASE_ID=$(aws bedrock-agent create-knowledge-base \
  --name $KNOWLEDGE_BASE_NAME \
  --role-arn $ROLE_ARN \
  --knowledge-base-configuration file://kb-config.json \
  --storage-configuration file://storage.json \
  --region $REGION \
  --query 'knowledgeBase.knowledgeBaseId' \
  --output text)


echo "Knowledge Base created with ID: $KNOWLEDGE_BASE_ID"

# Step 7: Create S3 data source
echo "Creating S3 data source..."

CURRENT_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text) 
# Create S3 data source configuration

sleep 5
cat > s3-source-config.json << EOF
{
  "type": "S3",
  "s3Configuration": {
    "bucketArn": "arn:aws:s3:::$S3_BUCKET_NAME",
    "bucketOwnerAccountId": "$CURRENT_ACCOUNT_ID"
  }
}
EOF

S3_DATA_SOURCE_ID=$(aws bedrock-agent create-data-source \
  --knowledge-base-id $KNOWLEDGE_BASE_ID \
  --name "${KNOWLEDGE_BASE_NAME}-s3-source" \
  --data-source-configuration file://s3-source-config.json \
  --data-deletion-policy "RETAIN" \
  --region $REGION \
  --query 'dataSource.dataSourceId' \
  --output text)

echo "S3 data source created with ID: $S3_DATA_SOURCE_ID"

# Step 8: Create web crawler data source
echo "Creating web crawler data source..."

# Create web crawler data source configuration
cat > web-crawler-config.json << EOF
{
  "type": "WEB",
  "webConfiguration": {
    "sourceConfiguration": {
        "urlConfiguration": {
            "seedUrls": [
                {"url": "$WEB_CRAWLER_URL"}
            ]
        }
    }
  }
  
}
EOF

WEB_CRAWLER_DATA_SOURCE_ID=$(aws bedrock-agent create-data-source \
  --knowledge-base-id $KNOWLEDGE_BASE_ID \
  --name "${KNOWLEDGE_BASE_NAME}-web-crawler-source" \
  --data-source-configuration file://web-crawler-config.json \
  --data-deletion-policy "RETAIN" \
  --region $REGION \
  --query 'dataSource.dataSourceId' \
  --output text)

echo "Web crawler data source created with ID: $WEB_CRAWLER_DATA_SOURCE_ID"

# Step 9: Start the ingestion jobs for both data sources
echo "Starting S3 data source ingestion job..."
S3_INGESTION_JOB_ID=$(aws bedrock-agent start-ingestion-job \
  --knowledge-base-id $KNOWLEDGE_BASE_ID \
  --data-source-id $S3_DATA_SOURCE_ID \
  --region $REGION \
  --query 'ingestionJob.ingestionJobId' \
  --output text)

echo "S3 ingestion job started with ID: $S3_INGESTION_JOB_ID"

echo "Starting web crawler data source ingestion job..."
WEB_CRAWLER_INGESTION_JOB_ID=$(aws bedrock-agent start-ingestion-job \
  --knowledge-base-id $KNOWLEDGE_BASE_ID \
  --data-source-id $WEB_CRAWLER_DATA_SOURCE_ID \
  --region $REGION \
  --query 'ingestionJob.ingestionJobId' \
  --output text)

echo "Web crawler ingestion job started with ID: $WEB_CRAWLER_INGESTION_JOB_ID"

sleep 3

PROMPT_NAME="KnowledgeBasePrompt"
MODEL_ID="amazon.nova-pro-v1:0"

cat > prompt_config.json << EOF
[
  {
      "inferenceConfiguration": {
          "text": {
          "maxTokens": 1024,
          "temperature": 0
          }
      },
      "templateConfiguration": {
          "text": {
              "text": "Human: You are a question answering agent. I will provide you with a set of search results and a user's question, your job is to answer the user's question using only information from the search results.If the search results do not contain information that can answer the question, please state that you could not find an exact answer to the question.Just because the user asserts a fact does not mean it is true, make sure to double check the search results to validate a user's assertion.\n\nHere are the search results in numbered order:\n<context>\n\$search_results\$\n</context>\n\nHere is the user's question:\n<question>\n\$query\$\n</question>\n\n\nAssistant:"
          }
      },
      "templateType": "TEXT",
      "modelId": "$MODEL_ID",
      "name": "KnowledgeBasePrompt"
  }
]
EOF

PROMPT_ID=$(aws bedrock-agent create-prompt \
  --name "$PROMPT_NAME" \
  --variants file://prompt_config.json \
  --query "id" \
  --output text)

# Clean up JSON files
# rm -f bedrock-trust-policy.json prompt_config.json bedrock-policy.json security-policy.json network-policy.json access-policy.json kb-config.json s3-source-config.json web-crawler-config.json storage.json index-config.json bedrock-permissions-policy.json

API_GW_URL="https://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE_NAME"
WEBSOCKET_URL="wss://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE_NAME"

cat > env-vars.json << EOF
{
  "Variables": {
    "API_GW_URL": "$API_GW_URL",
    "WEBSOCKET_URL": "$WEBSOCKET_URL",
    "WEB_BUCKET_NAME": "$WEB_BUCKET_NAME",
    "KNOWLEDGE_BASE_ID": "$KNOWLEDGE_BASE_ID",
    "PROMPT_ID": "$PROMPT_ID"
  }
}
EOF

aws lambda update-function-configuration \
  --function-name $LAMBDA_NAME \
  --environment file://env-vars.json

echo "Getting default VPC information..."
# Get the Default VPC ID
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" \
    --output text)

if [ -z "$DEFAULT_VPC_ID" ]; then
    echo "Error: No default VPC found in region $REGION"
    exit 1
fi

echo "Default VPC ID: $DEFAULT_VPC_ID"

# Get subnet IDs from the default VPC
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" \
    --query "Subnets[*].SubnetId" \
    --output text)

echo "Available Subnets: $SUBNET_IDS"

# Get default security group for the VPC
DEFAULT_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" "Name=group-name,Values=default" \
    --query "SecurityGroups[0].GroupId" \
    --output text)

echo "Default Security Group ID: $DEFAULT_SG_ID"

echo "Creating Redshift subnet group..."
# Create a Redshift subnet group if it doesn't exist already
aws redshift create-cluster-subnet-group \
    --cluster-subnet-group-name $SUBNET_GROUP_NAME \
    --description "Default subnet group for Redshift cluster" \
    --subnet-ids $SUBNET_IDS \
    --tags Key=Purpose,Value=RedshiftCluster || echo "Subnet group may already exist, continuing..."

if [ "$PUBLICLY_ACCESSIBLE" = true ]; then
    PUBLIC_ACCESS_FLAG="--publicly-accessible"
else
    PUBLIC_ACCESS_FLAG="--no-publicly-accessible"
fi

echo "Creating Redshift cluster..."
# Create the Redshift cluster
if [ "$CLUSTER_TYPE" = "single-node" ]; then
    aws redshift create-cluster \
        --cluster-identifier $CLUSTER_IDENTIFIER \
        --node-type $NODE_TYPE \
        --master-username $MASTER_USERNAME \
        --master-user-password $MASTER_PASSWORD \
        --cluster-type $CLUSTER_TYPE \
        --db-name $DB_NAME \
        --cluster-subnet-group-name $SUBNET_GROUP_NAME \
        --vpc-security-group-ids $DEFAULT_SG_ID \
        $PUBLIC_ACCESS_FLAG \
        --tags Key=Environment,Value=Development
else
    aws redshift create-cluster \
        --cluster-identifier $CLUSTER_IDENTIFIER \
        --node-type $NODE_TYPE \
        --master-username $MASTER_USERNAME \
        --master-user-password $MASTER_PASSWORD \
        --cluster-type $CLUSTER_TYPE \
        --number-of-nodes $NODE_COUNT \
        --db-name $DB_NAME \
        --cluster-subnet-group-name $SUBNET_GROUP_NAME \
        --vpc-security-group-ids $DEFAULT_SG_ID \
        $PUBLIC_ACCESS_FLAG 
fi

echo "Waiting for cluster to become available..."
aws redshift wait cluster-available --cluster-identifier $CLUSTER_IDENTIFIER

echo "Getting cluster information..."
aws redshift describe-clusters --cluster-identifier $CLUSTER_IDENTIFIER

echo "Redshift cluster setup completed successfully!"
echo "Cluster endpoint information is displayed above."
echo "Database: $DB_NAME"
echo "Username: $MASTER_USERNAME"
echo "Password: $MASTER_PASSWORD"

echo "Bedrock Knowledge Base setup complete!"
echo "Websocket Url: $WEBSOCKET_URL"
echo "Web bucket name: $WEB_BUCKET_NAME"