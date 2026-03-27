[//]: # (URL: https://docs.shadeform.ai/guides/vllm)

# Serve Model Using vLLM

Model Deployment is a very common GPU use case. With Shadeform, it's easy to deploy models right to the most affordable GPUs in the market with just a few commands.

In this guide, we will deploy [Mistral-7b-v0.1](https://huggingface.co/mistralai/Mistral-7B-v0.1) with vLLM onto an A6000.

### Setup

This guide builds off of our others for [finding the best GPU](https://docs.shadeform.ai/guides/mostaffordablegpus) and for [deploying GPU containers](https://docs.shadeform.ai/guides/dockercontainers).
We have a python notebook already ready for you to deploy this model that you can [find here](https://github.com/shadeform/examples/blob/main/basic_serving_vllm.ipynb).

```bash
git clone https://github.com/shadeform/examples.git
cd examples/
```

Then in `basic_serving_vllm.ipynb` you will need to input your [Shadeform API Key](https://platform.shadeform.ai/settings/api).

### Serving a Model

Once we have an instance, we deploy a model serving container with this request payload.

```python
model_id = "mistralai/Mistral-7B-v0.1"

payload = {
  "cloud": best_instance["cloud"],
  "region": region,
  "shade_instance_type": shade_instance_type,
  "shade_cloud": True,
  "name": "cool_gpu_server",
  "launch_configuration": {
    "type": "docker",
    # This selects the image to launch
    "docker_configuration": {
      "image": "vllm/vllm-openai:latest",
      "args": "--model " + model_id,
      "envs": [],
      "port_mappings": [
        {
          "container_port": 8000,
          "host_port": 8000
        }
      ]
    }
  }
}

response = requests.request("POST", create_url, json=payload, headers=headers)
print(response.text)
```

Once we request it, Shadeform will provision the machine, and deploy a docker container based on the image, arguments, and environment variables that we selected.
This might take 5-10 minutes depending on the machine chosen and the size of the model weights you choose.

### Checking on our Model server

There are three main steps that we need to wait for: VM Provisioning, image building, and spinning up vLLM.

```python
instance_response = requests.request("GET", base_url, headers=headers)
ip_addr = ""
print(instance_response.text)
instance = json.loads(instance_response.text)["instances"][0]
instance_status = instance['status']
if instance_status == 'active':
    print(f"Instance is active with IP: {instance['ip']}")
    ip_addr = instance['ip']
else:
    print(f"Instance isn't yet active: {instance}" )
```

#### Watch via the notebook

Once the model is ready, this code will output the model list and a response to our query. We can use either requests or OpenAI's completions library.

Using requests:

```python
model_list_response = requests.get(f'http://{ip_addr}:8000/v1/models')
print(model_list_response.text)

vllm_headers = {
  'Content-Type': 'application/json',
}

json_data = {
  'model': model_id,
  'prompt': 'San Francisco is a',
  'max_tokens': 7,
  'temperature': 0,
}

completion_response = requests.post(f'http://{ip_addr}:8000/v1/completions', headers=vllm_headers, json=json_data)
print(completion_response.text)
```

Using OpenAI library:

```python
from openai import OpenAI

openai_api_key = "EMPTY"
openai_api_base = f"http://{ip_addr}:8000/v1"
client = OpenAI(
  api_key=openai_api_key,
  base_url=openai_api_base,
)
completion = client.completions.create(model=model_id,
  prompt="San Francisco is a")
print("Completion result:", completion)
```

#### Watching with the Shadeform UI

Or once we've made the request, we can watch the logs under [Running Instances](https://platform.shadeform.ai/instances). Once it is ready to serve, the logs will show the vLLM server is running.
