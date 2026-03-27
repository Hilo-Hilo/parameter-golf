[//]: # (URL: https://docs.shadeform.ai/api-reference/instances/instances)
[//]: # (URL: https://docs.shadeform.ai/api-reference/instances/instances-info)
[//]: # (URL: https://docs.shadeform.ai/api-reference/instances/instances-delete)
[//]: # (URL: https://docs.shadeform.ai/api-reference/instances/instances-restart)
[//]: # (URL: https://docs.shadeform.ai/api-reference/instances/instances-update)

# Instances API - List, Info, Delete, Restart, Update

---

## GET /instances

> Get all non deleted instances. Note: instances in the "deleting" status will also show up here.

**Endpoint**: `https://api.shadeform.ai/v1/instances`

### Response Schema: InstancesResponse

The response contains an array of Instance objects. Each Instance has:

```yaml
Instance:
  required: [id, cloud, region, shade_instance_type, cloud_instance_type,
             cloud_assigned_id, shade_cloud, name, configuration, ip,
             ssh_user, ssh_port, status, cost_estimate, created_at, deleted_at]
  properties:
    id: string (uuid)
    cloud: string
    region: string
    shade_instance_type: string
    cloud_instance_type: string
    cloud_assigned_id: string
    shade_cloud: boolean
    name: string
    configuration:
      memory_in_gb: integer
      storage_in_gb: integer
      vcpus: integer
      num_gpus: integer
      gpu_type: string
      interconnect: string
      nvlink: boolean
      vram_per_gpu_in_gb: integer
      gpu_manufacturer: string
      os: string
    ip: string              # public IP or DNS
    ssh_user: string        # typically "shadeform"
    ssh_port: integer       # typically 22
    status:
      enum: [creating, pending_provider, pending, active, error, deleting, deleted]
    status_details: string
    cost_estimate: string   # cost in dollars (via Shadeform)
    hourly_price: integer   # price in cents
    launch_configuration: object
    tags: array of strings
    port_mappings: array
    active_at: datetime
    created_at: datetime
    deleted_at: datetime
    boot_time:
      min_boot_in_sec: integer
      max_boot_in_sec: integer
```

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/instances' \
--header 'X-API-KEY: <api-key>'
```

---

## GET /instances/{id}/info

> Get details for the specified, non deleted, instance in the url.

**Endpoint**: `https://api.shadeform.ai/v1/instances/{id}/info`

Same response schema as a single Instance object from /instances, with additional fields:
- `volume_ids`: array of volume IDs attached
- `ssh_key_id`: ID of the SSH key used
- `auto_delete`: date/spend thresholds for auto-deletion
- `alert`: date/spend thresholds for alerts
- `volume_mount`: settings for auto-mounting volumes
- `envs`: environment variables on the instance

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/instances/d290f1ee-6c54-4b01-90e6-d701748f0851/info' \
--header 'X-API-KEY: <api-key>'
```

---

## POST /instances/{id}/delete

> This will move the instance to the 'deleting' status while the instance is being deleted. Once the instance has entered the 'deleting' status, the account will no longer be billed for the instance.

**Endpoint**: `https://api.shadeform.ai/v1/instances/{id}/delete`

### Response

Returns 200 to confirm the deletion request was initiated.

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/d290f1ee-6c54-4b01-90e6-d701748f0851/delete' \
--header 'X-API-KEY: <api-key>'
```

---

## POST /instances/{id}/restart

> Restart an instance. The status of the instance will stay as 'active' throughout, but you may have to wait a few minutes for the instance to be ready to use again.

**Endpoint**: `https://api.shadeform.ai/v1/instances/{id}/restart`

### Response

Returns 200 to confirm the restart request was initiated. This does not confirm the instance restarted successfully.

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/d290f1ee-6c54-4b01-90e6-d701748f0851/restart' \
--header 'X-API-KEY: <api-key>'
```

---

## POST /instances/{id}/update

> Update mutable details about the instance. Set a value to null to delete it. Omit a value or leave undefined to keep unchanged.

**Endpoint**: `https://api.shadeform.ai/v1/instances/{id}/update`

### Request Schema: UpdateRequest

```yaml
UpdateRequest:
  properties:
    name: string
    auto_delete:
      date_threshold: string   # RFC3339 date
      spend_threshold: string  # dollar amount string
    alert:
      date_threshold: string
      spend_threshold: string
    tags: array of strings
```

### Response

Returns 200 to confirm the update.

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/instances/d290f1ee-6c54-4b01-90e6-d701748f0851/update' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
  "name": "new-instance-name",
  "tags": ["production", "gpu"]
}'
```
