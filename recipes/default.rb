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

  service 'iptables' do
    action [:enable, :start]
  end

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

    template "/etc/sysconfig/network-scripts/ifcfg-eth0" do
      source "ifcfg-eth0.erb"
      notifies :restart, "service[network]", :immediately
    end

    template "/etc/sysconfig/network-scripts/ifcfg-br0" do
      source "ifcfg-br0.erb"
      variables ipaddr: node['wakame-vdc']['lan']['router'],
        dns: node['wakame-vdc']['lan']['dns']
      notifies :restart, "service[network]", :immediately
    end

    iptables_rule "nat"

    template "/etc/wakame-vdc/dcmgr.conf" do
      source "dcmgr.conf.erb"
      variables password: node['mysql']['server_root_password']
    end
    template "/etc/wakame-vdc/hva.conf" do
      source "hva.conf.erb"
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

    # Register the HVA
    template "/etc/default/vdc-hva" do
      source "vdc-hva.erb"
      variables node_id: 'demo1'
      notifies :run, 'execute[vdc-manage host add demo1]', :immediately
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

    remote_file "/var/lib/wakame-vdc/images/ubuntu-lucid-kvm-md-32.raw.gz" do
      source "http://dlc.wakame.axsh.jp.s3.amazonaws.com/demo/vmimage/ubuntu-lucid-kvm-md-32.raw.gz"
      checksum "faa9c75fdfd9cce3b1bebfd5813e5f945e82f9b1117e521d7b1151641bc52ada"
      notifies :run, 'execute[vdc-manage backupobject add --uuid bo-lucid5d]', :immediately
    end

    execute "vdc-manage backupobject add --uuid bo-lucid5d" do
      command <<-CMD
        /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage backupobject add \
          --uuid bo-lucid5d \
          --display-name "Ubuntu 10.04 (Lucid Lynx) root partition" \
          --storage-id bkst-local \
          --object-key ubuntu-lucid-kvm-md-32.raw.gz \
          --size 149084 \
          --allocation-size 359940 \
          --container-format gz \
          --checksum 1f841b195e0fdfd4342709f77325ce29
      CMD
      action :nothing
      notifies :run, 'execute[vdc-manage image add local bo-lucid5d]', :immediately
    end

    execute "vdc-manage image add local bo-lucid5d" do
      command <<-CMD
        /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage image add local bo-lucid5d \
          --account-id a-shpoolxx \
          --uuid wmi-lucid5d \
          --root-device uuid:148bc5df-3fc5-4e93-8a16-7328907cb1c0 \
          --display-name "Ubuntu 10.04 (Lucid Lynx)"
      CMD
      action :nothing
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

    iptables_rule "vdc-webui"
  end
end
