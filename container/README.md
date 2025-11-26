# Building HAPI FHIR with Pre-loaded Data

This approach seeds a HAPI FHIR server with data, then builds an image with that data baked in.

## Step 1: Prepare directories

```bash
# Create folder structure for HAPI FHIR server data and config
# Copy configuration file into container volume
mkdir -p ./container-data/hapi-db && \
mkdir -p ./container-data/hapi-config && \
chmod 777 ./container-data/hapi-db && \
cp ./container/hapi.application.yaml ./container-data/hapi-config/application.yaml
```

## Step 2: Run seed container and load data

```bash
# Run HAPI FHIR server container with mounted volumes
podman run -d --name hapi-seed -p 8080:8080 \
  -v "$(pwd)/container-data/hapi-db:/data:Z" \
  -v "$(pwd)/container-data/hapi-config/application.yaml:/app/config/application.yaml:ro,Z" \
  docker.io/hapiproject/hapi:latest

# Load FHIR test data into the running server (loads all data in dependency order)
./load-fhir-data.sh

# Or load specific files only for testing
# ./load-fhir-data.sh -files=fhir-test-data/Patient.ndjson,fhir-test-data/Practitioner.ndjson,fhir-test-data/Location.ndjson
```

## Step 3: Stop seed container (keep the data)

```bash
# Stop and remove the seed container
podman stop hapi-seed && \
podman rm hapi-seed

# Fix permissions on the database files before building
sudo chown -R $(id -u):$(id -g) ./container-data/hapi-db/ && \
chmod -R 777 ./container-data/hapi-db/

# The database files are now persisted in ./container-data/hapi-db/
ls -hl ./container-data/hapi-db/
```

## Step 4: Build final image with data

```bash
# Build HAPI FHIR image with the persisted data included
podman build -t hapi-hackathon -f container/Containerfile .

# Test the built image
podman run -d --name hapi-test -p 8080:8080 hapi-hackathon

# Basic verification - count resources
echo "=== Basic Resource Counts ==="
curl -s "http://localhost:8080/fhir/Patient?_summary=count" | jq -r '.total'
curl -s "http://localhost:8080/fhir/Practitioner?_summary=count" | jq -r '.total'
curl -s "http://localhost:8080/fhir/Encounter?_summary=count" | jq -r '.total'

# Test resource relationships
echo ""
echo "=== Testing Resource Relationships ==="

# 1. Get a sample patient and their encounters
PATIENT_ID=$(curl -s "http://localhost:8080/fhir/Patient?_count=1" | jq -r '.entry[0].resource.id')
echo "Sample Patient ID: $PATIENT_ID"
echo "Encounters for this patient:"
curl -s "http://localhost:8080/fhir/Encounter?patient=$PATIENT_ID&_count=5" | \
  jq -r '.entry[]? | "  - Encounter \(.resource.id) on \(.resource.period.start)"'

# 2. Get a practitioner and their patients
PRACTITIONER_ID=$(curl -s "http://localhost:8080/fhir/Practitioner?_count=1" | jq -r '.entry[0].resource.id')
echo ""
echo "Sample Practitioner ID: $PRACTITIONER_ID"
echo "Patients treated by this practitioner (via Encounters):"
curl -s "http://localhost:8080/fhir/Encounter?practitioner=$PRACTITIONER_ID&_include=Encounter:patient&_count=5" | \
  jq -r '.entry[]? | select(.resource.resourceType=="Patient") | "  - Patient: \(.resource.name[0].given[0]) \(.resource.name[0].family)"'

# 3. Get observations for a patient
echo ""
echo "Observations for Patient $PATIENT_ID:"
curl -s "http://localhost:8080/fhir/Observation?patient=$PATIENT_ID&_count=5" | \
  jq -r '.entry[]? | "  - \(.resource.code.coding[0].display // .resource.code.text): \(.resource.valueQuantity.value // .resource.valueString // "N/A") \(.resource.valueQuantity.unit // "")"'

# 4. Get conditions (diagnoses) for a patient
echo ""
echo "Conditions for Patient $PATIENT_ID:"
curl -s "http://localhost:8080/fhir/Condition?patient=$PATIENT_ID&_count=5" | \
  jq -r '.entry[]? | "  - \(.resource.code.coding[0].display // .resource.code.text)"'

# 5. Test reverse includes - Get encounters with their locations
echo ""
echo "Encounters with their locations:"
curl -s "http://localhost:8080/fhir/Encounter?_count=3&_include=Encounter:location" | \
  jq -r '.entry[]? | select(.resource.resourceType=="Location") | "  - Location: \(.resource.name)"'

# 6. Get medication requests for a patient
echo ""
echo "Medications for Patient $PATIENT_ID:"
curl -s "http://localhost:8080/fhir/MedicationRequest?patient=$PATIENT_ID&_count=5" | \
  jq -r '.entry[]? | "  - \(.resource.medicationCodeableConcept.coding[0].display // .resource.medicationCodeableConcept.text)"'

# 7. Complex query - Get all resources related to a patient encounter
echo ""
echo "Full encounter details (with related resources):"
ENCOUNTER_ID=$(curl -s "http://localhost:8080/fhir/Encounter?patient=$PATIENT_ID&_count=1" | jq -r '.entry[0].resource.id')
curl -s "http://localhost:8080/fhir/Encounter/$ENCOUNTER_ID/\$everything" | \
  jq -r '.entry[]? | "  - \(.resource.resourceType): \(.resource.id)"' | head -10

# 8. Test chained searches - Patients at a specific organization
ORG_ID=$(curl -s "http://localhost:8080/fhir/Organization?_count=1" | jq -r '.entry[0].resource.id')
echo ""
echo "Organization ID: $ORG_ID"
echo "Patients with encounters at this organization:"
curl -s "http://localhost:8080/fhir/Patient?_has:Encounter:patient:service-provider=$ORG_ID&_count=5" | \
  jq -r '.entry[]? | "  - \(.resource.name[0].given[0]) \(.resource.name[0].family)"'

# Clean up test container
echo ""
echo "Tests complete. Cleaning up..."
podman stop hapi-test
podman rm hapi-test
```

## Step 5: Push to registry

```bash
# Tag for GitHub Container Registry
podman tag hapi-hackathon ${REGISTRY}:latest

# Push to registry
podman push ${REGISTRY}:latest
```

## Notes

- The `container-data/hapi-db` directory contains the H2 database files after seeding
- This directory is copied into the final image at `/data`
- The final image is self-contained with all data pre-loaded