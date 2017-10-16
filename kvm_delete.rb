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
   
  option :kvmname,
    :short => "-N NAME",
    :long => "--node-name NAME",
    :description => "The Name of the VM to delete",
    :proc => Proc.new { |t| Chef::Config[:knife][:kvmname] = t }

  option :hv,
    :short => "-H HYPERVISOR",
    :long => "--hypervisor",
    :description => "HYPERVISOR\n" \
    "                         1: hydrogen\n" \
    "                         2: helium\n",    
    :proc => Proc.new { |t| Chef::Config[:knife][:hv] = t }

  option :pool,
    :short => "-X POOL",
    :long => "--pool POOL",
    :description => "COMPUTE POOL for VM - defaults to hydrogen: vm",
    :proc => Proc.new { |t| Chef::Config[:knife][:pool] = t }

  def run
    kvmname = Chef::Config[:knife][:kvmname]
    kvmvol = [kvmname, ".qcow2"].join("")

    unless kvmname
      ui.error("Missing Node Name")
      exit 1
    end

    Chef::Config[:knife][:hv] ||= 1

    hv = 
    img = ""
    pool = ""
    if Chef::Config[:knife][:hv] == "1"
      hv = "hydrogen"
      pool = "vm"
    elsif Chef::Config[:knife][:hv] == "2" 
      hv = "helium"
      pool = "kvm"
    end
    compute = Fog::Compute.new({ :provider => "libvirt",
				 :libvirt_uri => ["qemu+ssh://", hv, "/system"].join("")
                               })

    voluuid = ""
    volname = ""
    compute.volumes.each do |vol|
      if vol.name == kvmvol 
        volname = vol.key
      end
    end 
    
    vmuuid = ""
    vmname = ""
    compute.servers.each do |server|
      if server.name.to_s == kvmname 
        vmname = server.name.to_s
	vmuuid = server.uuid
      end
    end 
 
    puts ["Deleting VM", vmname].join(" ")
    delvm = compute.vm_action( vmuuid, :undefine )
    offvm = compute.vm_action( vmuuid, :destroy)
    delvol = compute.volume_action( volname, :delete )
    sleep (1)
    puts ["VM", vmname, "DESTROYED."].join(" ")
  end
end
