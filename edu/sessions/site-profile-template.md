# Site profile — <University name>

Fill during Phase 0 discovery. Commit to the site's fork of this repository
(no secrets, no personal data).

## Contacts

| Role | Name | Email |
| --- | --- | --- |
| Faculty champion | | |
| Research-computing engineer | | |
| Security / compliance reviewer | | |
| Student ambassadors | | |

## Hardware

| Partition / node type | GPU model & memory | GPUs/node | Nodes | NVLink / IB | CPU threads & RAM per node |
| --- | --- | ---: | ---: | --- | --- |
| | | | | | |

- Driver / CUDA version:
- Shared filesystem for model cache (path, free TB, read throughput):
- Node-local scratch (path, size):
- Outbound internet from compute nodes? HF / NGC reachable? Proxy?

## Scheduler & containers

- Scheduler: Slurm version / Kubernetes / none
- Container runtime: Pyxis+Enroot / Apptainer / Docker (rootless?) / Podman
- Preemptible QOS or partition available? Max walltime?
- Can a service job expose a port to campus network? Via which host?

## Idle capacity (from `sreport`/`sacct`, last 8 weeks)

| Partition | GPU-hours available | GPU-hours used | Idle % | Idle pattern (nights/weekends/term breaks) |
| --- | ---: | ---: | ---: | --- |
| | | | | |

## Policies

- Acceptable-use policy link:
- Data classification allowed on this system (public / internal / FERPA / HIPAA / export-controlled):
- May prompts/completions be logged? Retention limit? Consent required?
- Identity provider for SSO (SAML/OIDC):
- Model license restrictions (legal review required?):

## Target users & use cases

- Courses (code, name, enrollment, term):
- Research groups interested in inference / post-training:
- Staff use cases (admin, library, IT helpdesk):

## Decisions

- Model tier and profile (`config/edu-models/…`):
- Serving window (always / nights+weekends / term only):
- Gateway (LiteLLM) and UI (Open WebUI) hosting location:
- Pilot users and start date:
