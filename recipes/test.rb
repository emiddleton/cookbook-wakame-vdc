template "/opt/axsh/wakame-vdc/dcmgr/spec/minimal_dcmgr.conf" do
  source 'minimal_dcmgr.conf.erb'
  variables user: 'root',
    password: node['mysql']['server_root_password']
end

mysql_database "wakame_dcmgr_test" do
  connection(
    host:     'localhost',
    username: 'root',
    password: node['mysql']['server_root_password']
  )
  action :create
  notifies :run, 'execute[dcmgr rake test:db:up]', :immediately
end

execute "dcmgr rake test:db:up" do
  cwd "/opt/axsh/wakame-vdc/dcmgr"
  command "/opt/axsh/wakame-vdc/ruby/bin/rake test:db:up"
  action :nothing
end
