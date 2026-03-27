[//]: # (URL: https://docs.shadeform.ai/api-reference/instances/instances-create)

# /instances/create

> Create a new GPU instance. The create API is asynchronous. Poll /instances/{id}/info to check status.

**Method**: POST
**Endpoint**: `https://api.shadeform.ai/v1/instances/create`

> Note: Only `docker_configuration` or `script_configuration` can be specified but not both.

## Request Schema: CreateRequest

```yaml
CreateRequest:
  required: [cloud, region, shade_instance_type, shade_cloud, name]
  properties:
    cloud: string                    # e.g. "hyperstack", "massedcompute"
    region: string                   # e.g. "canada-1"
    shade_instance_type: string      # e.g. "A6000", "H100x8"
    shade_cloud: boolean             # true = Shade Cloud, false = linked cloud account
    name: string                     # name of the instance
    os: string                       # optional OS selection, e.g. "ubuntu22.04_cuda12.2_shade_os"
    template_id: string              # optional: ID of template to use
    launch_configuration:
      type: string                   # "docker" or "script"
      docker_configuration:
        image: string                # docker image to run
        args: string                 # container arguments
        shared_memory_in_gb: integer # optional shm size (omit for --ipc=host)
        envs:
          - name: string
            value: string
        port_mappings:
          - host_port: integer
            container_port: integer
        volume_mounts:
          - host_path: string
            container_path: string
        registry_credentials:
          username: string
          password: string
      script_configuration:
        base64_script: string        # base64-encoded bash script
    volume_ids: array of strings     # array of 1 volume ID max
    ssh_key_id: string               # optional SSH key ID
    auto_delete:
      date_threshold: string         # RFC3339 date
      spend_threshold: string        # dollar amount string
    alert:
      date_threshold: string
      spend_threshold: string
    volume_mount:
      auto: boolean                  # auto-mount unmounted disks
    tags: array of strings
    envs:
      - name: string
        value: string
```

## Response Schema: CreateResponse

```json
{
  "id": "d290f1ee-6c54-4b01-90e6-d701748f0851"
}
```

## Example Requests

### Basic instance launch

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/create' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
  "cloud": "massedcompute",
  "region": "us-central-2",
  "shade_instance_type": "A6000",
  "shade_cloud": true,
  "name": "my-instance"
}'
```

### Launch with Docker container

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/create' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
  "cloud": "massedcompute",
  "region": "us-central-2",
  "shade_instance_type": "A6000",
  "shade_cloud": true,
  "name": "docker-example",
  "launch_configuration": {
    "type": "docker",
    "docker_configuration": {
      "image": "vllm/vllm-openai:latest",
      "args": "--model HuggingFaceH4/zephyr-7b-beta",
      "envs": [
        {
          "name": "HUGGING_FACE_HUB_TOKEN",
          "value": "hugging_face_api_token"
        }
      ],
      "port_mappings": [
        {
          "host_port": 8000,
          "container_port": 8000
        }
      ]
    }
  }
}'
```

### Launch with startup script

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/create' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
  "cloud": "massedcompute",
  "region": "us-central-2",
  "shade_instance_type": "A6000",
  "shade_cloud": true,
  "name": "script-example",
  "launch_configuration": {
    "type": "script",
    "script_configuration": {
      "base64_script": "<base64-encoded-script>"
    }
  }
}'
```
