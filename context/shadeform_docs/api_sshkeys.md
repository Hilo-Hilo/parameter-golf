[//]: # (URL: https://docs.shadeform.ai/api-reference/sshkeys/sshkeys)
[//]: # (URL: https://docs.shadeform.ai/api-reference/sshkeys/sshkeys-add)
[//]: # (URL: https://docs.shadeform.ai/api-reference/sshkeys/sshkeys-delete)
[//]: # (URL: https://docs.shadeform.ai/api-reference/sshkeys/sshkeys-info)
[//]: # (URL: https://docs.shadeform.ai/api-reference/sshkeys/sshkeys-setdefault)

# SSH Keys API

---

## GET /sshkeys

> Get all SSH Keys for the account.

**Endpoint**: `https://api.shadeform.ai/v1/sshkeys`

### Response Schema

```yaml
SshKeysResponse:
  ssh_keys:
    - id: string (uuid)
      name: string
      public_key: string
      is_default: boolean
```

### Example Request

```bash
curl --request GET \
--url https://api.shadeform.ai/v1/sshkeys \
--header 'X-API-KEY: <api-key>'
```

---

## POST /sshkeys/add

> Add a new SSH Key.

**Endpoint**: `https://api.shadeform.ai/v1/sshkeys/add`

### Request Schema

```yaml
AddSshKeyRequest:
  required: [name, public_key]
  properties:
    name: string          # name for the SSH key
    public_key: string    # public key content (ssh-rsa ...)
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
--url https://api.shadeform.ai/v1/sshkeys/add \
--header 'Content-Type: application/json' \
--header 'X-API-KEY: <api-key>' \
--data '{
  "name": "My ssh key",
  "public_key": "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAklOUp..."
}'
```

---

## POST /sshkeys/{id}/delete

> Delete an ssh key. The Shadeform managed SSH Key, current default ssh key, and in use SSH Keys cannot be deleted.

**Endpoint**: `https://api.shadeform.ai/v1/sshkeys/{id}/delete`

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/sshkeys/78a0dd5a-dbb1-4568-b55c-5e7e0a8b0c40/delete' \
--header 'X-API-KEY: <api-key>'
```

---

## GET /sshkeys/{id}/info

> Get details for the specified SSH Key in the url.

**Endpoint**: `https://api.shadeform.ai/v1/sshkeys/{id}/info`

### Response

Returns a single SshKey object:
```json
{
  "id": "78a0dd5a-dbb1-4568-b55c-5e7e0a8b0c40",
  "name": "My ssh key",
  "public_key": "ssh-rsa AAAAB3NzaC1yc2EAAA...",
  "is_default": false
}
```

### Example Request

```bash
curl --request GET \
--url 'https://api.shadeform.ai/v1/sshkeys/78a0dd5a-dbb1-4568-b55c-5e7e0a8b0c40/info' \
--header 'X-API-KEY: <api-key>'
```

---

## POST /sshkeys/{id}/setdefault

> Set the specified SSH Key as the default SSH Key used by Shadeform.

**Endpoint**: `https://api.shadeform.ai/v1/sshkeys/{id}/setdefault`

### Response

Returns 200 to confirm the key was set as default.

### Example Request

```bash
curl --request POST \
--url 'https://api.shadeform.ai/v1/sshkeys/78a0dd5a-dbb1-4568-b55c-5e7e0a8b0c40/setdefault' \
--header 'X-API-KEY: <api-key>'
```
