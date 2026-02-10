flowchart LR
  %% =========================================================
  %% COMBINED: Frontend + Backend + AI (Namespaces + Dual ACRs)
  %% Environments:
  %%   Dev -> Non-Prod Azure Subscription
  %%   Staging + Prod -> Prod Azure Subscription
  %% Notes:
  %%   - Feature branches do NOT auto-build on push
  %%   - PR to main runs required CI checks
  %%   - Feature -> Dev deploy is OPTIONAL via dev/* tag
  %%   - Staging deploy follows "prod-like" process without a Release
  %%   - Prod deploy is Release-driven and ALWAYS approval-gated
  %% =========================================================

  %% -------------------------
  %% Git refs (shared pattern)
  %% -------------------------
  subgraph GIT[Git refs / triggers]
    FB_FE[Frontend: feature/*<br/>no auto build on push]
    FB_BE[Backend: feature/*<br/>no auto build on push]
    FB_AI[AI: feature/*<br/>no auto build on push]

    TAG_FE[Frontend tag: dev/* (optional)]
    TAG_BE[Backend tag: dev/* (optional)]
    TAG_AI[AI tag: dev/* (optional)]

    PR_FE[Frontend PR -> main]
    PR_BE[Backend PR -> main]
    PR_AI[AI PR -> main]

    MAIN_FE[Frontend main]
    MAIN_BE[Backend main]
    MAIN_AI[AI main]

    REL_FE[Frontend Release: vX.Y.Z]
    REL_BE[Backend Release: vX.Y.Z]
    REL_AI[AI Release: vX.Y.Z]
  end

  %% -------------------------
  %% CI checks (PR-required)
  %% -------------------------
  subgraph CI[PR Validation (required checks)]
    subgraph CI_FE[Frontend CI]
      FE_LINT[Lint]
      FE_UT[Unit Tests]
      FE_IT[Integration Tests]
      FE_BV[Build Validation (Next.js build)]
    end

    subgraph CI_BE[Backend CI]
      BE_LINT[Lint (.NET format/analyzers)]
      BE_UT[Unit Tests]
      BE_IT[Integration Tests]
      BE_MIG[Migration Testing (Postgres)]
      BE_BV[Build Validation (dotnet build/publish)]
    end

    subgraph CI_AI[AI CI]
      AI_LINT[Lint/Static checks]
      AI_UT[Unit/Component Tests]
      AI_BV[Build Validation (docker build)]
    end
  end

  %% -------------------------
  %% Azure: Non-Prod Subscription (Dev)
  %% -------------------------
  subgraph NONPROD[Azure Subscription: Non-Prod (Dev)]
    FE_DEV_APP[Frontend Dev App Service]
    BE_DEV_API[Backend Dev App Service]
    DEV_DB[(Dev Postgres)]

    ACR_NP[ACR (Non-Prod)]
    AKS_NP[AKS (Non-Prod)]
    NS_DEV[Namespace: dev]
    AKS_NP --> NS_DEV
  end

  %% -------------------------
  %% Azure: Prod Subscription (Staging + Prod)
  %% -------------------------
  subgraph PROD[Azure Subscription: Prod (Staging + Prod)]
    %% App Services with slots
    FE_STG_SLOT[Frontend Staging Slot]
    FE_PROD_SLOT[Frontend Production Slot]

    BE_STG_SLOT[Backend Staging Slot]
    BE_PROD_SLOT[Backend Production Slot]

    STG_DB[(Staging DB scope in Prod sub)]
    PROD_DB[(Prod DB)]

    %% ACR + AKS namespaces
    ACR_P[ACR (Prod)]
    AKS_P[AKS (Prod)]
    NS_STG[Namespace: staging]
    NS_PROD[Namespace: prod]
    AKS_P --> NS_STG
    AKS_P --> NS_PROD

    %% Approval gate for Prod deployments
    APPROVAL[Prod Approval Gate]
  end

  %% =========================
  %% FRONTEND FLOW
  %% =========================
  FB_FE --> PR_FE --> FE_LINT --> FE_UT --> FE_IT --> FE_BV --> MAIN_FE

  %% Optional Feature -> Dev via tag
  FB_FE --> TAG_FE -->|Deploy to Dev (optional)| FE_DEV_APP

  %% Main -> Staging (no Release)
  MAIN_FE -->|Deploy to Staging (main)| FE_STG_SLOT

  %% Release -> Prod (approval) + Slot Swap
  MAIN_FE --> REL_FE --> APPROVAL -->|Deploy to Staging slot| FE_STG_SLOT
  FE_STG_SLOT -->|Slot Swap (approved)| FE_PROD_SLOT


  %% =========================
  %% BACKEND FLOW
  %% =========================
  FB_BE --> PR_BE --> BE_LINT --> BE_UT --> BE_IT --> BE_MIG --> BE_BV --> MAIN_BE

  %% Optional Feature -> Dev via tag
  FB_BE --> TAG_BE -->|Deploy to Dev (optional)| BE_DEV_API
  BE_DEV_API -->|Migrations (dev)| DEV_DB

  %% Main -> Staging (no Release)
  MAIN_BE -->|Deploy to Staging slot (main)| BE_STG_SLOT
  BE_STG_SLOT -->|Migrations (staging)| STG_DB

  %% Release -> Prod (approval) + Migrations + Slot Swap
  MAIN_BE --> REL_BE --> APPROVAL -->|Deploy to Staging slot| BE_STG_SLOT
  BE_STG_SLOT -->|Migrations (prod - gated step)| PROD_DB
  BE_STG_SLOT -->|Slot Swap (approved)| BE_PROD_SLOT


  %% =========================
  %% AI / CONTAINER + AKS FLOW
  %% =========================
  FB_AI --> PR_AI --> AI_LINT --> AI_UT --> AI_BV --> MAIN_AI

  %% Optional Feature -> Dev via tag (build & push to Non-Prod ACR; deploy to AKS Non-Prod dev namespace)
  FB_AI --> TAG_AI -->|Build & Push Image| ACR_NP
  ACR_NP -->|Deploy to AKS dev ns| NS_DEV

  %% Main -> Staging (build & push to Prod ACR; deploy to AKS Prod staging namespace)
  MAIN_AI -->|Build & Push Image (main)| ACR_P
  ACR_P -->|Deploy to AKS staging ns| NS_STG

  %% Release -> Prod (approval; promote/retag in Prod ACR; deploy to AKS Prod prod namespace)
  MAIN_AI --> REL_AI --> APPROVAL -->|Promote Tag / Deploy| ACR_P
  ACR_P -->|Deploy to AKS prod ns (approved)| NS_PROD