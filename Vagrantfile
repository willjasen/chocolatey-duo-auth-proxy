Vagrant.configure("2") do |config|
  config.vm.box = ENV.fetch("VAGRANT_WINDOWS_BOX", "gusztavvargadr/windows-server-2022-standard")
  config.vm.guest = :windows
  config.vm.communicator = "winrm"
  config.vm.boot_timeout = Integer(ENV.fetch("VAGRANT_BOOT_TIMEOUT", "1800"))

  config.winrm.username = ENV.fetch("VAGRANT_WINDOWS_USERNAME", "vagrant")
  config.winrm.password = ENV.fetch("VAGRANT_WINDOWS_PASSWORD", "vagrant")
  config.winrm.timeout = 1800
  config.winrm.retry_limit = 60

  config.vm.provider "virtualbox" do |vb|
    vb.name = "chocolatey-duo-auth-proxy-test"
    vb.memory = ENV.fetch("VAGRANT_MEMORY", "16384")
    vb.cpus = ENV.fetch("VAGRANT_CPUS", "4")
  end

  push_api_key = ENV["DUO_PUSH_API_KEY"]
  if push_api_key.nil? || push_api_key.empty?
    key_file = File.expand_path("~/.chocolatey/duo-auth-proxy-api-key")
    if File.exist?(key_file)
      push_api_key = File.read(key_file).strip
    end
  end

  config.vm.provision "shell",
    privileged: true,
    path: "tests/vagrant/provision.ps1",
    env: {
      "DUO_TEST_UNINSTALL" => ENV.fetch("DUO_TEST_UNINSTALL", "false"),
      "DUO_PUSH_API_KEY" => push_api_key.to_s,
      "DUO_PUSH_SOURCE" => ENV.fetch("DUO_PUSH_SOURCE", "https://push.chocolatey.org/")
    }
end
