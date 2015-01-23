#
# Cookbook Name:: wakame-vdc
# Recipe:: default
#
# Copyright 2014, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
include_recipe "database::mysql"
include_recipe "reboot-handler"

case node['platform_family']
when 'rhel', 'fedora'

  remote_file '/etc/yum.repos.d/wakame-vdc.repo' do
    source "https://raw.githubusercontent.com/axsh/wakame-vdc/master/rpmbuild/wakame-vdc.repo"
    mode '0644'
  end

  remote_file '/etc/yum.repos.d/openvz.repo' do
    source "https://raw.githubusercontent.com/axsh/wakame-vdc/master/rpmbuild/openvz.repo"
    mode '0644'
  end

  yum_package "ca-certificates" do
    action :upgrade
    notifies :install, "yum_package[epel-release]", :immediately
  end

  yum_package "epel-release" do
    action :nothing
  end

  yum_package "wakame-vdc-dcmgr-vmapp-config"
  yum_package "wakame-vdc-hva-openvz-vmapp-config" do
    notifies :run, 'ruby_block[reboot into openvz kernel]', :immediately
  end

  ruby_block "reboot into openvz kernel" do
    block do
      node.run_state['reboot'] = true
    end
    action :nothing
  end

  # base system packages
  package "vim"

  if node['kernel']['modules'].include?('vznetdev')
    yum_package "wakame-vdc-webui-vmapp-config"

    yum_package "libyaml"

    remote_file "#{Chef::Config[:file_cache_path]}/wakame-vdc-ruby-2.0.0.247.axsh0-1.x86_64.rpm" do
      source "http://dlc.wakame.axsh.jp/packages/3rd/rhel/6/master/wakame-vdc-ruby-2.0.0.247.axsh0-1.x86_64.rpm"
      checksum '01b47ab9bbd27e4374d82642b89d50e5d0b4e83e34d5e4683cb8ffc9ecacd453'
      action :create
    end

    # downgrade ruby
    yum_package "wakeme-vdc-ruby" do
      source "#{Chef::Config[:file_cache_path]}/wakame-vdc-ruby-2.0.0.247.axsh0-1.x86_64.rpm"
      version "2.0.0.247.axsh0-1"
      allow_downgrade true
    end

    service 'network' do
      supports restart: true
      action :enable
    end

    template "/etc/sysconfig/network-scripts/ifcfg-br0" do
      source "ifcfg-br0.erb"
      variables ipaddr: node['wakame-vdc']['lan']['router'],
        netmask: node['wakame-vdc']['lan']['netmask'],
        dns: node['wakame-vdc']['lan']['dns']
      notifies :restart, "service[network]", :immediately
    end

    template "/etc/wakame-vdc/nat-forwarding.sh" do
      source "nat-forwarding.sh.erb"
      variables bridge_network: "192.168.3.0/24",
        bridge_device: "br0",
        gateway_device: "eth0"
    end

    template "/etc/wakame-vdc/dcmgr.conf" do
      source "dcmgr.conf.erb"
      variables password: node['mysql']['server_root_password']
    end
    template "/etc/wakame-vdc/hva.conf" do
      source "hva.conf.erb"
      variables netfilter_script_post_flush: "/etc/wakame-vdc/nat-forwarding.sh"
    end
    template "/etc/wakame-vdc/dcmgr_gui/database.yml" do
      source "database.yml.erb"
      variables password: node['mysql']['server_root_password']
    end
    template "/etc/wakame-vdc/dcmgr_gui/dcmgr_gui.yml" do
      source "dcmgr_gui.yml.erb"
    end
    template "/etc/wakame-vdc/dcmgr_gui/instance_spec.yml" do
      source "instance_spec.yml.erb"
    end
    template "/etc/wakame-vdc/dcmgr_gui/load_balancer_spec.yml" do
      source "load_balancer_spec.yml.erb"
    end

    mysql_service "default" do
      action :create
    end

    mysql_database "wakame_dcmgr" do
      connection(
        host:     'localhost',
        username: 'root',
        password: node['mysql']['server_root_password']
      )
      action :create
      notifies :run, 'execute[dcmgr rake db:up]', :immediately
    end

    execute "dcmgr rake db:up" do
      cwd "/opt/axsh/wakame-vdc/dcmgr"
      command "/opt/axsh/wakame-vdc/ruby/bin/rake db:up"
      notifies :run, "execute[vdc-manage network add --uuid nw-demo1]", :immediately
      action :nothing
    end

    execute "vdc-manage host add demo1" do
      command <<-CMD
        /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage host add hva.demo1 \
          --uuid hn-demo1 \
          --display-name "demo HVA 1" \
          --cpu-cores 100 \
          --memory-size 10240 \
          --hypervisor openvz \
          --arch x86_64 \
          --disk-space 102400 \
          --force
      CMD
      action :nothing
    end

    # Download and register a machine image
    directory "/var/lib/wakame-vdc/images" do 
      recursive true
      notifies :run, 'execute[vdc-manage backupstorage add]', :immediately
    end

    execute "vdc-manage backupstorage add" do
      command <<-CMD
        /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage backupstorage add \
          --uuid bkst-local \
          --display-name "local storage" \
          --base-uri "file:///var/lib/wakame-vdc/images/" \
          --storage-type local \
          --description "storage on the local filesystem"
      CMD
      action :nothing
    end

    machine_image "haproxy1d64" do
      service_type 'lb'
      description "lb-centos6-stud.x86_64.openvz.md.raw.gz local"
      url "https://downloads.vortorus.net/wakame-vdc/images/lb-centos6-stud.x86_64.openvz.md.raw.gz"
      sha246 "93b4d9cecfc3494ac55f230c670dd60df57e1b61227f9e614a406cdf6683c36d"
      md5 "3a243bc4b420e6f7f42cf518249803c7"
      size "238364391"
      allocated "1073741824"
      root_device "uuid:0ceef42a-3542-4e94-ace9-18cd7a54542a"
    end

    machine_image "lbnode1d64" do
      service_type 'lb'
      description "lbnode.x86_64.openvz.md.raw.gz local"
      url "https://downloads.vortorus.net/wakame-vdc/images/lbnode.x86_64.openvz.md.raw.gz"
      sha246 "db58e56984aa4909cb8fbd9ccb56a692f0bcfd819b1a72b650619ed4030af385"
      md5 "dbde35c9f8b8cec303da890eb729d0b9"
      size "230467339"
      allocated "1073741824"
      root_device "uuid:4cb57dee-b541-493f-afa6-d84be44ef2af"
    end

    machine_image "vanilla1d64" do
      description "vanilla.x86_64.openvz.md.raw.gz local"
      url "https://downloads.vortorus.net/wakame-vdc/images/vanilla.x86_64.openvz.md.raw.gz"
      sha246 "8c6e906340bb6bc9050be1ef2932c0304e62a3bdf8b23451077519c2b984d870"
      md5 "8cc56d7bea81ecd1b6609de25bf74c03"
      size "277540653"
      allocated "4294967296"
      root_device "uuid:4e8dab0a-5b0b-43bf-ae0b-9794bedd74ef"
    end

    machine_image "centos64" do
      description "CentOS 6.4"
      url "https://downloads.vortorus.net/wakame-vdc/images/centos-6.4.x86_64.openvz.md.raw.gz"
      sha246 "caaec809de5d1dc1063dfa6e56fef41507aeae169ff2183ca5e1f25b00ad2921"
      md5 "222188f4182429f901b55edf4de14a70"
      size "277423041"
      allocated "4294967296"
      root_device "uuid:0a5283db-4f6c-4142-8a44-ea79132d5208"
    end

    machine_image "lucid5d" do
      description "Ubuntu 10.04 (Lucid Lynx)"
      url "http://dlc.wakame.axsh.jp.s3.amazonaws.com/demo/vmimage/ubuntu-lucid-kvm-md-32.raw.gz"
      sha246 "faa9c75fdfd9cce3b1bebfd5813e5f945e82f9b1117e521d7b1151641bc52ada"
      md5 "1f841b195e0fdfd4342709f77325ce29"
      size "152659010"
      allocated "657457152"
      root_device "uuid:148bc5df-3fc5-4e93-8a16-7328907cb1c0"
    end

    # Register a network
    execute "vdc-manage network add --uuid nw-demo1" do
      command <<-CMD
        /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage network add \
          --uuid nw-demo1 \
          --ipv4-network #{node['wakame-vdc']['lan']['network']} \
          --prefix #{node['wakame-vdc']['lan']['prefix']} \
          --ipv4-gw #{node['wakame-vdc']['lan']['gateway']} \
          --dns #{node['wakame-vdc']['lan']['dns']} \
          --account-id a-shpoolxx \
          --display-name "demo network"
      CMD
      action :nothing
      notifies :run, 'execute[vdc-manage network dhcp addrange nw-demo1]', :immediately
    end

    execute "vdc-manage network dhcp addrange nw-demo1" do
      command <<-CMD
        /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage network dhcp addrange nw-demo1 #{node['wakame-vdc']['lan']['dhcp']['range']}
      CMD
      action :nothing
      notifies :run, 'execute[vdc-manage network reserve gateway nw-demo1]', :immediately
    end

    execute "vdc-manage network reserve gateway nw-demo1" do
      command <<-CMD
        /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage network reserve nw-demo1 --ipv4 #{node['wakame-vdc']['lan']['gateway']}
      CMD
      action :nothing
      notifies :run, 'execute[vdc-manage macrange add mr-demomacs]', :immediately
    end

    execute "vdc-manage macrange add mr-demomacs" do
      command <<-CMD
        /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage macrange add 525400 1 ffffff --uuid mr-demomacs
      CMD
      action :nothing
      notifies :run, 'execute[vdc-manage network dc add public --uuid dcn-public]', :immediately
    end

    execute 'vdc-manage network dc add public --uuid dcn-public' do
      command <<-CMD.gsub(/^ {8}/,'')
        /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage -e <<CSET
          network dc add public --uuid dcn-public --description "the network instances are started in"
          network dc add-network-mode public securitygroup
          network forward nw-demo1 public
        CSET
      CMD
      action :nothing
    end

    mysql_database "wakame_dcmgr_gui" do
      connection(
        host:     'localhost',
        username: 'root',
        password: node['mysql']['server_root_password']
      )
      action :create
      notifies :run, 'execute[dcmgr_gui rake db:init]', :immediately
    end

    execute 'dcmgr_gui rake db:init' do
      cwd "/opt/axsh/wakame-vdc/frontend/dcmgr_gui"
      command <<-CMD
        /opt/axsh/wakame-vdc/ruby/bin/rake db:init
      CMD
      action :nothing
      notifies :run, 'execute[gui-manage account add a-shpoolxx]', :immediately
    end

    execute 'gui-manage account add a-shpoolxx' do
      command <<-CMD.gsub(/^ {8}/,'')
        /opt/axsh/wakame-vdc/frontend/dcmgr_gui/bin/gui-manage -e <<CSET
          account add --name default --uuid a-shpoolxx
          user add --name "demo user" --uuid u-demo --password demo --login-id demo
          user associate u-demo --account-ids a-shpoolxx
        CSET
      CMD
      action :nothing
    end

    service 'rabbitmq-server' do
      action [:enable, :start]
    end

    template "/etc/default/vdc-dcmgr" do
      source "vdc-dcmgr.erb"
      variables bind_addr: node['wakame-vdc']['dcmgr']['address'],
        port: node['wakame-vdc']['dcmgr']['port']
    end

    template "/etc/default/vdc-collector" do
      source "vdc-collector.erb"
      variables amqp_addr: node['wakame-vdc']['amqp']['address'],
        amqp_port: node['wakame-vdc']['amqp']['port']
    end

    template "/etc/default/vdc-hva" do
      source "vdc-hva.erb"
      variables node_id: 'demo1',
        amqp_addr: node['wakame-vdc']['amqp']['address'],
        amqp_port: node['wakame-vdc']['amqp']['port']
      notifies :run, 'execute[vdc-manage host add demo1]', :immediately
    end

    template "/etc/default/vdc-webui" do
      source "vdc-webui.erb"
      variables bind_addr: node['wakame-vdc']['webui']['address'],
        port: node['wakame-vdc']['webui']['port']
    end

    service 'vdc-dcmgr' do
      provider Chef::Provider::Service::Upstart
      action [:enable, :start]
    end

    service 'vdc-collector' do
      provider Chef::Provider::Service::Upstart
      action [:enable, :start]
    end

    service 'vdc-hva' do
      provider Chef::Provider::Service::Upstart
      action [:enable, :start]
    end

    service 'vdc-webui' do
      provider Chef::Provider::Service::Upstart
      action [:enable, :start]
    end

  end
end
