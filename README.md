---
chef-knife-kvm
---

A knife plugin suite built upon the fog-libvirt library suite that creates/bootstraps and destroys kvm guests.
Supports GSSAPI ssh connections with qemu+ssh and Net::SSH.

requirements:
* fog-libvirt
* net-ssh
If you want to use GSSAPI with ssh you will need:
* net-ssh-krb

In alpha ... more documentation coming forthwith.
