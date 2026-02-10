```mermaid
flowchart TB

%% =========================
%% Azure Subscriptions / Targets
%% =========================
subgraph "Azure Subscription: Non-Prod (Dev)"
  FE_DEV["Frontend App Service (Dev)"]
  BE_DEV["Backend App Service (Dev)"]
  ACR_NP["ACR (Non-Prod)"]
  AKS_DEV["AKS namespace: dev"]
end

subgraph "Azure Subscription: Prod (Staging + Prod)"
  FE_STG["Frontend App Service Slot: Staging"]
  FE_PRD["Frontend App Service Slot: Production"]
  BE_STG["Backend App Service Slot: Staging"]
  BE_PRD["Backend App Service Slot: Production"]

  ACR_P["ACR (Prod)"]
  AKS_STG["AKS namespace: staging"]
  AKS_PRD["AKS namespace: prod"]

  APPROVE["Prod Approval Gate"]
end

%% =========================
%% Frontend Repo (Next.js)
%% =========================
subgraph "Repo: Frontend (Next.js React)"
  FE_FB["feature/*\n(no auto build on push)"]
  FE_TAG["tag: dev/*\n(optional dev deploy trigger)"]
  FE_PR["PR -> main\nCI: Lint + Unit + Integration + Build"]
  FE_MAIN["main"]
  FE_REL["Release: vX.Y.Z"]
end

FE_FB --> FE_PR --> FE_MAIN
FE_FB --> FE_TAG -->|Deploy to Dev (optional)| FE_DEV
FE_MAIN -->|Deploy to Staging (no release)| FE_STG
FE_MAIN --> FE_REL --> APPROVE -->|Deploy to Staging slot| FE_STG
FE_STG -->|Slot swap (approved)| FE_PRD

%% =========================
%% Backend Repo (.NET API)
%% =========================
subgraph "Repo: Backend (.NET API)"
  BE_FB["feature/*\n(no auto build on push)"]
  BE_TAG["tag: dev/*\n(optional dev deploy trigger)"]
  BE_PR["PR -> main\nCI: Lint + Unit + Integration + Migration(Postgres) + Build"]
  BE_MAIN["main"]
  BE_REL["Release: vX.Y.Z"]
end

BE_FB --> BE_PR --> BE_MAIN
BE_FB --> BE_TAG -->|Deploy to Dev (optional)| BE_DEV
BE_MAIN -->|Deploy to Staging slot (no release)| BE_STG
BE_MAIN --> BE_REL --> APPROVE -->|Deploy to Staging slot| BE_STG
BE_STG -->|Slot swap (approved)| BE_PRD

%% =========================
%% AI Repo (Container -> ACR -> AKS Namespaces)
%% =========================
subgraph "Repo: AI (Container)"
  AI_FB["feature/*\n(no auto build on push)"]
  AI_TAG["tag: dev/*\n(optional dev deploy trigger)"]
  AI_PR["PR -> main\nCI: Lint/Static + Tests + Docker Build"]
  AI_MAIN["main"]
  AI_REL["Release: vX.Y.Z"]
end

AI_FB --> AI_PR --> AI_MAIN

AI_FB --> AI_TAG -->|Build & Push| ACR_NP
ACR_NP -->|Deploy| AKS_DEV

AI_MAIN -->|Build & Push| ACR_P
ACR_P -->|Deploy| AKS_STG

AI_MAIN --> AI_REL --> APPROVE -->|Promote tag / Deploy| ACR_P
ACR_P -->|Deploy (approved)| AKS_PRD
```
