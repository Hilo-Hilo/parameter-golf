[//]: # (URL: https://docs.shadeform.ai/api-reference/templates/templates)
[//]: # (URL: https://docs.shadeform.ai/api-reference/templates/templates-save)
[//]: # (URL: https://docs.shadeform.ai/api-reference/templates/templates-featured)
[//]: # (URL: https://docs.shadeform.ai/api-reference/templates/templates-info)
[//]: # (URL: https://docs.shadeform.ai/api-reference/templates/templates-update)
[//]: # (URL: https://docs.shadeform.ai/api-reference/templates/templates-delete)

# Templates API

Templates allow you to save and reuse instance configurations.

---

## GET /templates

> List all templates created by the user.

**Endpoint**: `https://api.shadeform.ai/v1/templates`

### Response Schema

```yaml
TemplatesResponse:
  templates:
    - id: string (uuid)
      name: string
      description: string
      author: string
      logo: string (url)
      public: boolean
      launch_configuration: object
      tags: array of strings
```

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/templates' \
--header 'X-API-KEY: <api-key>'
```

---

## POST /templates/save

> Create a new template.

**Endpoint**: `https://api.shadeform.ai/v1/templates/save`

### Request Schema

```yaml
SaveTemplateRequest:
  required: [name, launch_configuration]
  properties:
    name: string
    description: string
    public: boolean
    launch_configuration:
      type: string                # "docker" or "script"
      docker_configuration:
        image: string
        args: string
        envs: [{name, value}]
        port_mappings: [{container_port, host_port}]
        volume_mounts: [{host_path, container_path}]
      script_configuration:
        base64_script: string
    tags: array of strings
```

### Response

```json
{
  "id": "d290f1ee-6c54-4b01-90e6-d701748f0851"
}
```

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/templates/save' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
  "name": "vLLM Deployment",
  "description": "Template for vLLM",
  "public": false,
  "launch_configuration": {
    "type": "docker",
    "docker_configuration": {
      "image": "vllm/vllm-openai:latest",
      "args": "--model mistralai/Mistral-7B-v0.1",
      "port_mappings": [{"container_port": 8000, "host_port": 8000}]
    }
  },
  "tags": ["vllm", "development"]
}'
```

---

## GET /templates/featured

> List featured templates.

**Endpoint**: `https://api.shadeform.ai/v1/templates/featured`

Returns same schema as /templates.

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/templates/featured' \
--header 'X-API-KEY: <api-key>'
```

---

## GET /templates/{template_id}/info

> Get information about a specific template.

**Endpoint**: `https://api.shadeform.ai/v1/templates/{template_id}/info`

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/templates/d290f1ee-6c54-4b01-90e6-d701748f0851/info' \
--header 'X-API-KEY: <api-key>'
```

---

## POST /templates/{template_id}/update

> Update an existing template.

**Endpoint**: `https://api.shadeform.ai/v1/templates/{template_id}/update`

### Request Schema

Same fields as /templates/save, all optional.

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/templates/d290f1ee-6c54-4b01-90e6-d701748f0851/update' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
  "name": "Updated vLLM Deployment"
}'
```

---

## POST /templates/{template_id}/delete

> Delete a template.

**Endpoint**: `https://api.shadeform.ai/v1/templates/{template_id}/delete`

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/templates/d290f1ee-6c54-4b01-90e6-d701748f0851/delete' \
--header 'X-API-KEY: <api-key>'
```
