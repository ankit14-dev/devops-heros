# Security gate policy

The `security-gate` job in `.github/workflows/final-devops-project.yml` blocks image push and deployment when:

| Check | Tool | Blocks when |
|---|---|---|
| SAST | Bandit (+ CodeQL results in the Security tab) | any HIGH severity finding |
| SCA – Python | pip-audit | any dependency with a known vulnerability |
| SCA – Node | npm audit (production deps) | any HIGH/CRITICAL advisory |
| Secrets | gitleaks | any secret found |
| Container images | Trivy | any **fixable** CRITICAL vulnerability or any secret in an image |

Fixable HIGH image CVEs are reported (summary + annotations) but do not block; unfixable CVEs are ignored
(there is nothing to upgrade to). Exceptions must be added in code review via the tool's own allowlist
(`.gitleaks.toml`, `# nosec` with a justification, `.trivyignore`) - never by disabling the gate.
