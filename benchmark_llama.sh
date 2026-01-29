#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  llama-server Benchmark Script
#  Tests: token speed, reasoning, concurrency, prompt caching
#═══════════════════════════════════════════════════════════════════════════════

SERVER="${LLAMA_SERVER:-http://localhost:8080}"

# Colors
GRN='\033[0;32m'
CYN='\033[0;36m'
NC='\033[0m'

#───────────────────────────────────────────────────────────────────────────────
# Single request benchmark
#───────────────────────────────────────────────────────────────────────────────
bench() {
    local name="$1"
    local prompt="$2"
    local max_tokens="${3:-256}"
    local extra="${4:-}"

    local response=$(curl -s "$SERVER/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"qwen\",\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}],\"max_tokens\":$max_tokens$extra}")

    local tps=$(echo "$response" | jq '.timings.predicted_per_second // 0')
    local tokens=$(echo "$response" | jq '.usage.completion_tokens // 0')
    local finish=$(echo "$response" | jq -r '.choices[0].finish_reason // "?"')

    printf "  %-22s %6.1f tok/s | %4d tokens | %s\n" "$name" "$tps" "$tokens" "$finish"
}

#───────────────────────────────────────────────────────────────────────────────
# Concurrent benchmark
#───────────────────────────────────────────────────────────────────────────────
bench_concurrent() {
    local n="$1"
    local start=$(date +%s.%N)

    for i in $(seq 1 $n); do
        curl -s "$SERVER/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"qwen\",\"messages\":[{\"role\":\"user\",\"content\":\"Count to 10. Request $i\"}],\"max_tokens\":80}" \
            > /tmp/conc_$i.json &
    done
    wait

    local end=$(date +%s.%N)
    local total_time=$(echo "$end - $start" | bc)
    local total_tokens=0
    for i in $(seq 1 $n); do
        local t=$(jq '.usage.completion_tokens // 0' /tmp/conc_$i.json)
        total_tokens=$((total_tokens + t))
    done
    rm -f /tmp/conc_*.json

    local agg_tps=$(echo "scale=1; $total_tokens / $total_time" | bc)
    printf "  %-22s %6.1f tok/s | %4d tokens | %.2fs total\n" "Concurrent x$n" "$agg_tps" "$total_tokens" "$total_time"
}

#───────────────────────────────────────────────────────────────────────────────
# Main
#───────────────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "  llama-server Benchmark - $(date '+%Y-%m-%d %H:%M')"
echo "  Server: $SERVER"
echo "═══════════════════════════════════════════════════════════════════════"

# Check server
if ! curl -s "$SERVER/health" | grep -q "ok"; then
    echo "ERROR: Server not responding"
    exit 1
fi
MODEL=$(curl -s "$SERVER/v1/models" | jq -r '.data[0].id' 2>/dev/null)
echo "  Model: $MODEL"
echo ""

echo "───────────────────────────────────────────────────────────────────────"
echo "  Token Generation Speed"
echo "───────────────────────────────────────────────────────────────────────"
bench "Short response" "Say hello in exactly 5 words." 32
bench "Medium response" "Explain what a GPU does in 2 sentences." 128
bench "Long response" "Write a 4-line poem about computers." 256
echo ""

echo "───────────────────────────────────────────────────────────────────────"
echo "  Reasoning Mode"
echo "───────────────────────────────────────────────────────────────────────"
bench "Math (with thinking)" "What is 23 * 17? Show work." 400 ",\"reasoning_format\":\"deepseek\""
bench "Logic puzzle" "If all cats are animals and some animals are pets, can we conclude all cats are pets?" 300 ",\"reasoning_format\":\"deepseek\""
echo ""

echo "───────────────────────────────────────────────────────────────────────"
echo "  Concurrent Requests"
echo "───────────────────────────────────────────────────────────────────────"
bench_concurrent 2
bench_concurrent 4
echo ""

echo "───────────────────────────────────────────────────────────────────────"
echo "  Code Generation"
echo "───────────────────────────────────────────────────────────────────────"
bench "Python function" "Write a Python function to check if a number is prime." 300
bench "Bash one-liner" "Write a bash command to find all .py files modified today." 100
echo ""

echo "═══════════════════════════════════════════════════════════════════════"
echo -e "  ${GRN}Benchmark Complete${NC}"
echo "═══════════════════════════════════════════════════════════════════════"
