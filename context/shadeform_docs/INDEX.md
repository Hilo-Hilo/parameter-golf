[//]: # (URL: https://docs.shadeform.ai)

# Shadeform Documentation Index

Shadeform is a multi-cloud GPU management platform providing unified access to GPU instances across 15+ cloud providers.

- Official docs: https://docs.shadeform.ai
- API base URL: https://api.shadeform.ai/v1
- Platform UI: https://platform.shadeform.ai
- Full doc index: https://docs.shadeform.ai/llms.txt
- OpenAPI spec: https://docs.shadeform.ai/openapi.yaml

---

## Getting Started

| File | URL | Description |
|------|-----|-------------|
| `getting_started_introduction.md` | https://docs.shadeform.ai/getting-started/introduction | Overview of the Shadeform platform and quick navigation links |
| `getting_started_quickstart.md` | https://docs.shadeform.ai/getting-started/quickstart | Step-by-step guide to finding, launching, SSHing into, and deleting GPU instances |
| `getting_started_concepts.md` | https://docs.shadeform.ai/getting-started/concepts | Core concepts: cloud providers, shade instance types, cloud access, launch configurations |
| `getting_started_faq.md` | https://docs.shadeform.ai/getting-started/faq | Frequently asked questions covering technical and business topics |

---

## Guides

| File | URL | Description |
|------|-----|-------------|
| `guide_tutorial_library.md` | https://docs.shadeform.ai/guides/tutoriallibrary | Index of all available tutorials |
| `guide_attach_volume.md` | https://docs.shadeform.ai/guides/attachvolume | How to create, attach, mount, and delete persistent storage volumes |
| `guide_benchmark.md` | https://docs.shadeform.ai/guides/benchmark | Evaluate language models using lm-eval-harness in a Docker container |
| `guide_docker_containers.md` | https://docs.shadeform.ai/guides/dockercontainers | Launch VM with auto-started Docker container; envs, port mappings, volume mounts, shared memory |
| `guide_firewall.md` | https://docs.shadeform.ai/guides/firewall | Configure UFW firewall rules on GPU instances |
| `guide_jupyter.md` | https://docs.shadeform.ai/guides/jupyter | Run Jupyter Notebook on a GPU instance using Docker launch configuration |
| `guide_most_affordable_gpus.md` | https://docs.shadeform.ai/guides/mostaffordablegpus | Use instance types API with filtering/sorting to find cheapest GPU instances |
| `guide_skypilot.md` | https://docs.shadeform.ai/guides/skypilot | Integrate Shadeform with SkyPilot for multi-cloud GPU job orchestration |
| `guide_ssh_issues.md` | https://docs.shadeform.ai/guides/sshissues | Troubleshoot common SSH problems: key permissions, host ID changes, permission denied |
| `guide_ssh_keys.md` | https://docs.shadeform.ai/guides/sshkeys | Add and manage custom SSH keys; use your own key instead of Shadeform managed key |
| `guide_startup_script.md` | https://docs.shadeform.ai/guides/startupscript | Run a base64-encoded bash script automatically when an instance becomes active |
| `guide_templates.md` | https://docs.shadeform.ai/guides/templates | Create, use, and manage reusable instance configuration templates |
| `guide_vllm.md` | https://docs.shadeform.ai/guides/vllm | Deploy and query an LLM using vLLM on a Shadeform GPU instance |

---

## API Reference

### Authentication
| File | URL | Description |
|------|-----|-------------|
| `api_authentication.md` | https://docs.shadeform.ai/api-reference/authentication | API key authentication, usage, best practices, and troubleshooting |

### Instances
| File | URL | Description |
|------|-----|-------------|
| `api_instances_types.md` | https://docs.shadeform.ai/api-reference/instances/instances-types | GET /instances/types - query GPU instance types with filtering and sorting |
| `api_instances_create.md` | https://docs.shadeform.ai/api-reference/instances/instances-create | POST /instances/create - launch new GPU instances with optional Docker/script configs |
| `api_instances_list_info_delete_restart_update.md` | https://docs.shadeform.ai/api-reference/instances/instances | GET /instances, GET /instances/{id}/info, POST /instances/{id}/delete, POST /instances/{id}/restart, POST /instances/{id}/update |

### Clusters
| File | URL | Description |
|------|-----|-------------|
| `api_clusters.md` | https://docs.shadeform.ai/api-reference/clusters/clusters | GET/POST /clusters, /clusters/create, /clusters/{id}/delete, /clusters/{id}/info, /clusters/types |

### SSH Keys
| File | URL | Description |
|------|-----|-------------|
| `api_sshkeys.md` | https://docs.shadeform.ai/api-reference/sshkeys/sshkeys | GET /sshkeys, POST /sshkeys/add, POST /sshkeys/{id}/delete, GET /sshkeys/{id}/info, POST /sshkeys/{id}/setdefault |

### Templates
| File | URL | Description |
|------|-----|-------------|
| `api_templates.md` | https://docs.shadeform.ai/api-reference/templates/templates | GET /templates, POST /templates/save, GET /templates/featured, GET /templates/{id}/info, POST /templates/{id}/update, POST /templates/{id}/delete |

### Volumes
| File | URL | Description |
|------|-----|-------------|
| `api_volumes.md` | https://docs.shadeform.ai/api-reference/volumes/volumes | GET /volumes, POST /volumes/create, POST /volumes/{id}/delete, GET /volumes/{id}/info, GET /volumes/types |

---

## Key API Concepts

- **Authentication**: All requests require `X-API-KEY: <your-key>` header
- **Base URL**: `https://api.shadeform.ai/v1`
- **Hourly prices**: Returned in **cents** (integer), not dollars
- **Instance status lifecycle**: `creating` -> `pending_provider` -> `pending` -> `active` -> `deleting` -> `deleted`
- **Shade Cloud**: Use `"shade_cloud": true` to use Shadeform's managed cloud accounts without needing your own
- **shade_instance_type**: Standardized GPU type name used across all providers (e.g. `A6000`, `H100x8`, `A100_80G`)
- **Volume constraint**: Volumes must be in the same cloud and region as the instance they attach to
- **SkyPilot integration**: Install `pip install "skypilot[shadeform]"` and place API key at `~/.shadeform/api_key`
