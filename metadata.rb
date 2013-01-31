maintainer       "Ryan J. Geyer"
maintainer_email "me@ryangeyer.com  "
license          "All rights reserved"
description      "Installs/Configures app_wordpress"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.rdoc'))
version          "0.0.2"

%w{db_mysql mysql web_apache nginx php5}.each do |dep|
  depends dep
end

provides "app_wordpress[site]"

recipe "app_wordpress::default","Installs and configures some defaults for the app_wordpress cookbook"
recipe "app_wordpress::deploy","Installs an instance of wordpress for the specified vhost"
recipe "app_wordpress::update","Updates the instance of wordpress for the specified vhost to the latest version from wordpress.org"

%w{ubuntu debian centos rhel}.each do |supp|
  supports supp
end

attribute "app_wordpress",
  :display_name => "app_wordpress",
  :type => "hash"

attribute "app_wordpress/vhost_fqdn",
  :display_name => "Wordpress VHOST FQDN",
  :description => "The fully qualified domain name (FQDN) of the new vhost to deploy wordpress to.  Example www.apache.org",
  :required => "required",
  :recipes => ["app_wordpress::deploy","app_wordpress::update"]

attribute "app_wordpress/vhost_aliases",
  :display_name => "Wordpress VHOST Aliases",
  :description => "The possible hostname aliases (if any) for the vhost.  For instance to host the same content at www.yourdomain.com and yourdomain.com simply put \"yourdomain.com\" here.  Many values can be supplied, separated by spaces",
  :default => "",
  :recipes => ["app_wordpress::deploy"]

attribute "app_wordpress/db_pass",
  :display_name => "MySQL Database Password for this Wordpress instance",
  :description => "The password to access the MySQL database for this Wordpress instance",
  :required => "required",
  :recipes => ["app_wordpress::deploy"]

attribute "app_wordpress/webserver",
  :display_name => "Wordpress Web Server",
  :description => "The web server which will be serving pages for the wordpress instance",
  :choice => ["nginx","apache2"],
  :required => "required"