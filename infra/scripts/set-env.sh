#!/bin/bash
# This script sets environment variables for local development based on Bicep outputs
# Usage: ./scripts/set-env.sh

# Get outputs from azd env get-values (assumes azd deployment)
echo "Getting environment variables from azd..."

# Create .env file with Bicep outputs
cat > .env << EOF
# Environment variables
# Generated from Bicep deployment outputs

# ---- AOAI/LLM/Embedding Model Variables ----
APIM_RESOURCE_GATEWAY_URL=$(azd env get-values | grep APIM_RESOURCE_GATEWAY_URL | cut -d'=' -f2 | tr -d '"')
API_KEY=$(azd env get-values | grep API_KEY | cut -d'=' -f2 | tr -d '"')
AZURE_OPENAI_DEPLOYMENT_NAME=$(azd env get-values | grep azureOpenAiDeploymentName | cut -d'=' -f2 | tr -d '"')
AZURE_OPENAI_API_VERSION=$(azd env get-values | grep azureOpenAiApiVersion | cut -d'=' -f2 | tr -d '"')
EOF

echo ".env file created successfully with deployment outputs!"
echo "You can now use 'docker-compose up' to test your container locally."