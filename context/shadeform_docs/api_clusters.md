[//]: # (URL: https://docs.shadeform.ai/api-reference/clusters/clusters)
[//]: # (URL: https://docs.shadeform.ai/api-reference/clusters/clusters-create)
[//]: # (URL: https://docs.shadeform.ai/api-reference/clusters/clusters-delete)
[//]: # (URL: https://docs.shadeform.ai/api-reference/clusters/clusters-info)
[//]: # (URL: https://docs.shadeform.ai/api-reference/clusters/clusters-types)

# Clusters API

Clusters are multi-node GPU configurations. The Clusters API allows you to provision, manage, and query GPU clusters.

---

## GET /clusters

> Get all non deleted clusters.

**Endpoint**: `https://api.shadeform.ai/v1/clusters`

### Response Schema

```yaml
ClustersResponse:
  clusters:
    - id: string (uuid)
      cloud: string                  # e.g. "denvr"
      name: string
      cloud_cluster_id: string       # cloud provider assigned cluster ID
      region_info:
        region: string               # e.g. "houston-usa-1"
        display_name: string         # e.g. "US, Houston, TX"
      status: string                 # e.g. "active"
      status_details: string
      created_at: datetime
      updated_at: datetime
      instances: array               # array of Instance objects in the cluster
      hourly_price: integer          # price in cents
      cost_estimate: string          # e.g. "$15.00"
      active_at: datetime
```

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/clusters' \
--header 'X-API-KEY: <api-key>'
```

---

## POST /clusters/create

> Create a new GPU cluster.

**Endpoint**: `https://api.shadeform.ai/v1/clusters/create`

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/clusters/create' \
--header 'X-API-KEY: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
  "cloud": "denvr",
  "region": "houston-usa-1",
  "shade_instance_type": "H100x8",
  "name": "my-cluster"
}'
```

---

## POST /clusters/{id}/delete

> This will move the cluster to the 'deleting' status while the cluster is being deleted. Once the cluster has entered the 'deleting' status, the account will no longer be billed for the cluster.

**Endpoint**: `https://api.shadeform.ai/v1/clusters/{id}/delete`

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/clusters/8eda86fe-0f36-41ed-9837-0ccf8f6e0fcb/delete' \
--header 'X-API-KEY: <api-key>'
```

---

## GET /clusters/{id}/info

> Get details for the specified, non deleted, cluster in the url.

**Endpoint**: `https://api.shadeform.ai/v1/clusters/{id}/info`

Returns a single Cluster object.

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/clusters/8eda86fe-0f36-41ed-9837-0ccf8f6e0fcb/info' \
--header 'X-API-KEY: <api-key>'
```

---

## GET /clusters/types

> Return all the GPU cluster types with their corresponding availability and specs.

**Endpoint**: `https://api.shadeform.ai/v1/clusters/types`

Returns available cluster configurations similar to /instances/types but for multi-node cluster deployments.

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/clusters/types' \
--header 'X-API-KEY: <api-key>'
```
