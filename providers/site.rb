#  Copyright 2011-2012 Ryan J. Geyer
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

def update_latest_version()
  require 'net/http'
  require 'uri'

  url = URI.parse('http://api.wordpress.org/core/version-check/1.5/')
  req = Net::HTTP::Get.new(url.path)
  res = Net::HTTP.start(url.host, url.port) { |http|
    http.request(req)
  }

  latest_version_num = res.body.split("\n")[3]
  latest_version_dir = "#{node[:app_wordpress][:version_store_path]}/#{latest_version_num}"

  if !::File.exist? latest_version_dir
    d = directory latest_version_dir do
      recursive true
      action :nothing
    end

    b = bash "Downloading Wordpress #{latest_version_num}" do
      code "wget -q -O #{latest_version_dir}/wordpress.tar.gz http://wordpress.org/wordpress-#{latest_version_num}.tar.gz"
      action :nothing
    end

#    remote_file "#{latest_version_dir}/wordpress.tar.gz" do
#      source "http://wordpress.org/wordpress-#{latest_version_num}.tar.gz"
#      backup false
#    end

    l = link "#{node[:app_wordpress][:version_store_path]}/latest" do
      to latest_version_dir
      action :nothing
    end

    # We need to do this "right now" because we're using this like a blocking method call
    d.run_action(:create)
    b.run_action(:run)
    l.run_action(:create)
  end
end

def current_version(path)
  version = nil
  regex = /^\$wp_version\s*=\s*'(.*)'/
  ver_file = ::File.new("#{path}/wp-includes/version.php", "r")
  ver_file.each_line do |line|
    match = regex.match line
    if match && match[1] then version = match[1] end
  end
  return version
end

action :install do
  require 'net/http'
  require 'uri'

  fqdn = new_resource.fqdn
  aliases = new_resource.aliases
  db_pass = new_resource.db_pass

  underscored_fqdn = fqdn.gsub(".", "_")
  underscored_fqdn = underscored_fqdn.gsub("-", "_")
  underscored_fqdn_16 = underscored_fqdn.slice(0..15)
  vhost_dir = "#{node[:app_wordpress][:content_dir]}/#{fqdn}"
  install_dir = "#{vhost_dir}/htdocs"

  Chef::Log.info "Installing a wordpress instance for vhost #{fqdn}"

  # This step creates the directory, so lets do that first
  if new_resource.webserver == "apache2"
    web_apache_enable_vhost fqdn do
      fqdn fqdn
      aliases aliases
      allow_override "FileInfo"
    end
  else
    nginx_enable_vhost fqdn do
      cookbook "app_wordpress"
      template "nginx.conf.erb"
      fqdn fqdn
      aliases aliases
    end
  end

  mysql_database "Create database for this wordpress instance" do
    host "localhost"
    username "root"
    database underscored_fqdn
    action :create_db
  end

  # Grant permissions to the mysql database for this wordpress instance
  db_mysql_set_privileges "Create and authorize wordpress MySQL user" do
    preset "user"
    username underscored_fqdn_16
    password db_pass
    db_name underscored_fqdn
  end

  unless ::File.directory? install_dir

    update_latest_version()

    execute "untar wordpress" do
      cwd "#{node[:app_wordpress][:version_store_path]}/latest"
      command "tar --strip-components 1 -zxf wordpress.tar.gz -C #{install_dir}"
    end

    url = URI.parse('http://api.wordpress.org/secret-key/1.1/')
    req = Net::HTTP::Get.new(url.path)
    res = Net::HTTP.start(url.host, url.port) { |http|
      http.request(req)
    }

    # TODO: By leaving this in this block, if a different DB password is provided, things will break.
    # May want to reconsider the unless ::File.directory? above
    template "#{install_dir}/wp-config.php" do
      source "wp-config.php.erb"
      mode 0400
      owner node[:app_wordpress][:content][:username]
      group node[:app_wordpress][:content][:username]
      variables(
        :db_name => underscored_fqdn,
        :username => underscored_fqdn_16,
        :auth_unique_keys => res.body,
        :db_pass => db_pass,
        :db_host => "localhost"
      )
    end

  end

  if new_resource.webserver == "nginx"
    bash "Downloading nginx compatibility plugin" do
      cwd "#{install_dir}/wp-content/plugins"
      code <<-EOF
wget -q -O nginx-compatibility.zip http://downloads.wordpress.org/plugin/nginx-compatibility.0.2.5.zip
unzip nginx-compatibility.zip
rm -rf nginx-compatibility.zip
      EOF
      not_if do
        ::File.directory? "#{install_dir}/wp-content/plugins/nginx-compatibility"
      end
    end
  end

  right_link_tag "vhost:#{fqdn}=#{new_resource.webserver}+wordpress" do
    action :publish
  end
end

action :update do
  fqdn = new_resource.fqdn
  tempDir = "/tmp/wordpress"
  install_dir = "#{node[:app_wordpress][:content_dir]}/#{fqdn}/htdocs"
  wpcontent_dir = "#{install_dir}/wp-content"

  if ::File.directory? wpcontent_dir
    update_latest_version()
    version = current_version(install_dir)
    wp_versions = ::Dir.entries(node[:app_wordpress][:version_store_path]).sort
    if version == wp_versions.last
      Chef::Log.info "#{fqdn} is already updated to version #{wp_versions.last} of wordpress, no update occurred.."
    else
      directory tempDir do
        recursive true
        action :create
      end

      remote_file "#{tempDir}/latest.tar.gz" do
        source "http://wordpress.org/latest.tar.gz"
        backup false
      end

      execute "untar wordpress" do
        cwd tempDir
        command "tar --strip-components 1 -zxf latest.tar.gz -C #{install_dir}"
      end

      directory tempDir do
        recursive true
        action :delete
      end
    end
  else
    raise "#{fqdn} does not appear to be a wordpress site, no update performed.  You may need to run the :install action of app_wordpress[site] first."
  end

end