[//]: # (URL: https://docs.shadeform.ai/getting-started/concepts)

# Core Concepts

These are some of the core concepts that power Shadeform.

### Cloud / Cloud Provider

Shadeform is an abstraction layer over lots of cloud providers and data centers. In Shadeform's platform and API, cloud refers to the underlying provider that is supplying GPU instances through Shadeform.

### Shade Instance Type and Cloud Instance Type

**Shade instance type** is the generalized name for instances based on its GPU configuration. Shadeform uses this generalized instance naming to better group similar instance types in different clouds.

**Cloud instance type** is the name of the instance in the underlying cloud provider. You can use cloud instance type to look up cloud specific documentation for the instance.

| Cloud      | Cloud Instance Type          | Shade Instance Type |
| ---------- | ---------------------------- | ------------------- |
| AWS        | p4de.24xlarge                | A100_80Gx8          |
| Azure      | Standard_ND96amsr_A100_v4    | A100_80Gx8          |
| HyperStack | n2-A100x8                    | A100_80Gx8          |

As you can see, the cloud instance type can vary greatly depending on the provider whereas the shade instance type is standardized across providers. The combination of cloud and shade instance type uniquely denotes a GPU instance type.

### Cloud Access

If you prefer not to use Shade Cloud, you can also set up cloud access [here](https://platform.shadeform.ai/settings/cloudaccess) to have Shadeform manage your own cloud account. Setting up cloud access typically means providing Shadeform with your cloud API key but can also mean deploying resource stacks that grant Shadeform permissions in your cloud provider.

### Launch Configuration

Launch configurations are additional settings that you can provide when launching a GPU instance through Shadeform.

**Script Launch Configuration** allows you to provide a custom bash script that gets run on your instance once it becomes active.

**Docker Launch Configuration** allows you to provide a container image which gets run on your instance once it becomes active.

> Warning: For Docker Launch Configuration, you are not running a serverless container. Shadeform is merely spinning up the container on the VM that you spun up.
