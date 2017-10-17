# knife kvm create
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
require 'chef/knife/bootstrap'

class KvmCreate < Chef::Knife

  banner "knife kvm create (options)"

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
    :description => "The Name of the new VM",
    :proc => Proc.new { |n| Chef::Config[:knife][:kvmname] = n }

  option :kvmip,
    :short => "-I IP",
    :long => "--ip IP",
    :description => "IP Address for VM",
    :proc => Proc.new { |i| Chef::Config[:knife][:kvmip] = i }

  option :oldip,
    :short => "-Q IP",
    :long => "--old-ip IP",
    :description => "Orginal IP Address from cloned image",
    :proc => Proc.new { |q| Chef::Config[:knife][:oldip] = q }
  
  option :strap,
    :short => "-B",
    :long => "--bootstrap",
    :description => "set bootstrap bit"

  option :hv,
    :short => "-H HYPERVISOR",
    :long => "--hv HYPERVISOR",
    :description => "Hostname of KVM hypervisor",
    :proc => Proc.new { |h| Chef::Config[:knife][:hv] = h }
  
  option :template,
    :short => "-O OS_IMAGE",
    :long => "--osimage IMAGE",
    :description => "OS image template to use (VOLUME NAME)",
    :proc => Proc.new { |o| Chef::Config[:knife][:template] = o }

  option :runlist,
    :short => "-r RUN_LIST",
    :long => "--run-list RUN_LIST",
    :description => "Comma separated list of roles/recipes to apply",
    :proc => lambda { |r| r.split(/[\s,]+/) }

  option :pool,
    :short => "-X POOL",
    :long => "--pool POOL",
    :description => "COMPUTE POOL for VM - defaults to hydrogen: vm",
    :proc => Proc.new { |x| Chef::Config[:knife][:pool] = x }

  option :cpus,
    :short => "-C CPUs",
    :long => "--cpus CPUs",
    :description => "# of CPUs for VM",
    :proc => Proc.new { |c| Chef::Config[:knife][:cpus] = c }

  option :mem,
    :short => "-M MEMORY",
    :long => "--mem MEMORY",
    :description => "Memory for VM in MB ( -M 2048 ) defaults to 1024",
    :proc => Proc.new { |m| Chef::Config[:knife][:mem] = m }

  option :disk,
    :short => "-D DISK_SIZE",
    :long => "--disk DISK_SIZE",
    :description => "Capacity for vdisk volume in GB ( -D 10G )",
    :proc => Proc.new { |d| Chef::Config[:knife][:disk] = d }

  option :alloc,
    :short => "-A DISK_ALLOC",
    :long => "--alloc DISK_ALLOC",
    :description => "Storage allocation for vdisk volume in MB or GB ( -A 5120M or -A 1G )",
    :proc => Proc.new { |a| Chef::Config[:knife][:alloc] = a }

  option :volfmt,
    :short => "-F VOLUME_FMT",
    :long => "--fmt VOLUME_FMT",
    :description => "Disk format for volume ( qcow2/img/raw ) defaults to qcow2",
    :proc => Proc.new { |f| Chef::Config[:knife][:volfmt] = f }

  option :itype,
    :short => "-T INT_TYPE",
    :long => "--itype INT_TYPE",
    :description => "Network interface type (bridge || NAT)",
    :proc => Proc.new { |t| Chef::Config[:knife][:itype] = t }

  option :iface,
    :short => "-K INTERFACE",
    :long => "--iface INT_TYPE",
    :description => "Hypervisor network interface to choose",
    :proc => Proc.new { |k| Chef::Config[:knife][:iface] = k }
  
  option :realm,
    :short => "-R REALM",
    :long => "--realm REALM",
    :description => "Domain / realm to have FQDN for chef node/client names",
    :proc => Proc.new { |z| Chef::Config[:knife][:iface] = z }

  # spinner - mostly useless
  def wait_spin(fps = 10)11
    chars = %w[| / - \\]
    delay = 1.0 / fps
    i = 0
    spin = Thread.new do
      while i do  
        print chars[(i += 1) % chars.length]
        sleep delay
        print "\b"
      end
    end
    yield.tap {       
      i = false   
      spin.join   
    }
  end

  def run
    kvmconf = Chef::Config[:knife]
    kvmvol = [kvmconf[:kvmname], ".qcow2"].join("")
    clonevol = [kvmconf[:kvmname], "_r.qcow2"].join("")
    mem = kvmconf[:mem].to_i * 1024 
    # XXX defaults for bytepimps - change or
    # eliminate to your liking - just here for
    # testing convenience
    kvmconf[:template] ||= "centos-7-image.qcow2"
    kvmconf[:cpus] ||= 1
    kvmconf[:mem] ||= "1024"
    kvmconf[:disk] ||= "10G"
    kvmconf[:alloc] ||= "5120M"
    kvmconf[:pool] ||= "vm"
    kvmconf[:hv] ||= "hydrogen"
    kvmconf[:itype] ||= "bridge"
    kvmconf[:iface] ||= "br0"
    kvmconf[:oldip] ||= "192.168.62.56"
    kvmconf[:realm] ||= ".bytepimps.net"
    kvmconf[:usr] ||= "root"
    oldip = ""
    if kvmconf[:hv] == "helium"
      oldip = "192.168.62.156"
    else
      oldip = kvmconf[:oldip] 
    end
    # ^ end hardcodes ^
    kvmconf[:volfmt] ||= "qcow2"

    unless kvmconf[:kvmname] && kvmconf[:kvmip] && kvmconf[:oldip] 
      ui.error("Missing one of New Node Name/Old IP Address/New IP Address")
      exit 1
    end

    # set hypervisor address - if needed change protocol here for now
    virturi = ["qemu+ssh://", kvmconf[:hv], "/system"].join("")
    compute = Fog::Compute.new({ :provider => "libvirt",
				 :libvirt_uri => virturi
                               })

    wait_spin {
      puts ["Creating volume", kvmvol, "for VM", kvmconf[:kvmname]].join(" ")
      # cheating - need to use API
      res = system( ["virsh -c", virturi, "vol-clone", kvmconf[:template], clonevol, "--pool", kvmconf[:pool]].join(" ") )
    }
    # spin it up
    newvm = compute.servers.create(
                      { :name => kvmconf[:kvmname],
		        :volume_pool_name => kvmconf[:pool],
			:volume_capacity => kvmconf[:disk],
			:volume_format_type => kvmconf[:volfmt],
			:allocation => kvmconf[:alloc],
			:network_interface_type => kvmconf[:itype],
		        :network_bridge_name => kvmconf[:iface],
			:cpus => kvmconf[:cpus],
			:memory_size => mem,
		      })

    puts ["Volume created for VM ", kvmconf[:kvmname]].join("")

    # get volume_key for our volume to determine the absolute path
    # to the volume pool of our target 
    vpath = ""
    volkey = ""
    compute.volumes.each do |vol|
      if vol.name == kvmvol
        volkey = vol.key
	arr = volkey.split(/\//)
	l = arr.length
        arr.each_index do |i|
          if i < (l - 1)
            vpath = vpath + "/" + arr[i]
          end
        end
      end
    end
    vpath = vpath + "/"
    vpath[0] = ""
    cpath = vpath + clonevol
    # still finding a way to do an stream upload from the template to the newly created volume
    # but this cheat works for now - copy our template volume over the blank volume while the
    # VM is shut off... it is none the wiser when brought up becaue the xml is identical
    # Also an argument for the SSH key - ~/.ssh for now
    wait_spin {
      Net::SSH.start(kvmconf[:hv], kvmconf[:usr], :keys => "~/.ssh/id_rsa") do |ssh|
        ssh.exec!(["mv -f ", cpath, " ", volkey].join(""))
      end	
      delvol = compute.volume_action( cpath, :delete )
      sleep(2)
    }

    puts ["Powering on VM", newvm.name].join(" ")

    newvm.start()
    wait_spin {
      newvm.wait_for { ready? }
    }
    puts ["VM", newvm.name, "powered ON"].join(" ")
    wait_spin {
      sleep(15)
    }
    kvmip = kvmconf[:kvmip]
    # XXX makes it simple for my env
    if kvmconf[:hv] == "helium"
      oldip = "192.168.62.156"
    else
      oldip = kvmconf[:oldip] 
    end

    puts ["Configuring VM for HOSTNAME", newvm.name, "/ IP", kvmip].join(" ")

    # some minor configuration setup - hostname/IP
    wait_spin {
      Net::SSH.start(oldip, kvmconf[:usr], :keys => "~/.ssh/id_rsa") do |ssh|
        ssh.exec!(["sudo echo ", newvm.name, " > /etc/hostname"].join(""))
	ssh.exec!("for i in system password; do echo 'session    optional    pam_mkhomedir.so skel=/etc/skel umask=0077' >> /etc/pam.d/$i-auth-ac; done")
        ssh.exec("sleep 1")
	# debian
        #ssh.exec!(["sudo perl -p -i -e 's/", oldip, "/", kvmip, "/g' /etc/sysconfig/network-scripts/ifcfg-eth0"].join(""))
        ssh.exec!(["sudo nmcli c modify eth0 ipv4.address ", kvmip, "/24"].join(""))
        ssh.exec("sleep 1")
      end
    }
    puts ["Rebooting ", newvm.name].join("")
    newvm.reboot()
    wait_spin {
       newvm.wait_for { ready? }
       sleep (20)
    }
    puts "Done."
    
    runlist = ""
    if config[:strap]
      bootstrap_node(newvm.name, kvmip).run
    end
  end

  # bootstrap chef-client and install any software from recipes
  def bootstrap_node(server, host)
    bootstrap = Chef::Knife::Bootstrap.new
    bootstrap.name_args = host
    bootstrap.config[:ssh_user] = kvmconf[:usr] 
    # XXX will config
    bootstrap.config[:identity_file] = "~/.ssh/id_rsa"
    # XXX make command switch
    bootstrap.config[:chef_node_name] = [server, kvmconf[:realm]].join("")
    #bootstrap.config[:chef_node_name] = [server, ".bytepimps.net"]
    bootstrap.config[:distro] = "chef-full"
    bootstrap.config[:run_list] = config[:runlist]
    bootstrap.config[:use_sudo] = true
    bootstrap
  end
end
