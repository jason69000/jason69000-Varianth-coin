# Project Objective

Build a production-quality non-custodial Bitcoin wallet platform.

Users control their own keys.

The platform never stores seed phrases or private keys.

The platform provides:

- Account registration
- MFA
- Dashboard
- Bitcoin address generation
- Transaction viewing
- QR codes
- Portfolio overview
- Notifications
- Audit logging
- Admin management
- Monitoring
- API documentation

# Technology Stack

Frontend:
- Next.js
- React
- TypeScript
- TailwindCSS

Backend:
- NestJS
- TypeScript

Database:
- PostgreSQL

Caching:
- Redis

Messaging:
- RabbitMQ

Infrastructure:
- Docker
- Kubernetes
- Terraform

Monitoring:
- Prometheus
- Grafana
- Loki

Cloud:
- Azure

Security:
- OAuth2
- OpenID Connect
- JWT
- MFA
- TLS 1.3

# Engineering Standards

- SOLID principles
- Clean Architecture
- CQRS where appropriate
- Repository pattern
- Dependency injection
- Unit tests
- Integration tests
- OpenAPI documentation
- 80%+ code coverage

# Security Requirements

Never:

- Store private keys
- Store seed phrases
- Expose secrets

Always:

- Encrypt sensitive data
- Audit all privileged activity
- Enable MFA
- Log authentication events
- Implement rate limiting

# Deliverables

Generate:

- Full source code
- API routes
- Database migrations
- Kubernetes manifests
- Terraform infrastructure
- Docker files
- CI/CD pipelines
- Monitoring dashboards
- Documentation

# Repository Layout

```text
bitcoin-platform
│
├── apps
│   ├── web
│   ├── api
│   └── admin
│
├── packages
│   ├── ui
│   ├── auth
│   └── shared
│
├── infrastructure
│   ├── terraform
│   ├── kubernetes
│   └── monitoring
│
├── database
│   ├── migrations
│   └── seed
│
├── docs
│
└── .github
    └── workflows
```

# Backend Prompt

Use this Copilot Chat prompt:

```text
Generate a NestJS backend using Clean Architecture.

Requirements:

- User registration
- Login
- MFA
- JWT authentication
- RBAC
- Audit logs
- PostgreSQL
- Redis

Modules:

AuthModule
UsersModule
AuditModule
NotificationModule
AdminModule

Generate:

DTOs
Controllers
Services
Repositories
Entities
Validation
Swagger documentation
Unit tests
```

# PostgreSQL Schema Prompt

```text
Generate PostgreSQL migrations.

Tables:

users
roles
user_roles
audit_logs
sessions
notifications

Include:

UUID primary keys
Foreign keys
Indexes
Soft delete support
Created/Updated timestamps
```

# Authentication Prompt

```text
Build authentication using:

NestJS
Passport
JWT
Refresh Tokens
TOTP MFA

Features:

registration
email verification
password reset
account lockout
MFA enrollment
remember device

Create controller, services,
DTOs, unit tests and Swagger docs.
```

# Frontend Prompt

```text
Build Next.js frontend.

Pages:

Landing
Login
Register
Dashboard
Settings
Notifications
Profile

Use:

Tailwind
TypeScript
React Query
Redux Toolkit

Features:

responsive design
dark mode
accessibility
error boundaries
loading states
```

# Dashboard Prompt

```text
Create dashboard UI.

Widgets:

Account Summary
Recent Activity
Security Status
Notifications

Requirements:

mobile responsive
accessible
dark mode
skeleton loading
charts using recharts
```

# Admin Portal Prompt

```text
Generate admin portal.

Capabilities:

user management
audit log viewing
security event monitoring
notification management

Use role-based authorization.
```

# API Documentation Prompt

```text
Generate OpenAPI 3.0 documentation.

Document:

Authentication endpoints
Users endpoints
Notifications endpoints
Admin endpoints

Include:

examples
schemas
responses
security requirements
```

# Docker Prompt

```text
Generate Dockerfiles.

Services:

web
api
postgres
redis
rabbitmq

Use multi-stage builds.

Optimize image size.

Run as non-root.
```

# Kubernetes Prompt

```text
Generate Kubernetes manifests.

Create:

Deployments
Services
Ingress
Secrets
ConfigMaps
Horizontal Pod Autoscalers

Environment:

production

Use readiness and liveness probes.
```

# Terraform Prompt

```text
Generate Terraform for Azure.

Provision:

resource groups
virtual network
AKS
Azure Database PostgreSQL
Azure Redis Cache
Key Vault
Application Insights
Storage Account

Follow least privilege access.
```

# Monitoring Prompt

```text
Generate observability stack.

Use:

Prometheus
Grafana
Loki

Build dashboards for:

API latency
error rate
authentication events
database health
kubernetes health

Create alert rules.
```

# GitHub Actions Prompt

```text
Generate CI/CD workflow.

Stages:

lint
test
security scan
dependency audit
build
docker build
container scan
deploy
smoke tests

Block deployment on failed tests.
```

# Security Prompt

```text
Perform security hardening.

Implement:

OWASP Top 10 protections
rate limiting
CSP headers
secure cookies
HSTS
CSRF protection
XSS protection
SQL injection protection

Generate automated security tests.
```

# Testing Prompt

```text
Generate test suite.

Testing:

Jest
Supertest
Playwright

Create:

unit tests
integration tests
API tests
E2E tests

Target:

80% plus coverage.
```

# Production Readiness Prompt

```text
Review the entire repository.

Generate:

architecture report
security review
performance review
dependency review
deployment checklist
disaster recovery checklist

Identify all production blockers.
```

Using these prompts sequentially in GitHub Copilot Chat will generate a full enterprise-grade project skeleton, infrastructure-as-code, CI/CD pipelines, testing framework, and deployment assets for a non-custodial Bitcoin wallet/payment platform without enabling operation of a regulated custodial exchange.
