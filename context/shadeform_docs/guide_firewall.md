[//]: # (URL: https://docs.shadeform.ai/guides/firewall)

# Setup Firewall Using UFW

### Intro

While Shadeform does not currently provide any firewall rules through the platform, we can set up a firewall on the GPU instance using [Uncomplicated Firewall](https://wiki.ubuntu.com/UncomplicatedFirewall).

### Setting up UFW

Follow the [QuickStart](/getting-started/quickstart) guide on how to create a GPU instance and SSH into it.

Once you have terminal access, use the following command to verify that UFW is installed on the machine.
UFW should already come pre-installed on all Shadeform instances.

```bash
sudo ufw status
```

You can now specify allow and deny rules using the `ufw` cli.
You can specify the port range and the protocol.
Additionally, you can also specify blanket allows and denies.

```bash
sudo ufw allow 22/tcp   # Allow TCP on port 22
sudo ufw allow 80/tcp   # Allow TCP on port 80
sudo ufw allow 443/tcp  # Allow TCP on port 443
sudo ufw allow 1194/udp # Allow UDP on port 1194
sudo ufw deny 25/tcp    # Deny TCP on port 25
sudo ufw allow 3000:4000/tcp  # Allow TCP on ports 3000-4000
```

> Warning: It is possible to block your own SSH access if you blanket deny all incoming traffic without having an explicit allow rule for port 22 for TCP. If this happens, you will be locked out of your instance. For certain cloud providers, Shadeform can work with the underlying cloud provider to disable `ufw` but this is not guaranteed.

Once you have configured all of your `ufw` policies, make sure to enable `ufw` using the command below. Rules are only applied when you enable the service.

```bash
sudo ufw enable
```
