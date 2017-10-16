# knife kvm list 
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

class KvmList < Chef::Knife

  banner "knife kvm list (options)"
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
   
  option :hv,
    :short => "-H HYPERVISOR",
    :long => "--hypervisor",
    :description => "Hostname of KVM hypervisor",
    :proc => Proc.new { |t| Chef::Config[:knife][:hv] = t }

  option :lkvm,
    :long => "--lkvm",
    :description => "List VMs"

  option :lvol,
    :long => "--lvol",
    :description => "List volumes"


  def run
    kvmconf = Chef::Config[:knife] 
    kvmvol = [kvmconf[:kvmname], ".qcow2"].join("")
    kvmconf[:hv] ||= "hydrogen"

    unless kvmconf[:hv]
      ui.error("Missing HYPERVISOR")
      exit 1
    end

    unless config[:lkvm] || config[:lvol]
      ui.error("Choose --lvol for volumes or --lkvm for VMs")
      exit 1
    end

    compute = Fog::Compute.new({ :provider => "libvirt",
				 :libvirt_uri => ["qemu+ssh://", kvmconf[:hv], "/system"].join("")
                               })

    if config[:lvol]
      # get volume key 
      puts ["----- VOLUMES for HOST:", kvmconf[:hv], "-----"].join(" ") 
      puts "    volume : volume_key"
      puts "---------------------------------"
      compute.volumes.each do |vol|
        puts [vol.name, vol.key].join(" : ") 
      end 
    end
    
   if config[:lkvm]
     # get vm uuid
     puts ["----- VMs for HOST:", kvmconf[:hv], "-----"].join(" ") 
     puts "    vm : vm_uuid"
     puts "----------------------------------"
     compute.servers.each do |server|
       puts [server.name, server.uuid].join(" : ")
     end 
   end
  end
end
