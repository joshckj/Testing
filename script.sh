#!/bin/bash
# =============================================================================
# available_models.sh
# Lists all available models on the SP Digital LiteLLM endpoint
# Usage: ./available_models.sh
# =============================================================================

API_KEY="sk-677s9TsQeLwaZF1W_8dfyg"
BASE_URL="https://litellm.qa.in.spdigital.sg"

echo "Fetching available models from $BASE_URL..."
echo ""

curl -s "$BASE_URL/models" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" | python3 -m json.tool

echo ""
echo "Done."
