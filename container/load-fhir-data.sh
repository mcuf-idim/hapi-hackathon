#!/bin/bash

# HAPI FHIR Data Loader Script
# Loads NDJSON files into a running HAPI FHIR server

FHIR_BASE_URL="http://localhost:8080/fhir"
DATA_DIR="./fhir-test-data"
BATCH_SIZE=100  # Number of resources per bundle

echo "HAPI FHIR Data Loader"
echo "===================="

# Parse command line arguments
FILES_TO_LOAD=""
for arg in "$@"; do
    case $arg in
        -files=*)
            FILES_TO_LOAD="${arg#*=}"
            shift
            ;;
        *)
            ;;
    esac
done

# Check if server is running
echo -n "Checking server... "
if ! curl -s -f "$FHIR_BASE_URL/metadata" > /dev/null 2>&1; then
    echo "Error: HAPI FHIR server not responding at $FHIR_BASE_URL"
    exit 1
fi
echo "OK"

# Function to load a single NDJSON file
load_file() {
    local file="$1"
    local resource_type="$2"
    
    [ -f "$file" ] || return
    
    echo -n "Loading $resource_type from $file... "
    
    line_count=0
    success_count=0
    batch_count=0
    
    # Start building a bundle
    bundle_entries=""
    
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        
        line_count=$((line_count + 1))
        batch_count=$((batch_count + 1))
        
        # Extract ID from the JSON line
        resource_id=$(echo "$line" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        
        if [ -z "$resource_id" ]; then
            continue
        fi
        
        # Add to bundle entries using PUT to preserve IDs
        if [ -n "$bundle_entries" ]; then
            bundle_entries="$bundle_entries,"
        fi
        bundle_entries="$bundle_entries{\"resource\":$line,\"request\":{\"method\":\"PUT\",\"url\":\"$resource_type/$resource_id\"}}"
        
        # Send bundle when batch size is reached
        if [ $batch_count -ge $BATCH_SIZE ]; then
            bundle="{\"resourceType\":\"Bundle\",\"type\":\"transaction\",\"entry\":[$bundle_entries]}"
            
            http_code=$(echo "$bundle" | curl -s -o /dev/null -w "%{http_code}" -X POST \
                -H "Content-Type: application/fhir+json" \
                -d @- \
                "$FHIR_BASE_URL")
            
            if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
                success_count=$((success_count + batch_count))
            fi
            
            # Reset for next batch
            bundle_entries=""
            batch_count=0
        fi
    done < "$file"
    
    # Send remaining entries if any
    if [ $batch_count -gt 0 ] && [ -n "$bundle_entries" ]; then
        bundle="{\"resourceType\":\"Bundle\",\"type\":\"transaction\",\"entry\":[$bundle_entries]}"
        
        http_code=$(echo "$bundle" | curl -s -o /dev/null -w "%{http_code}" -X POST \
            -H "Content-Type: application/fhir+json" \
            -d @- \
            "$FHIR_BASE_URL")
        
        if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
            success_count=$((success_count + batch_count))
        fi
    fi
    
    echo "$success_count/$line_count loaded"
}

# Check if specific files were requested
if [ -n "$FILES_TO_LOAD" ]; then
    # Process specified files in order
    IFS=',' read -ra FILES_ARRAY <<< "$FILES_TO_LOAD"
    for file in "${FILES_ARRAY[@]}"; do
        if [ ! -f "$file" ]; then
            echo "Error: File '$file' not found!"
            continue
        fi
        
        # Extract resource type from filename or first line
        filename=$(basename "$file" .ndjson)
        
        # Try to get resource type from first line if filename doesn't match
        first_line=$(head -n1 "$file" 2>/dev/null)
        resource_type=$(echo "$first_line" | grep -o '"resourceType":"[^"]*"' | cut -d'"' -f4)
        
        if [ -z "$resource_type" ]; then
            resource_type="$filename"
        fi
        
        load_file "$file" "$resource_type"
    done
else
    # Default behavior: load all files in dependency order
    # Check if data directory exists
    if [ ! -d "$DATA_DIR" ]; then
        echo "Error: Data directory '$DATA_DIR' not found!"
        exit 1
    fi
    
    # Define loading order - resources that are referenced should be loaded first
    LOAD_ORDER=(
        "Patient"
        "Practitioner"
        "Location"
        "Organization"
        "Medication"
        "Device"
        "Encounter"
        "Condition"
        "Observation"
        "Procedure"
        "AllergyIntolerance"
        "Immunization"
        "DiagnosticReport"
        "DocumentReference"
        "ImagingStudy"
        "MedicationRequest"
        "CarePlan"
        "MedicationAdministration"
        "MedicationDispense"
        "Claim"
    )
    
    # Process files in dependency order
    for resource_type in "${LOAD_ORDER[@]}"; do
        file="$DATA_DIR/$resource_type.ndjson"
        load_file "$file" "$resource_type"
    done
    
    # Process any remaining NDJSON files not in the load order
    for file in "$DATA_DIR"/*.ndjson; do
        [ -f "$file" ] || continue
        
        filename=$(basename "$file" .ndjson)
        
        # Skip if already processed
        for processed in "${LOAD_ORDER[@]}"; do
            [ "$filename" = "$processed" ] && continue 2
        done
        
        # Extract resource type from first line
        first_line=$(head -n1 "$file" 2>/dev/null)
        resource_type=$(echo "$first_line" | grep -o '"resourceType":"[^"]*"' | cut -d'"' -f4)
        
        if [ -z "$resource_type" ]; then
            resource_type="$filename"
        fi
        
        load_file "$file" "$resource_type"
    done
fi

echo ""
echo "Verifying data:"

# Count resources for each type
if [ -n "$FILES_TO_LOAD" ]; then
    # Count only for specified files - use a set to avoid duplicates
    declare -A resource_types_seen
    
    IFS=',' read -ra FILES_ARRAY <<< "$FILES_TO_LOAD"
    for file in "${FILES_ARRAY[@]}"; do
        [ -f "$file" ] || continue
        
        # Try to extract resource type from first line
        first_line=$(head -n1 "$file" 2>/dev/null)
        resource_type=$(echo "$first_line" | grep -o '"resourceType":"[^"]*"' | cut -d'"' -f4)
        
        # Fall back to filename if can't extract from content
        if [ -z "$resource_type" ]; then
            resource_type=$(basename "$file" .ndjson)
        fi
        
        # Skip if we've already counted this type
        if [ -n "${resource_types_seen[$resource_type]}" ]; then
            continue
        fi
        resource_types_seen[$resource_type]=1
        
        if [ -n "$resource_type" ]; then
            # Query the FHIR server for count
            response=$(curl -s "$FHIR_BASE_URL/$resource_type?_summary=count" 2>/dev/null)
            count=$(echo "$response" | grep -o '"total":[0-9]*' | sed 's/"total"://')
            
            # If no count found, try alternate format
            if [ -z "$count" ]; then
                count=$(echo "$response" | grep -o '"total": *[0-9]*' | sed 's/"total": *//')
            fi
            
            [ -z "$count" ] && count="0"
            printf "%-20s %s\n" "$resource_type:" "$count"
        fi
    done
else
    # Count all resource types
    for file in "$DATA_DIR"/*.ndjson; do
        [ -f "$file" ] || continue
        
        resource_type=$(basename "$file" .ndjson)
        
        # Query the FHIR server for count
        response=$(curl -s "$FHIR_BASE_URL/$resource_type?_summary=count" 2>/dev/null)
        count=$(echo "$response" | grep -o '"total":[0-9]*' | sed 's/"total"://')
        
        # If no count found, try alternate format
        if [ -z "$count" ]; then
            count=$(echo "$response" | grep -o '"total": *[0-9]*' | sed 's/"total": *//')
        fi
        
        [ -z "$count" ] && count="0"
        printf "%-20s %s\n" "$resource_type:" "$count"
    done
fi

echo ""
echo "Done. FHIR server ready at: $FHIR_BASE_URL"
