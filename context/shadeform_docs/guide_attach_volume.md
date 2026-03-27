[//]: # (URL: https://docs.shadeform.ai/guides/attachvolume)

# Setup a Volume

Volumes provide persistent block storage that can be attached to instances for storing data independently of the instance lifecycle. This makes them ideal for scenarios where you need to maintain critical data even after instances are deleted or replaced. Volumes can be reused and mounted across multiple instances, providing flexibility and durability for your storage needs.

In this guide, we will cover how to create a volume, attach it to an instance, and verify that it is mounted via the Shadeform API. This process involves creating a volume first, launching an instance with the volume attached, and confirming the volume on the instance.

Currently, volumes can only be attached to instances in the same cloud provider and region. Multi-cloud volumes are an upcoming feature.

### Prerequisites

1. After you have created your account, you must top up your wallet [here](https://platform.shadeform.ai/settings/billing).
2. After you have topped up your wallet, generate and retrieve your Shadeform API key [here](https://platform.shadeform.ai/settings/api).

### Step 1: Check Available Volume Types

Use the [`/volumes/types`](https://docs.shadeform.ai/api-reference/volumes/volumes-types) endpoint to fetch available volume types.

```bash
# Retrieve available volume types
curl --location 'https://api.shadeform.ai/v1/volumes/types' \
--header 'x-api-key: <api-key>'
```

**Example Response**

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

Take note of the `cloud` and `region` fields for the next step.

---

### Step 2: Create a Volume

> Note: Your volume and instance will need to have the same cloud provider, and be in the same region to work.

```bash
# Create a new volume
curl --location 'https://api.shadeform.ai/v1/volumes/create' \
--header 'x-api-key: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
    "cloud": "digitalocean",
    "region": "tor1",
    "size_in_gb": 100,
    "name": "mystoragevolume"
}'
```

**Example Response**

```json
{
  "id": "df5c952c-0567-4140-94d6-59cee96f8caa"
}
```

Save the `id` field as you will need it in the next step.

---

### Step 3: Create an Instance with the Volume Attached

> Note: "volume_ids" must be an array of size one. This is because we only allow attaching one volume to one instance right now.

```bash
# Create an instance with the volume attached
curl --location 'https://api.shadeform.ai/v1/instances/create' \
--header 'x-api-key: <api-key>' \
--header 'Content-Type: application/json' \
--data '{
  "cloud": "digitalocean",
  "region": "tor1",
  "shade_instance_type": "H100_sxm5",
  "shade_cloud": true,
  "name": "the-super-cool-digitalocean-server-volume",
  "volume_ids": ["b1f2c5d3-29ab-4e7b-9f7e-2c35a1e34d4e"]
}'
```

**Example Response**

```json
{
  "id": "cc9f6b74-9825-4854-9e9c-dd50c7e97c3a",
  "cloud_assigned_id": "720f2a6a-e4ee-488a-ade1-e7892f5d730a"
}
```

---

### Step 4: Verify the Volume on the Instance

Once the instance is active, SSH into it to verify that the volume has been mounted.

```bash
# List all block devices attached to the instance
lsblk
```

Your output should look something similar to this:

```
NAME    MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
vda     252:0    0   128G  0 disk
├─vda1  252:1    0 127.9G  0 part /
├─vda14 252:14   0     4M  0 part
└─vda15 252:15   0   106M  0 part /boot/efi
vdb     252:16   0    50G  0 disk # this is the volume I mounted
nvme0n1 259:0    0 894.3G  0 disk
```

---

### Step 5: Mount the volume to a file system

Find your volume from the `lsblk` command (in this example the volume is `vdb`) and mount it to a directory:

```bash
sudo mkdir /mnt/vdb
sudo mkfs.ext4 /dev/vdb
sudo mount -t ext4 /dev/vdb /mnt/vdb/
sudo chown -R shadeform:shadeform /mnt/vdb/
```

Now, the `/mnt/vdb` directory should be connected to your volume and fully accessible for you to write and read from.

---

### Step 6: Deleting the Instance and Volume

Before you can delete a volume, you must delete the instance it is attached to.

**Delete the Instance**

```bash
# Delete the instance
curl --location 'https://api.shadeform.ai/v1/instances/<instance-id>/delete' \
--header 'x-api-key: <api-key>'
```

**Delete the Volume**

Once the instance has been deleted, you can safely delete the volume:

```bash
# Delete the volume
curl --location 'https://api.shadeform.ai/v1/volumes/<volume-id>/delete' \
--header 'x-api-key: <api-key>'
```

---

### Summary

You have successfully created a volume, attached it to an instance, verified the attachment, and learned how to clean up resources. For more details, check out the [Shadeform API reference](https://docs.shadeform.ai/api-reference/volumes/volumes-create).
