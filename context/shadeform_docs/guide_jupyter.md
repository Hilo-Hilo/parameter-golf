[//]: # (URL: https://docs.shadeform.ai/guides/jupyter)

# Run Jupyter Notebook

### Intro

You can quickly set up a Jupyter Notebook instance running on a Shadeform GPU using Shadeform's docker launch configuration.
All Shadeform instances come pre-installed with Python, Cuda, and Docker so running containers is easy.

### Example

For this example, we will run the container image `quay.io/jupyter/pytorch-notebook:cuda12-python-3.11.8`.
We will be running the instance on an A6000 GPU at $0.57/hr.
Make sure to replace `<api-key>` with your account's API Key.

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
  "name": "jupyter-notebook",
  "launch_configuration": {
    "type": "docker",
    "docker_configuration": {
      "image": "quay.io/jupyter/pytorch-notebook:cuda12-python-3.11.8"
    }
  }
}'
```

After making the curl request, you should see a response like this:

```json
{"id":"26bedfa2-1e98-4ff5-9342-a5b0987a2f0f","cloud_assigned_id":"b9ecaf4e-d6ac-42eb-a89a-60010065388a"}
```

After you've launched the instance, you can track the instance progress by visiting the [Running Instances page](https://platform.shadeform.ai/instances).
When you're on the page, select the instance named `jupyter-notebook` and click on the `Logs` tab.

You can follow the progress of the container download and spin up in the log feed.

When the container is fully spun up and your Jupyter Notebook instance is running, you will see an entry that looks like this:

`http://shadecloud:8888/lab?token=736db552017247000023364f8e215cebebaa2f4431b4b015`

Make sure to save the token from that url.

After the container is spun up, you can take the IP of the instance and go to the following url:

`http://<ip_address>:8888`

On this page, you will need to paste in the token you saved earlier and click the `Login` button.
After logging in with your token, your Jupyter Notebook instance is up and running!
You can use the following code to check for the GPU on your machine.

```python
import torch

# Check if CUDA is available
if torch.cuda.is_available():
  print("CUDA is available. GPU Details:")
  print(f"Number of GPUs: {torch.cuda.device_count()}")
  for i in range(torch.cuda.device_count()):
    print(f"GPU {i}: {torch.cuda.get_device_name(i)}")
else:
  print("CUDA is not available. Running on CPU.")
```
