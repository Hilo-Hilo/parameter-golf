[//]: # (URL: https://docs.shadeform.ai/guides/templates)

# Using Templates

Templates in Shadeform allow you to save and reuse instance configurations, making it easy to launch instances with predefined settings like launch configurations, networking rules, and environment variables. Templates are particularly useful when you need to repeatedly deploy instances with the same configuration or share configurations with team members.

### Prerequisites

1. After you have created your account, you must top up your wallet [here](https://platform.shadeform.ai/settings/billing).
2. After you have topped up your wallet, generate and retrieve your Shadeform API key [here](https://platform.shadeform.ai/settings/api).

### Step 1: Create a Template

Use the [`/templates/save`](https://docs.shadeform.ai/api-reference/templates/templates-save) endpoint.

```bash
# Create a new template
curl --location 'https://api.shadeform.ai/v1/templates/save' \
--header 'x-api-key: <api-key>' \
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
      "envs": [
        {
          "name": "HUGGING_FACE_HUB_TOKEN",
          "value": "hugging_face_api_token"
        }
      ],
      "port_mappings": [
        {
          "container_port": 8000,
          "host_port": 8000
        }
      ]
    }
  },
  "tags": ["vllm", "development"]
}'
```

**Example Response**

```json
{
  "id": "d290f1ee-6c54-4b01-90e6-d701748f0851"
}
```

### Step 2: View Template Details

Use the [`/templates/{template_id}/info`](https://docs.shadeform.ai/api-reference/templates/templates-info) endpoint.

```bash
# Get template details
curl --location 'https://api.shadeform.ai/v1/templates/d290f1ee-6c54-4b01-90e6-d701748f0851/info' \
--header 'x-api-key: <api-key>'
```

**Example Response**

```json
{
  "id": "template-123",
  "name": "vLLM Deployment",
  "description": "Template for vLLM",
  "public": false,
  "launch_configuration": {
    "type": "docker",
    "docker_configuration": {
      "image": "vllm/vllm-openai:latest",
      "args": "--model mistralai/Mistral-7B-v0.1",
      "envs": [
        {
          "name": "HUGGING_FACE_HUB_TOKEN",
          "value": "hugging_face_api_token"
        }
      ],
      "port_mappings": [
        {
          "container_port": 8000,
          "host_port": 8000
        }
      ]
    }
  },
  "tags": ["vllm", "development"]
}
```

### Step 3: Launch an Instance Using a Template

Include the `template_id` in your instance creation request.

```bash
# Create an instance using a template
curl --location 'https://api.shadeform.ai/v1/instances/create' \
--header 'x-api-key: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
  "cloud": "aws",
  "region": "us-east-1",
  "shade_instance_type": "A100_80G",
  "shade_cloud": true,
  "name": "vllm-inference-server",
  "template_id": "d290f1ee-6c54-4b01-90e6-d701748f0851"
}'
```

**Example Response**

```json
{
  "id": "cc9f6b74-9825-4854-9e9c-dd50c7e97c3a",
  "cloud_assigned_id": "720f2a6a-e4ee-488a-ade1-e7892f5d730a"
}
```

### Step 4: Delete a Template

Use the [`/templates/{template_id}/delete`](https://docs.shadeform.ai/api-reference/templates/templates-delete) endpoint.

```bash
# Delete a template
curl --location 'https://api.shadeform.ai/v1/templates/d290f1ee-6c54-4b01-90e6-d701748f0851/delete' \
--header 'x-api-key: <api-key>'
```

### Summary

Templates provide a powerful way to standardize and automate your instance deployments.
For more details about template configurations and available options, check out the [Templates API reference](https://docs.shadeform.ai/api-reference/templates/templates).
