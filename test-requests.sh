#!/bin/bash

# Replace with your N8N webhook URL
BASE_URL="https://your-n8n.com/webhook/disposable-marketplace"

echo "🚀 Testing Disposable Marketplace"

# 1. Start quote collection
echo "1. Starting quote collection..."
curl -X POST "$BASE_URL/start" \
  -H "Content-Type: application/json" \
  -d '{
    "csvUrl": "https://raw.githubusercontent.com/your-repo/disposable-marketplace-n8n/main/example-resellers.csv",
    "product": {
      "brand": "Rolex",
      "model": "Submariner 16610",
      "year": "2010",
      "condition": "Excellent",
      "serial": "X123456"
    },
    "callbackBaseUrl": "https://your-n8n.com"
  }'

echo -e "\n\n⏱️  Waiting 5 seconds...\n"
sleep 5

# 2. Submit test offers
echo "2. Submitting test offers..."

curl -X POST "$BASE_URL/offer" \
  -H "Content-Type: application/json" \
  -d '{
    "reseller_id": "ROLEX_SPEC",
    "reseller_name": "Rolex Specialists Inc",
    "price": 12500,
    "currency": "USD",
    "terms": "Wire transfer, 24h settlement",
    "response_time": 90,
    "trust_score": 9.5,
    "region": "US"
  }'

curl -X POST "$BASE_URL/offer" \
  -H "Content-Type: application/json" \
  -d '{
    "reseller_id": "SWISS001",
    "reseller_name": "Swiss Watch Specialists",
    "price": 11800,
    "currency": "USD",
    "terms": "Bank transfer, 48h",
    "response_time": 120,
    "trust_score": 9.1,
    "region": "EU"
  }'

curl -X POST "$BASE_URL/offer" \
  -H "Content-Type: application/json" \
  -d '{
    "reseller_id": "USA999",
    "reseller_name": "American Watch Co",
    "price": 10500,
    "currency": "USD",
    "terms": "Certified check",
    "response_time": 200,
    "trust_score": 7.8,
    "region": "US"
  }'

echo -e "\n\n📊 Getting summary..."

# 3. Get summary
curl "$BASE_URL/summary?limit=5"

echo -e "\n\n✅ Test complete!"