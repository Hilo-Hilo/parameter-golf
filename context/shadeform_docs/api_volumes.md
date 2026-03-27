[//]: # (URL: https://docs.shadeform.ai/api-reference/volumes/volumes)
[//]: # (URL: https://docs.shadeform.ai/api-reference/volumes/volumes-create)
[//]: # (URL: https://docs.shadeform.ai/api-reference/volumes/volumes-delete)
[//]: # (URL: https://docs.shadeform.ai/api-reference/volumes/volumes-info)
[//]: # (URL: https://docs.shadeform.ai/api-reference/volumes/volumes-types)

# Volumes API

---

## GET /volumes

> Get all storage volumes for the account.

**Endpoint**: `https://api.shadeform.ai/v1/volumes`

### Response Schema

```yaml
VolumesResponse:
  volumes:
    - id: string (uuid)
      cloud: string
      cloud_assigned_id: string
      region: string
      name: string
      fixed_size: boolean        # true = fixed size, false = elastic
      size_in_gb: integer
      cost_estimate: string      # cost in dollars
      supports_multi_mount: boolean
      mounted_by: string         # ID of instance currently mounting it
```

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/volumes' \
--header 'X-API-KEY: <api-key>'
```

---

## POST /volumes/create

> Create a new storage volume.

**Endpoint**: `https://api.shadeform.ai/v1/volumes/create`

### Request Schema

```yaml
CreateVolumeRequest:
  required: [cloud, region, size_in_gb, name]
  properties:
    cloud: string
    region: string
    size_in_gb: integer
    name: string
```

### Response

```json
{
  "id": "78a0dd5a-dbb1-4568-b55c-5e7e0a8b0c40"
}
```

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/volumes/create' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
  "cloud": "digitalocean",
  "region": "tor1",
  "size_in_gb": 100,
  "name": "my-storage-volume"
}'
```

---

## POST /volumes/{id}/delete

> Delete a storage volume.

**Endpoint**: `https://api.shadeform.ai/v1/volumes/{id}/delete`

> Note: You must delete the attached instance before deleting a volume.

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/volumes/78a0dd5a-dbb1-4568-b55c-5e7e0a8b0c40/delete' \
--header 'X-API-KEY: <api-key>'
```

---

## GET /volumes/{id}/info

> Get details for the specified storage volume.

**Endpoint**: `https://api.shadeform.ai/v1/volumes/{id}/info`

### Response

Returns a single Volume object (same schema as items in /volumes response).

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/volumes/78a0dd5a-dbb1-4568-b55c-5e7e0a8b0c40/info' \
--header 'X-API-KEY: <api-key>'
```

---

## GET /volumes/types

> Get list of supported storage volumes.

**Endpoint**: `https://api.shadeform.ai/v1/volumes/types`

### Response Schema

```yaml
VolumesTypesResponse:
  volume_types:
    - cloud: string
      region: string
      supports_multi_mount: boolean
      fixed_size: boolean
      price_per_gb_per_hour: string   # e.g. "0.0001"
```

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/volumes/types' \
--header 'X-API-KEY: <api-key>'
```

### Example Response

```json
{
  "volume_types": [
    {
      "cloud": "datacrunch",
      "region": "FIN-01",
      "supports_multiple_mounts": false,
      "fixed_size": true,
      "price_per_gb_per_hour": "0.00028"
    },
    {
      "cloud": "nebius",
      "region": "eu-north1",
      "supports_multiple_mounts": false,
      "fixed_size": true,
      "price_per_gb_per_hour": ".000097"
    },
    {
      "cloud": "digitalocean",
      "region": "tor1",
      "supports_multiple_mounts": false,
      "fixed_size": true,
      "price_per_gb_per_hour": ".000084"
    }
  ]
}
```
