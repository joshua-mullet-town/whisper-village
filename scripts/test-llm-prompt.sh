#!/bin/bash

# Test the two-stage formatting prompt with OpenAI GPT-5 Mini
# Usage: ./test-llm-prompt.sh <your-openai-api-key>

API_KEY="${1:-$OPENAI_API_KEY}"

if [ -z "$API_KEY" ]; then
    echo "Usage: ./test-llm-prompt.sh <your-openai-api-key>"
    echo "Or set OPENAI_API_KEY environment variable"
    exit 1
fi

# Test cases: [message, instruction, description]
echo "=========================================="
echo "Testing Two-Stage Formatting Prompt"
echo "Model: gpt-4o-mini (using available model)"
echo "=========================================="

run_test() {
    local test_name="$1"
    local message="$2"
    local instruction="$3"

    echo ""
    echo "--- TEST: $test_name ---"
    echo "MESSAGE: $message"
    echo "INSTRUCTION: $instruction"
    echo ""

    local prompt="The user recorded a message and then recorded instructions for how to format it.

CRITICAL: Maintain the user's voice and tone exactly. Do not make it more or less professional or friendly than it already is. Use all the existing words and phrasing where possible. Only clean up where necessary - fix incorrect words, obvious mistakes, or apply the specific formatting requested. Preserve their personality.

MESSAGE:
$message

FORMATTING INSTRUCTIONS:
$instruction

Return ONLY the formatted message. No explanations or commentary."

    local response=$(curl -s https://api.openai.com/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        -d "{
            \"model\": \"gpt-4o-mini\",
            \"messages\": [{\"role\": \"user\", \"content\": $(echo "$prompt" | jq -Rs .)}],
            \"temperature\": 0.3
        }")

    echo "RESULT:"
    echo "$response" | jq -r '.choices[0].message.content // .error.message'
    echo ""
}

# Test 1: Casual email
run_test "Casual Email" \
    "hey so I was thinking we should probably get together sometime next week to talk about that project thing you know the one with the dashboard and all that stuff maybe tuesday or wednesday works for me let me know what you think" \
    "make this an email"

# Test 2: List extraction
run_test "List Extraction" \
    "okay so I need to get milk and eggs and also bread and oh yeah pick up the dry cleaning and don't forget to call the dentist about that appointment thing" \
    "format as a bullet list"

# Test 3: Markdown documentation
run_test "Markdown Docs" \
    "so the API endpoint should accept a user ID as a parameter and then return their profile data which includes their name and email address and also their preferences like notification settings and theme and stuff like that" \
    "write this as markdown documentation"

# Test 4: Voice preservation test (casual)
run_test "Voice Preservation - Casual" \
    "dude this meeting was like super long and honestly kinda boring but whatever we got through it and basically the main takeaway is we gotta finish the thing by friday or else" \
    "clean this up but keep my casual tone"

# Test 5: Voice preservation test (professional)
run_test "Voice Preservation - Professional" \
    "I wanted to follow up on our discussion regarding the quarterly projections and I believe we need to reassess our targets given the current market conditions" \
    "format this as a formal email"

echo "=========================================="
echo "Tests complete!"
echo "=========================================="
