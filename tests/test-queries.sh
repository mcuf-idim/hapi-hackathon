#!/bin/bash

# FHIR Server Test Queries
# Tests complex relationships and searches in the HAPI FHIR server

FHIR_BASE="${FHIR_BASE:-http://localhost:8080/fhir}"

LOCATION_IDS=("81c75a54-2b95-3fdf-9327-b74df8630869" "2ac42b29-8d6a-3319-a57a-c9b68dc54c0d" "78175de6-182e-3f6d-a7f8-deb7cc543841")
PRACTITIONER_IDS=("f0e94ce1-83e3-3bc2-8c77-31c5838ba5ed" "913df346-b12f-3499-b54f-333b41887c84" "914849bd-aeac-3505-9499-9ad2e6303d99")
PATIENT_IDS=("1758caee-08df-7067-6979-8b60105a91c0" "9b5bf1f7-6757-fd7f-65ae-020e06e0d48d" "d5157dcd-b473-62c6-961b-5ffacffb94b8")
ENCOUNTER_IDS=("691208cc-4323-9d2c-9b48-af819e8cc654" "7776675a-bdb2-7ac5-5b1b-6eb5e6be4bfc" "27442c1f-d905-e542-d6bc-e4335003b9ae")

# Function to run a query and display results
run_query() {
    local query_name=$1
    local query_url=$2
    local resource_type=$3
    local id=$4
    
    # Replace {id} placeholder with actual ID
    query_url="${query_url//\{id\}/$id}"
    
    echo "▶ ${query_name}"
    echo "  ${resource_type} ID: ${id}"
    echo "  Query: ${query_url}"
    
    # Execute query and get response
    response=$(curl -s "${FHIR_BASE}${query_url}")
    
    # Check if we got a Bundle response
    if echo "$response" | jq -e '.resourceType == "Bundle"' > /dev/null 2>&1; then
        total=$(echo "$response" | jq -r '.total // 0')
        resource_count=$(echo "$response" | jq -r '.entry | length // 0')
        
        if [[ "$query_url" == *"_include"* ]]; then
            echo "  Results: ${total} primary matches, ${resource_count} total resources in bundle (includes related resources)"
        else
            echo "  Results: ${total} matches, ${resource_count} resources returned"
        fi
        
        # Show first few resource types returned
        echo "$response" | jq -r '.entry[0:3] | .[] | "    - \(.resource.resourceType): \(.resource.id)"' 2>/dev/null
    else
        echo "  Results: Query failed or returned unexpected format"
    fi
    echo ""
}

echo "Testing server at: ${FHIR_BASE}"
echo ""

# Test 1: Location Query - Encounters at specific locations
echo "═══ Test 1: Location-based Encounter Search ═══"
for id in "${LOCATION_IDS[@]}"; do
    run_query \
        "Encounters at Location with Patient details" \
        "/Encounter?location=${id}&date=ge2020-01-01&date=le2020-12-31&_include=Encounter:patient" \
        "Location" \
        "$id"
done

# Test 2: Practitioner Workload Query
echo "═══ Test 2: Practitioner Workload Analysis ═══"
for id in "${PRACTITIONER_IDS[@]}"; do
    run_query \
        "Practitioner encounters over time period" \
        "/Encounter?participant=Practitioner/${id}&date=ge2015-01-01&date=le2024-03-31&_include=Encounter:participant" \
        "Practitioner" \
        "$id"
done

# Test 3: Condition Query - Patient conditions with related resources
echo "═══ Test 3: Patient Conditions with Context ═══"
for id in "${PATIENT_IDS[@]}"; do
    run_query \
        "Patient conditions with encounter context" \
        "/Condition?patient=${id}&_include=Condition:patient&_include=Condition:encounter" \
        "Patient" \
        "$id"
done

# Test 4: Procedure by Patient, including Encounter and Performer
echo "═══ Test 4: Patient Procedures with Context ═══"
for id in "${PATIENT_IDS[@]}"; do
    run_query \
        "Procedures for patient with encounter and performer details" \
        "/Procedure?subject=Patient/${id}&_include=Procedure:encounter&_include=Procedure:performer" \
        "Patient" \
        "$id"
done

# Test 5: Immunization by Patient and Date, including Performer and Location
echo "═══ Test 5: Patient Immunizations with Location ═══"
for id in "${PATIENT_IDS[@]}"; do
    run_query \
        "Immunizations for patient since 2020 with location and performer" \
        "/Immunization?patient=Patient/${id}&date=ge2020-01-01&_include=Immunization:performer&_include=Immunization:location" \
        "Patient" \
        "$id"
done

# Quick resource count summary
echo "Resource Counts:"
for resource in Patient Practitioner Location Encounter Observation Condition Procedure Immunization; do
    count=$(curl -s "${FHIR_BASE}/${resource}?_summary=count" | jq -r '.total // 0')
    echo "  ${resource}: ${count}"
done

echo ""
echo "Happy Hacking at the Black Forest Hackathon 2025! 🌲🚀"
