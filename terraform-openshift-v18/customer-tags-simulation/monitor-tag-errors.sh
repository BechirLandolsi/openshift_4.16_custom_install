#!/bin/bash
# ==============================================================================
# Monitor Tag-Related Errors
# ==============================================================================
# This script monitors CloudTrail for tag-related AccessDenied errors during
# OpenShift installation to verify that tag restrictions are being bypassed.
#
# Usage: ./monitor-tag-errors.sh [duration-in-minutes]
# Example: ./monitor-tag-errors.sh 30
# ==============================================================================

DURATION_MINUTES="${1:-10}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Monitor Tag-Related Errors (CloudTrail)                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${CYAN}Monitoring for tag-related errors for ${DURATION_MINUTES} minutes...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo

START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S")

check_errors() {
    echo -e "${CYAN}[$(date +%H:%M:%S)] Checking CloudTrail for tag errors...${NC}"
    
    # Check for CreateTags denials
    CREATE_TAG_ERRORS=$(aws cloudtrail lookup-events \
        --lookup-attributes AttributeKey=EventName,AttributeValue=CreateTags \
        --start-time "$START_TIME" \
        --max-results 50 \
        --query 'Events[?contains(CloudTrailEvent, `AccessDenied`)].[EventTime,CloudTrailEvent]' \
        --output text 2>&1)
    
    # Check for DeleteTags denials
    DELETE_TAG_ERRORS=$(aws cloudtrail lookup-events \
        --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteTags \
        --start-time "$START_TIME" \
        --max-results 50 \
        --query 'Events[?contains(CloudTrailEvent, `AccessDenied`)].[EventTime,CloudTrailEvent]' \
        --output text 2>&1)
    
    if [[ -n "$CREATE_TAG_ERRORS" ]] || [[ -n "$DELETE_TAG_ERRORS" ]]; then
        echo -e "${YELLOW}⚠ Tag-related AccessDenied errors detected:${NC}"
        
        if [[ -n "$CREATE_TAG_ERRORS" ]]; then
            echo -e "${RED}CreateTags Denials:${NC}"
            echo "$CREATE_TAG_ERRORS" | head -5
            echo
        fi
        
        if [[ -n "$DELETE_TAG_ERRORS" ]]; then
            echo -e "${RED}DeleteTags Denials:${NC}"
            echo "$DELETE_TAG_ERRORS" | head -5
            echo
        fi
        
        echo -e "${GREEN}✓ This is EXPECTED - OpenShift should bypass these errors!${NC}"
    else
        echo -e "${GREEN}✓ No tag-related errors detected in this interval${NC}"
    fi
    
    echo
}

# Monitor in a loop
END_TIME=$(($(date +%s) + ($DURATION_MINUTES * 60)))

while [[ $(date +%s) -lt $END_TIME ]]; do
    check_errors
    
    REMAINING=$((($END_TIME - $(date +%s)) / 60))
    echo -e "${CYAN}Time remaining: ${REMAINING} minutes${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    
    sleep 60
done

echo -e "${GREEN}✓ Monitoring complete!${NC}"
echo
echo -e "${CYAN}Summary:${NC}"
echo "• If you saw AccessDenied errors but installation succeeded,"
echo "  your OpenShift installer is handling immutable tags correctly!"
echo
echo "• If installation failed due to tag errors, the installer may need"
echo "  the custom tag bypass modifications."
echo
