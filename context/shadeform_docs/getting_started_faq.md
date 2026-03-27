[//]: # (URL: https://docs.shadeform.ai/getting-started/faq)

# FAQ

### Technical

**Help! I have an urgent issue! What do I do?**
Please email [support@shadeform.ai](mailto:support@shadeform.ai). We monitor this email very closely and will accommodate requests as much as possible. Alternatively, join our Slack group [here](https://www.shadeform.ai/?slack=true).

**What cloud providers do you support?**
We are constantly adding new cloud providers! Please see our public [cloud marketplace](https://www.shadeform.ai/exchange) page for the latest.

**I have existing cloud credits. Can I use my cloud credits through Shadeform?**
Absolutely! If you have cloud credits with a specific cloud, you can link your cloud account to Shadeform [here](https://platform.shadeform.ai/settings/cloudaccess). When you launch an instance to that cloud, make sure to toggle Shade Cloud to be off via the UI or set `"shade_cloud":false` in the API.

**How do I access my GPU instance?**
Please see the [Quickstart guide](/getting-started/quickstart#sshing-into-the-instance) on SSHing into your machine.

**What is Shadeform's docker feature?**
While Shadeform primarily focuses on providing virtual machines, we offer a launch configuration that automatically starts up your configured docker container when the VM is ready.

**How much GPU availability is on the platform?**
We tap into each cloud provider's on-demand pool. Therefore, what you see on Shadeform is also what you will see via the cloud provider natively. We can provide estimates for certain providers.

**What's next for Shadeform?**
We're focusing on building more platform features such as team management, SSH key management, volumes, and more. We're also focused on adding more providers to increase optionality.

**What machine SLAs do you have?**
As Shadeform is an abstraction for different clouds and data centers, we inherit the SLAs provided by cloud providers. We can share the cloud specific SLAs upon request. We guarantee all GPUs are in Tier 3 or Tier 4 datacenters.

**What is Shade Cloud?**
Shade Cloud is the name of the feature where we deploy your instances into our network of cloud accounts with each of the cloud providers. By using Shade Cloud, you can use the underlying cloud provider without having an account with them.

**How do I run as the root user on my instance?**
First, save your public SSH key to the `/root/.ssh/authorized_keys` directory. Next, run the following commands:

```bash
sudo chown -R root:root /root/.ssh
sudo chmod 700 /root/.ssh
sudo chmod 600 /root/.ssh/authorized_keys
```

You should now be able to SSH into your instance as the root user.

### Business

**How much does Shadeform cost?**
Shadeform charges the same rate as going direct to the cloud provider. There is no additional fee for using Shadeform to launch instances or manage cloud accounts.

**How does Shadeform billing work?**
When you launch an instance through Shadeform, you pay Shadeform for the GPU time and Shadeform passes the payment to the underlying cloud provider.

**Can I do invoice payments instead of pay as you go?**
Please contact [support@shadeform.ai](mailto:support@shadeform.ai) for setting up invoice payments.

**Can I reserve my instances for a longer period of time?**
We can offer reservation discounts and/or work with you to find the best options for your GPU needs. Please contact [support@shadeform.ai](mailto:support@shadeform.ai) for more information.

**I'm a GPU provider and want to offer my machines through Shadeform. What are the next steps?**
We currently only work with machines that located in Tier 3 and Tier 4 datacenters. If your machines meet this criteria, we'd love to support you as a provider. Please contact [support@shadeform.ai](mailto:support@shadeform.ai).

### Have a question not answered on this page? Reach out to us at [support@shadeform.ai](mailto:support@shadeform.ai)!
