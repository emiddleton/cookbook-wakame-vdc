require 'uri'

define :machine_image,
  format: 'gz',
  service_type: 'std',
  account_id: 'a-shpoolxx' do

  uri = URI.parse(params[:url])
  file_name = File.basename(uri.path)

  remote_file "/var/lib/wakame-vdc/images/#{file_name}" do
    source params[:url]
    checksum params[:sha246]
    notifies :run, "execute[vdc-manage backupobject add --uuid bo-#{params[:name]}]", :immediately
  end

  execute "vdc-manage backupobject add --uuid bo-#{params[:name]}" do
    command <<-CMD
      /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage backupobject add \
        --uuid bo-#{params[:name]} \
        --display-name "#{params[:description]} root partition" \
        --storage-id bkst-local \
        --object-key #{file_name} \
        --size #{params[:size]} \
        --allocation-size #{params[:allocated]} \
        --container-format #{params[:format]} \
        --checksum #{params[:md5]}
    CMD
    action :nothing
    notifies :run, "execute[vdc-manage image add local bo-#{params[:name]}]", :immediately
  end

  execute "vdc-manage image add local bo-#{params[:name]}" do
    command <<-CMD
      /opt/axsh/wakame-vdc/dcmgr/bin/vdc-manage image add local bo-#{params[:name]} \
        --account-id #{params[:account_id]} \
        --uuid wmi-#{params[:name]} \
        --service-type #{params[:service_type]} \
        --root-device #{params[:root_device]} \
        --display-name #{params[:name]}
    CMD
    action :nothing
  end

end
