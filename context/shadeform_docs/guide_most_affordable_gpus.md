[//]: # (URL: https://docs.shadeform.ai/guides/mostaffordablegpus)

# Find and Deploy the Most Affordable GPU

### Intro

Prices for VM instances with the same GPU can vary widely between cloud providers.
Some of the variance is due to other hardware specs such as memory, storage, vCPU count, network speed, region, and more.
However, a lot of the variance is also due to non-technical factors such as cloud provider brand, marketing, and pricing strategy.

Often times, the GPU configuration in an instance is far more important than any other details.
In such cases, we provide an API that can help search for the most affordable GPU instance given the GPU type.

### Using the Instance Types API

We can find the most affordable GPU instances by applying filtering and sorting query params to the [Instance Types API](/api-reference/instances/instances-types).
Without any query parameters, the API returns all of the instance types supported by Shadeform in a random order.
By using the following query parameters, we can filter down the results and sort them as needed.

| Query Parameter | Description                              | Example Value |
| --------------- | ---------------------------------------- | ------------- |
| cloud           | Filter by cloud name                     | massedcompute |
| region          | Filter by region                         | us-central-3  |
| num_gpus        | Filter by number of GPUs in the instance | 1             |
| gpu_type        | Filter by GPU type                       | A100_80G      |
| available       | Filter by availability                   | true          |
| sort            | Sort by a parameter                      | price         |

### Find the Most Affordable A100_80G Instance Available

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/types?gpu_type=A100_80G&available=true&sort=price' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json'
```

From array of results returned, we can see that the A100_80G instance from RunPod is the most affordable instance available right now at `$2.03/hr`.

```json
{
  "instance_types": [
    {
      "cloud": "runpod",
      "shade_instance_type": "A100_80G",
      "cloud_instance_type": "NVIDIA A100 80GB PCIe",
      "configuration": {
        "memory_in_gb": 125,
        "storage_in_gb": 250,
        "vcpus": 8,
        "num_gpus": 1,
        "gpu_type": "A100_80G",
        "interconnect": "pcie",
        "os_options": [
          "ubuntu22.04_cuda12.2_shade_os"
        ],
        "vram_per_gpu_in_gb": 80
      },
      "hourly_price": 203,
      "availability": [
        {
          "region": "any",
          "available": true
        }
      ]
    }
  ]
}
```

### Find the Most Affordable 8xH100 Instance Available

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/types?gpu_type=H100&num_gpus=8&available=true&sort=price' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json'
```

From array of results returned, we can see that the 8xH100 instance from Oblivus is the most affordable instance available right now at `$32.80/hr`.

```json
{
  "instance_types": [
    {
      "cloud": "oblivus",
      "shade_instance_type": "H100x8",
      "cloud_instance_type": "H100_PCIE_80GB_x8",
      "configuration": {
        "memory_in_gb": 1440,
        "storage_in_gb": 6600,
        "vcpus": 252,
        "num_gpus": 8,
        "gpu_type": "H100",
        "interconnect": "pcie",
        "vram_per_gpu_in_gb": 80
      },
      "hourly_price": 3280,
      "availability": [
        {
          "region": "MON1",
          "available": true,
          "display_name": "CA, Montreal"
        }
      ]
    }
  ]
}
```

### Find the Most Affordable 8xH100 Instance Regardless of Availability

To find the most affordable 8xH100 instance regardless of availability, remove the `available=true` parameter.

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/types?gpu_type=H100&num_gpus=8&sort=price' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json'
```

After removing the `available=true` parameter, the top result is Massed Compute's 8xH100 instance at `$23.92/hr`. However, it is not available at the time of this API call.

```json
{
  "instance_types": [
    {
      "cloud": "massedcompute",
      "shade_instance_type": "H100x8",
      "cloud_instance_type": "gpu_8x_h100",
      "configuration": {
        "memory_in_gb": 512,
        "storage_in_gb": 5000,
        "vcpus": 128,
        "num_gpus": 8,
        "gpu_type": "H100",
        "interconnect": "pcie",
        "vram_per_gpu_in_gb": 80
      },
      "hourly_price": 2392,
      "availability": [
        {
          "region": "us-central-2",
          "available": false,
          "display_name": "US, Kansas City, KS"
        }
      ]
    }
  ]
}
```

### Find the most Affordable A6000 Instance Available

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/types?gpu_type=A6000&available=true&sort=price' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json'
```

From array of results returned, we can see that the A6000 instance from Massed Compute is the most affordable instance available at `$0.57/hr`.

```json
{
  "instance_types": [
    {
      "cloud": "massedcompute",
      "shade_instance_type": "A6000",
      "cloud_instance_type": "gpu_1x_a6000",
      "configuration": {
        "memory_in_gb": 48,
        "storage_in_gb": 256,
        "vcpus": 6,
        "num_gpus": 1,
        "gpu_type": "A6000",
        "interconnect": "pcie",
        "vram_per_gpu_in_gb": 48
      },
      "hourly_price": 57,
      "availability": [
        {
          "region": "us-central-2",
          "available": true,
          "display_name": "US, Kansas City, KS"
        }
      ]
    }
  ]
}
```

### Launching the Instance

After you have found the most affordable instance, you can launch the instance by using the [Create Instance API](/api-reference/instances/instances-create).

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
  "name": "most_affordable"
}'
```
