# Diagrams to Copy from Documentation Repository

Copy these diagrams from the documentation repository to this directory:

1. **participant-lookup-flow.svg**
   - Generate from: `/documentation/docs/technical/technical/account-lookup-service/assets/diagrams/sequence/seq-acct-lookup-get-parties-7.2.0.plantuml`
   - Description: Party lookup sequence showing discovery phase

2. **quote-phase-sequence.svg**
   - Generate from: `/documentation/docs/technical/technical/quoting-service/assets/diagrams/sequence/seq-quotes-1.0.0.plantuml`
   - Description: Quote calculation and agreement flow

3. **transfer-fulfillment-flow.svg**
   - Generate from: `/documentation/docs/technical/technical/central-ledger/assets/diagrams/sequence/seq-fulfil-2.1.0.plantuml`
   - Description: Transfer fulfillment sequence

## Note:
These PlantUML files need to be rendered to SVG format. You can use:
- PlantUML online server: http://www.plantuml.com/plantuml
- VS Code PlantUML extension
- Command line: `plantuml -tsvg <filename>.plantuml`