Vagrant.configure("2") do |config|
  config.vm.box = ENV.fetch("VAGRANT_WINDOWS_BOX", "gusztavvargadr/windows-server-2022-standard")
  config.vm.guest = :windows
  config.vm.communicator = "winrm"

  config.winrm.username = ENV.fetch("VAGRANT_WINDOWS_USERNAME", "vagrant")
  config.winrm.password = ENV.fetch("VAGRANT_WINDOWS_PASSWORD", "vagrant")
  config.winrm.timeout = 1800
  config.winrm.retry_limit = 60

  config.vm.provider "virtualbox" do |vb|
    vb.name = "chocolatey-duo-auth-proxy-test"
    vb.memory = ENV.fetch("VAGRANT_MEMORY", "4096")
    vb.cpus = ENV.fetch("VAGRANT_CPUS", "2")
  end

  config.vm.provision "shell",
    privileged: true,
    path: "tests/vagrant/provision.ps1",
    env: {
      "DUO_TEST_UNINSTALL" => ENV.fetch("DUO_TEST_UNINSTALL", "false")
    }
end
