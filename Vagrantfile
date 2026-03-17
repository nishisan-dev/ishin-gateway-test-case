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
      ],
      banner: [
        "🔀 Proxy:     http://localhost:19090",
        "⚙️  Management: http://localhost:19190",
        "📊 Dashboard:  http://localhost:19200",
        "🔗 Cluster:    192.168.56.11:7100"
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
      ],
      banner: [
        "🔀 Proxy:     http://localhost:29090",
        "⚙️  Management: http://localhost:29190",
        "📊 Dashboard:  http://localhost:29200",
        "🔗 Cluster:    192.168.56.12:7100"
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
      args: ["web-1"],
      banner: [
        "🌐 Nginx: http://localhost:18080"
      ]
    },
    {
      name: "zipkin-1",
      hostname: "zipkin-1",
      ip: "192.168.56.31",
      service_guest_port: 9411,
      service_host_port: 39411,
      memory: 1024,
      provisioner: "scripts/install_zipkin.sh",
      args: ["zipkin-1"],
      banner: [
        "🔍 Zipkin UI: http://localhost:39411",
        "📡 Zipkin API: http://localhost:39411/api/v2/traces"
      ]
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

      # ─── Banner pós-provisionamento ──────────────────────────────────
      node.trigger.after :up do |trigger|
        trigger.info = banner_text(machine)
      end
    end
  end
end

# ─── Helper: monta o banner de cada VM ──────────────────────────────────────
def banner_text(machine)
  separator = "━" * 56
  lines = []
  lines << ""
  lines << separator
  lines << "  ✅ #{machine[:name]} está rodando!"
  lines << "  📍 IP privado: #{machine[:ip]}"
  lines << separator
  machine[:banner].each { |b| lines << "  #{b}" }
  lines << separator
  lines << ""
  lines.join("\n")
end

