[//]: # (URL: https://docs.shadeform.ai/guides/startupscript)

# Run Startup Script

### Intro

We can configure a bash startup script that automatically runs on an instance immediately after the instance becomes active.

### Example

We can configure a bash startup script using Shadeform's Create Instance API.
In this example, we will run the script below once the instance becomes ready.

```bash
#!/bin/bash
counter=1

# Infinite loop
while true; do
  echo $counter
  # Increment the counter
  ((counter++))
  # Wait for 3 seconds
  sleep 3
done
```

First, we must [Base64 encode](https://en.wikipedia.org/wiki/Base64) the script to preserve all special characters, whitespacing, and formatting of the script.
We recommend using [this tool](https://www.base64encode.org/) to base64 encode our script. After base64 encoding the script, you should get the following:

```
IyEvYmluL2Jhc2gKY291bnRlcj0xCgojIEluZmluaXRlIGxvb3AKd2hpbGUgdHJ1ZTsgZG8KICBlY2hvICRjb3VudGVyCiAgIyBJbmNyZW1lbnQgdGhlIGNvdW50ZXIKICAoKGNvdW50ZXIrKykpCiAgIyBXYWl0IGZvciAzIHNlY29uZHMKICBzbGVlcCAzCmRvbmUK
```

After we have base64 encoded our script, we can create a new GPU instance with the startup script included in the `base64_script` property.

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
  "name": "docker-example",
  "launch_configuration": {
    "type": "script",
    "script_configuration": {
      "base64_script": "IyEvYmluL2Jhc2gKY291bnRlcj0xCgojIEluZmluaXRlIGxvb3AKd2hpbGUgdHJ1ZTsgZG8KICBlY2hvICRjb3VudGVyCiAgIyBJbmNyZW1lbnQgdGhlIGNvdW50ZXIKICAoKGNvdW50ZXIrKykpCiAgIyBXYWl0IGZvciAzIHNlY29uZHMKICBzbGVlcCAzCmRvbmUK"
    }
  }
}'
```

Once the instance is created, we can get the status and IP address of the instance by calling the Instances API.
Once the instance is active, we can verify that the script ran correctly by SSHing into the instance and running:

```bash
journalctl -u init-script -f
```

### Security

The script provided is encrypted at rest.
