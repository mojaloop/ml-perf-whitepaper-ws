#!/bin/bash

# Script to copy diagrams from documentation repository to ml-perf-whitepaper-ws
# Run this from the ml-perf-whitepaper-ws directory

DOCS_REPO="/Users/jc/ml/documentation"

echo "Copying diagrams from documentation repository..."

# Phase 04 - Mojaloop diagrams
echo "→ Phase 04 diagrams..."
cp "$DOCS_REPO/docs/technical/technical/overview/assets/diagrams/architecture/Arch-Mojaloop-overview-PI18.svg" \
   "phases/04-mojaloop/diagrams/mojaloop-switch-architecture.svg"

cp "$DOCS_REPO/docs/technical/technical/sdk-scheme-adapter/assets/SDKSchemeAdapterMode2.svg" \
   "phases/04-mojaloop/diagrams/sdk-scheme-adapter-architecture.svg"

cp "$DOCS_REPO/docs/technical/reference-architecture/boundedContexts/security/assets/ML2RA_SecAuth-ucAuthModel_Apr22_1829.png" \
   "phases/04-mojaloop/diagrams/security-architecture-overview.png"

# Phase 06 - First test diagrams (these need to be generated from PlantUML)
echo "→ Phase 06 diagrams (PlantUML files - need rendering)..."
echo "  - participant-lookup-flow.svg (from seq-acct-lookup-get-parties-7.2.0.plantuml)"
echo "  - quote-phase-sequence.svg (from seq-quotes-1.0.0.plantuml)"
echo "  - transfer-fulfillment-flow.svg (from seq-fulfil-2.1.0.plantuml)"

# Phase 07 - Performance test diagrams
echo "→ Phase 07 diagrams..."
cp "$DOCS_REPO/docs/technical/api/assets/diagrams/sequence/figure1.svg" \
   "phases/07-performance-tests/diagrams/p2p-transfer-complete-flow.svg"

# Note about custom diagrams to create
echo ""
echo "Custom diagrams to create:"
echo "  - phases/05-k6-infrastructure/diagrams/k6-testing-architecture.svg"
echo "  - phases/07-performance-tests/diagrams/8-dfsp-test-architecture.svg"
echo "  - phases/04-mojaloop/diagrams/sdk-security-flow.svg"
echo ""
echo "PlantUML files to render:"
echo "  - $DOCS_REPO/docs/technical/technical/account-lookup-service/assets/diagrams/sequence/seq-acct-lookup-get-parties-7.2.0.plantuml"
echo "  - $DOCS_REPO/docs/technical/technical/quoting-service/assets/diagrams/sequence/seq-quotes-1.0.0.plantuml"
echo "  - $DOCS_REPO/docs/technical/technical/central-ledger/assets/diagrams/sequence/seq-fulfil-2.1.0.plantuml"
echo "  - $DOCS_REPO/docs/technical/technical/central-event-processor/assets/diagrams/sequence/seq-signature-validation.plantuml"

echo ""
echo "Done! Check the DIAGRAMS-TO-COPY.md files in each phase directory for PlantUML sources."