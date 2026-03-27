[//]: # (URL: https://docs.shadeform.ai/api-reference/instances/instances-types)

# /instances/types

> Return all the GPU instance types with their corresponding availability and specs.

**Method**: GET
**Endpoint**: `https://api.shadeform.ai/v1/instances/types`

## Query Parameters

| Parameter          | Type    | Description                                          | Example        |
| ------------------ | ------- | ---------------------------------------------------- | -------------- |
| cloud              | string  | Filter the instance type results by cloud.           | aws            |
| region             | string  | Filter the instance type results by region.          | us-east-1a     |
| num_gpus           | string  | Filter by the number of GPUs.                        | 1              |
| gpu_type           | string  | Filter by GPU type.                                  | A100_80G       |
| shade_instance_type| string  | Filter by the shade instance type.                   | A100_80G       |
| available          | boolean | Filter by availability.                              | true           |
| sort               | string  | Sort the results (enum: `price`).                    | price          |

## Response Schema: InstanceTypesResponse

```yaml
InstanceTypesResponse:
  type: object
  required: [instance_types]
  properties:
    instance_types:
      type: array
      items: InstanceType

InstanceType:
  type: object
  required: [cloud, shade_instance_type, cloud_instance_type, configuration, hourly_price, deployment_type, availability]
  properties:
    cloud:
      type: string
      description: Specifies the underlying cloud provider.
    shade_instance_type:
      type: string
      description: The Shadeform standardized instance type.
    cloud_instance_type:
      type: string
      description: The instance type for the underlying cloud provider.
    configuration:
      type: object
      properties:
        memory_in_gb: integer
        storage_in_gb: integer
        vcpus: integer
        num_gpus: integer
        gpu_type: string
        interconnect: string   # e.g. "pcie"
        nvlink: boolean
        vram_per_gpu_in_gb: integer
        os_options: array of strings
        gpu_manufacturer: string
    hourly_price:
      type: integer
      description: The hourly price of the instance in cents.
    deployment_type:
      type: string
      description: "vm", "container", or "baremetal"
    availability:
      type: array
      items:
        region: string
        available: boolean
        display_name: string
    boot_time:
      min_boot_in_sec: integer
      max_boot_in_sec: integer
```

## Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/instances/types?gpu_type=H100&num_gpus=8&available=true&sort=price' \
--header 'X-API-KEY: <api-key>'
```
