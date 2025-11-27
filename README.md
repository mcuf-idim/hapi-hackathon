# 🌲 HAPI FHIR Server for Black Forest Hackathon 2025

Welcome to the **[Black Forest Hackathon](https://www.blackforesthackathon.de/sxh25/)** in **November 2025**! 🚀

This repository provides a pre-configured HAPI FHIR server with synthetic patient data for your hackathon challenges, brought to you by the [Medical Center – University of Freiburg](https://www.uniklinik-freiburg.de/de.html).

Let's build the future of smart healthcare together! 🏥💻

## Quick Start

### Using Docker

```bash
docker pull ghcr.io/mcuf-idim/hapi-hackathon:latest && \
docker run -d -p 8080:8080 --name hapi-fhir ghcr.io/mcuf-idim/hapi-hackathon:latest
```

### Using Podman

```bash
podman pull ghcr.io/mcuf-idim/hapi-hackathon:latest && \
podman run -d -p 8080:8080 --name hapi-fhir ghcr.io/mcuf-idim/hapi-hackathon:latest
```

The FHIR server will be available at: **http://localhost:8080/fhir**

## Verify It's Running

```bash
# Check server status
curl http://localhost:8080/fhir/metadata

# Get patient count
curl http://localhost:8080/fhir/Patient?_summary=count
```

## Container Management

```bash
# Stop the container
docker stop hapi-fhir

# Start it again
docker start hapi-fhir

# View logs
docker logs hapi-fhir

# Remove container
docker rm -f hapi-fhir

# Remove image
docker rmi ghcr.io/mcuf-idim/hapi-hackathon:latest
```

## FHIR Server Test Queries

Run comprehensive test queries to explore the interconnected healthcare data:

```bash
# Clone this repository to get the test scripts
git clone https://github.com/mcuf-idim/hapi-hackathon.git
cd hapi-hackathon

# Run test queries against the running server
./tests/test-queries.sh
```

The test script demonstrates complex FHIR queries including:
- Location-based encounter searches with date ranges
- Practitioner workload analysis
- Patient conditions with related resources
- Procedures and immunization records

See [tests/test-queries.sh](tests/test-queries.sh) for the full test suite and [tests/expected-results.txt](tests/expected-results.txt) for sample output showing what results you should expect.

## Building Your Own Image

See [container/README.md](container/README.md) for instructions on building the container image yourself.

## FHIR Test Data

The synthetic FHIR resources used in this server are available for download:

```bash
# Download the complete dataset
curl -L -o fhir-data.tar.gz https://raw.githubusercontent.com/mcuf-idim/fhir-benchmark-data/main/data.tar.gz

# Extract the data
tar -xzf fhir-data.tar.gz
```

This dataset includes:
- 121 Patients
- 288 Practitioners  
- 289 Locations
- Thousands of Encounters, Observations, Conditions, and other clinical resources

---

**Happy Hacking!** 🌲🚀

*Black Forest Hackathon 2024 - Medical Center, University of Freiburg*