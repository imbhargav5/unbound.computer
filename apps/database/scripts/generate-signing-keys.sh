#!/bin/bash
# Generate signing keys for Supabase auth
# The command outputs a single object, but config expects an array

cd "$(dirname "$0")/../supabase"

# Generate signing key and wrap in array
echo "[$(supabase gen signing-key --algorithm ES256)]" > signing_keys.json

echo "Generated signing_keys.json"
