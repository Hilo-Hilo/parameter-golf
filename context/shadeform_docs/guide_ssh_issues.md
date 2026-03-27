[//]: # (URL: https://docs.shadeform.ai/guides/sshissues)

# Common SSH Issues and Solutions

### Intro

These are some common issues users experience when connecting to Shadeform GPUs via SSH and the solutions to fix them.

### Unprotected Key File

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@         WARNING: UNPROTECTED PRIVATE KEY FILE!          @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Permissions 0644 for 'ronald.pem' are too open.
It is required that your private key files are NOT accessible by others.
This private key will be ignored.
Load key "ronald.pem": bad permissions
hotaisle@23.183.40.132: Permission denied (publickey).
```

This issue indicates that the private key file (.pem format) does not have the correct permissions. On unix based systems (Linux or MacOS), run the following to fix:

```
chmod 600 <path_to_key_file>
```

### Remote Host Identification Has Changed

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
...
Host key for <ip> has changed and you have requested strict checking.
Host key verification failed.
```

This issue appears when the underlying server/host for the IP address has changed since the last time you connected to this IP address.
On Shadeform, a lot of our providers have a pool for their public IP addresses that their machines pull from. Therefore, if you have previously launched a Shadeform instance and just now relaunched one, it's very likely that the IP address was reused but the machine behind the IP is a new one.

You can very quickly resolve this problem by running the command below to reset your cache of IPs and hosts.

```
ssh-keygen -R <ip>
```

### Permission Denied

```
shadeform@23.183.40.132: Permission denied (publickey)
```

If you are sure you're using the correct private key and are still getting permission denied, it's possible that you have multiple other keys in your keychain that SSH is automatically trying first. The target server will automatically reject your SSH attempts after a number of back to back failures. In this case, you will need to specifically target a private key file and only use that one for SSH.

```
ssh -i <path_to_private_key> -o IdentitiesOnly=yes shadeform@<ip>
```
