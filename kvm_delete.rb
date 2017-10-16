# knife kvm delete 
# (c) 2017 Michael Brown <mikal@bytepimps.net>
#
require 'rubygems'
require 'rubygems/gem_runner'
require 'fog'
require 'fog/libvirt'
require 'net/ssh'
require 'net/ssh/multi'
require 'net/scp'
require 'chef/knife/core/bootstrap_context'
require 'chef/knife'
require 'chef/knife/ssh'
require 'chef/json_compat'

class KvmDelete < Chef::Knife

  banner "knife kvm delete (options)"

  option :usr,
    :short => "-U USERNAME",
    :long => "--username USERNAME",
    :description => "SSH username",
    :proc => Proc.new { |username| Chef::Config[:knife][:usr] = username }

  option :pwd,
    :short => "-P PASSWORD",
    :long => "--password PASSWORD",
    :description => "SSH password",
    :proc => Proc.new { |key| Chef::Config[:knife][:pwd] = key }
   
  option :kvmname,
    :short => "-N NAME",
    :long => "--node-name NAME",
    :description => "The Name of the VM to delete",
    :proc => Proc.new { |n| Chef::Config[:knife][:kvmname] = n }

  option :hv,
    :short => "-H HYPERVISOR",
    :long => "--hypervisor",
    :description => "Hostname of KVM hypervisor",
    :proc => Proc.new { |h| Chef::Config[:knife][:hv] = h }


  def run
    kvmconf = Chef::Config[:knife] 
    kvmvol = [kvmconf[:kvmname], ".qcow2"].join("")

    unless kvmconf[:kvmname]
      ui.error("Missing Node Name")
      exit 1
    end

    kvmconf[:hv] ||= "hydrogen"

    compute = Fog::Compute.new({ :provider => "libvirt",
				 :libvirt_uri => ["qemu+ssh://", kvmconf[:hv], "/system"].join("")
                               })

    # get volume key 
    voluuid = ""
    volname = ""
    compute.volumes.each do |vol|
      if vol.name == kvmvol 
        volname = vol.key
      end
    end 
    
    # get vm uuid
    vmuuid = ""
    vmname = ""
    compute.servers.each do |server|
      if server.name.to_s == kvmconf[:kvmname]
        vmname = server.name.to_s
	vmuuid = server.uuid
      end
    end 
 
    # tear it down
    puts ["Deleting VM", vmname].join(" ")
    delvm = compute.vm_action( vmuuid, :undefine )
    offvm = compute.vm_action( vmuuid, :destroy)
    delvol = compute.volume_action( volname, :delete )
    sleep (1)
    puts ["VM", vmname, "DESTROYED."].join(" ")
  end
end
