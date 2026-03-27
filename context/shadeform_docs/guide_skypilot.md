[//]: # (URL: https://docs.shadeform.ai/guides/skypilot)

# Run Jobs with SkyPilot

## What is SkyPilot?

[SkyPilot](https://docs.skypilot.co/en/latest/docs/index.html) is an open-source framework that simplifies running AI workloads on any cloud. It automatically finds the best price and availability across multiple cloud providers, provisions resources, and manages your jobs - all from a single unified interface.

## Using Shadeform with SkyPilot

SkyPilot integrates with Shadeform to give you access to the best GPU prices across Shadeform's marketplace of cloud providers. When you specify `infra: shadeform` in your SkyPilot task, SkyPilot will automatically search across all available providers in Shadeform to find the optimal GPU for your workload.

### Setup

1. **Install SkyPilot**

   ```bash
   # Recommended: use a new conda env to avoid package conflicts.
   # SkyPilot requires 3.7 <= python <= 3.13.
   conda create -y -n sky python=3.10
   conda activate sky

   # Install just the Shadeform provider
   pip install "skypilot[shadeform]"

   # Optional: Install all supported providers
   pip install "skypilot[all]"
   ```

   For more information on installing SkyPilot, see the [SkyPilot documentation](https://docs.skypilot.co/en/latest/getting-started/installation.html).

2. **Get your Shadeform API Key**

   Sign up at [shadeform.ai](https://shadeform.ai) and obtain an API key from your [account settings page](https://platform.shadeform.ai/settings/api).

3. **Configure your credentials**

   In order to use Shadeform with SkyPilot you need to place your API key in a file called `api_key` in the `~/.shadeform` directory on your machine.

   ```bash
   mkdir ~/.shadeform
   echo "your-api-key-here" > ~/.shadeform/api_key
   ```

4. **Verify the setup**

   ```bash
   sky check shadeform
   ```

You're now ready to launch GPU workloads on Shadeform through SkyPilot!

## Running Jobs

SkyPilot works by writing a YAML file that describes your job and then launching it with the `sky launch` command. A simple job that just prints "Hello, World!" would look like this:

```yaml
resources:
  infra: shadeform

run: |
  echo "Hello, World!"
```

If you save that file as `job.yaml` you can launch it with:

```bash
sky launch job.yaml
```

For more information on what a cluster is, what job is, and how to build SkyPilot YAML jobs, refer to the [quickstart guide](https://docs.skypilot.co/en/latest/getting-started/quickstart.html) and [examples page](https://docs.skypilot.co/en/latest/examples/index.html).

### Defining a Shadeform Resource

You can use Shadeform GPUs in three different ways in a SkyPilot YAML file by defining the `infra`, `accelerators`, or `instance_type` fields.
To know what Shadeform GPUs are available, you can use the SkyPilot Catalog for Shadeform [here](https://github.com/skypilot-org/skypilot-catalog/blob/master/catalogs/v8/shadeform/vms.csv).

In the `vms.csv` file:
- `InstanceType` maps to the `instance_type` field in the SkyPilot YAML file.
- `Accelerators` maps to the `accelerators` field.
- `AcceleratorCount` shows how many GPUs that type has.

#### Find the cheapest available across all Shadeform providers

```yaml
resources:
  infra: shadeform
```

#### Find the cheapest available for a specific GPU type

```yaml
resources:
  infra: shadeform
  accelerators: A100:4  # this means A100 with 4 GPUs
```

> Note: `infra` is optional if you define `accelerators`. But, when you have other SkyPilot integrations installed and you leave out `infra`, SkyPilot may pick your other integration to use if it has a cheaper accelerator of the same type available.

#### Find the cheapest available for a specific provider and GPU type

```yaml
resources:
  infra: shadeform       # optional when you define an instance_type
  accelerators: A6000:4  # optional when you define an instance_type
  instance_type: hyperstack_A6000
```

### Useful Commands

```bash
# Launch a job
sky launch task.yaml

# Launch with a specific cluster name
sky launch -c my-cluster task.yaml

# Check job status
sky status

# View logs
sky logs my-cluster

# Stop the cluster
sky stop my-cluster

# Terminate the cluster
sky down my-cluster
```
