---
chef-knife-kvm
---

A knife plugin suite built upon the fog-libvirt library suite that creates/bootstraps and destroys kvm guests. SSH using GSSAPI authentication is available for qemu+ssh// urls and Net::SSH connections. This is in alpha but I plan to add a lot more functionality as ruby-libvirt and fog-libvirt expose a great deal of the libvirt C API.

For now, you can create machines from a template image - setting number of vcpus as well as memory size are available. The machine can then be bootstrapped with chef client if desired, and configured through your normal chef workflow. Deleting machines and their associated storage functionality is there. as well as a rudimentary list plugin that displays vms and volumes.
requirements:
* fog-libvirt
* net-ssh

If you want to use GSSAPI with ssh you will need:
* net-ssh-krb

In alpha ... more documentation coming forthwith.
