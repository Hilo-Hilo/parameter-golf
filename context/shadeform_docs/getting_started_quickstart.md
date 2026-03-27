[//]: # (URL: https://docs.shadeform.ai/getting-started/quickstart)

# Quickstart

In this guide, we will cover the basic operations for GPU instances on Shadeform via the API. Alternatively, you can perform all of the same operations via the [UI](https://platform.shadeform.ai).

### Prequisites

There are two pre-requisites for this guide:

1. After you have created your account, you must top up your wallet [here](https://platform.shadeform.ai/settings/billing).
2. After you have topped up your wallet, generate and retrieve your Shadeform API key [here](https://platform.shadeform.ai/settings/api).

### Finding a GPU instance

Use the [/instances/types](/api-reference/instances/instances-types) API to query for your desired instance. For this guide, we will query for the cheapest available A6000 instance. Make sure to replace `<api-key>` with your own API Key retrieved from [here](https://platform.shadeform.ai/settings/api).

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/instances/types?gpu_type=A6000&num_gpus=1&available=true&sort=price' \
--header 'X-API-KEY: <api-key>'
```

You should get a response like the JSON snippet below. The response will have an array of the instances that match the search criteria sorted by price. We only need to look at the first entry in the array. Don't worry! We don't need all of that data to launch an instance. We only care about the `cloud`, `region`, and `shade_instance_type` fields.

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
      "nvlink": false,
      "os_options": [
        "ubuntu22.04_cuda12.6_shade_os"
      ],
      "vram_per_gpu_in_gb": 48,
      "gpu_manufacturer": "nvidia"
    },
    "memory_in_gb": 48,
    "storage_in_gb": 256,
    "vcpus": 6,
    "num_gpus": 1,
    "gpu_type": "A6000",
    "interconnect": "pcie",
    "nvlink": false,
    "hourly_price": 57,
    "availability": [
      {
        "region": "kansascity-usa-1",
        "available": true,
        "display_name": "US, Kansas City, KS"
      }
    ],
    "boot_time": {
      "min_boot_in_sec": 300,
      "max_boot_in_sec": 600
    },
    "deployment_type": "vm"
  }
  ]
}
```

### Launching the instance

After we have found the cheapest A6000 that's available, we will launch the GPU instance using the [/instances/create](/api-reference/instances/instances-create) API. Using the values from the previous JSON snippet, we can fill in request payload fields for `cloud`, `region`, and `shade_instance_type`.

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/create' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
  "cloud": "massedcompute",
  "region": "kansascity-usa-1",
  "shade_instance_type": "A6000",
  "name": "quickstart"
}'
```

> If you encounter an error that implies that the selected instance is out of capacity, please try the next instance returned in the response. Sometimes GPU availability can change rapidly!

The response from the API will look like the JSON snippet below. We will need the `id` property for further requests.

```json
{
  "id": "1dc915dd-8899-4b4f-862a-f63fb2b3dc3d"
}
```

### Checking the status of the instance

Now that we have created the GPU instance, we must wait for the instance to spin up. We can check on the status of the instance by calling the [/instances/info](/api-reference/instances/instances-info) API. We will need to use the `id` from the response of the previous step as a URL parameter.

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/instances/<id>/info' \
--header 'X-API-KEY: <api-key>'
```

The response from the API look like the JSON snippet below. We can look at the `status` field to see if the instance is ready. Right now the instance is `pending`.

```json
{
  "id": "1dc915dd-8899-4b4f-862a-f63fb2b3dc3d",
  "cloud": "massedcompute",
  "region": "kansascity-usa-1",
  "shade_instance_type": "A6000",
  "cloud_instance_type": "gpu_1x_a6000",
  "cloud_assigned_id": "2865d9f3-86fa-4d9b-ac0b-a0fb2fa19a3a",
  "shade_cloud": true,
  "name": "quickstart",
  "status": "pending_provider",
  "status_details": "Instance created, waiting on provider to spin up instance",
  "ip": null,
  "ssh_user": "shadeform",
  "ssh_port": null,
  "hourly_price": 57,
  "active_at": null,
  "created_at": "2026-01-28T20:53:39.459529Z",
  "deleted_at": null
}
```

You can query this API on a loop until `status` changes from `pending` to `active`. This will typically take 4-5 minutes for A6000 instances. When the status turns to `active`, the `ip` field will also become populated.

```json
{
  "id": "1dc915dd-8899-4b4f-862a-f63fb2b3dc3d",
  "status": "active",
  "ip": "123.123.123.123",
  "ssh_user": "shadeform",
  "ssh_port": null,
  "hourly_price": 57,
  "active_at": "2026-01-28T20:53:39.459529Z"
}
```

### SSHing into the instance

Once the instance's status is `active`, we can now SSH into the GPU instance. Unless you have specified a different SSH key in the create request or updated your default SSH key, your default SSH key will be the one labeled as 'Shadeform Managed Key'. Download your Shadeform [generated private key](https://platform.shadeform.ai/settings/ssh-keys).

```bash
chmod 600 ~/Downloads/private_key.pem
ssh -i ~/Downloads/private_key.pem shadeform@<ip>
```

> If you encounter an error that starts with `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`, you can run `ssh-keygen -R <ip>` to reset your saved host info.

### Restarting the instance

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/<id>/restart' \
--header 'X-API-KEY: <api-key>'
```

### Deleting the instance

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/<id>/delete' \
--header 'X-API-KEY: <api-key>'
```
