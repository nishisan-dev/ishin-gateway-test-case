ENV['VAGRANT_DEFAULT_PROVIDER'] ||= 'libvirt'

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.box_version = "202502.21.0"

  config.vm.synced_folder ".", "/vagrant", disabled: true

  machines = [
    {
      name: "ngate-1",
      hostname: "ngate-1",
      ip: "192.168.56.11",
      service_guest_port: 9090,
      service_host_port: 19090,
      management_guest_port: 9190,
      management_host_port: 19190,
      dashboard_guest_port: 9200,
      dashboard_host_port: 19200,
      memory: 2048,
      provisioner: "scripts/install_ngate.sh",
      args: [
        "ngate-1",
        "192.168.56.11",
        "192.168.56.21",
        "80",
        "ngate-2:7100"
      ]
    },
    {
      name: "ngate-2",
      hostname: "ngate-2",
      ip: "192.168.56.12",
      service_guest_port: 9090,
      service_host_port: 29090,
      management_guest_port: 9190,
      management_host_port: 29190,
      dashboard_guest_port: 9200,
      dashboard_host_port: 29200,
      memory: 2048,
      provisioner: "scripts/install_ngate.sh",
      args: [
        "ngate-2",
        "192.168.56.12",
        "192.168.56.21",
        "80",
        "ngate-1:7100"
      ]
    },
    {
      name: "web-1",
      hostname: "web-1",
      ip: "192.168.56.21",
      service_guest_port: 80,
      service_host_port: 18080,
      memory: 1024,
      provisioner: "scripts/install_nginx.sh",
      args: ["web-1"]
    },
    {
      name: "zipkin-1",
      hostname: "zipkin-1",
      ip: "192.168.56.31",
      service_guest_port: 9411,
      service_host_port: 39411,
      memory: 3072,
      provisioner: "scripts/install_zipkin.sh",
      args: ["zipkin-1"]
    }
  ]

  machines.each do |machine|
    config.vm.define machine[:name] do |node|
      node.vm.hostname = machine[:hostname]
      node.vm.network "private_network", ip: machine[:ip]
      node.vm.network "forwarded_port",
        guest: machine[:service_guest_port],
        host: machine[:service_host_port],
        auto_correct: true

      if machine[:management_guest_port]
        node.vm.network "forwarded_port",
          guest: machine[:management_guest_port],
          host: machine[:management_host_port],
          auto_correct: true
      end

      if machine[:dashboard_guest_port]
        node.vm.network "forwarded_port",
          guest: machine[:dashboard_guest_port],
          host: machine[:dashboard_host_port],
          auto_correct: true
      end

      node.vm.provider "libvirt" do |lv|
        lv.memory = machine[:memory]
        lv.cpus = 2
      end

      node.vm.provider "virtualbox" do |vb|
        vb.name = "n-gate-#{machine[:name]}"
        vb.memory = machine[:memory]
        vb.cpus = 2
      end

      node.vm.provision "shell", path: "scripts/common.sh"
      node.vm.provision "shell", path: machine[:provisioner], args: machine[:args]
    end
  end
end
