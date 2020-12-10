# This recipe installs the base environment needed for a WordPress site.
# In summary, it:
#
# 1. Installs the minimum required packages, which are:
#     - Apache2 (v 2.4)
#     - PHP (v7)
#     - PHP's MySQL connector
#     - PHP GD for image manipulation
#
# 2. Makes sure the variables defined in the OpsWorks console are readable
#    in PHP.
#
# 3. Sets those same variables as ENV variables so we can use them on scripts
#    and other tasks.
#
# 4. Creates the Apache VirtualHost for the site. It uses the default template
#    which can be found in the `apache2` cookbook in this repo.
#
# This is all it does. Other considerations (such as giving it EFS support
# for multi-server setups or installing a MySQL/MariaDB server for single
# server setups) should be done in other recipes.
#
# The actual deployment of the application code is done in the `deploy` recipe,
# since we don't need to build the entire environment with each deploy.
#
# There are some considerations that should be taken into account with this
# recipe:
#
# a) It is intended solely for Opsworks, not for local installations.
# b) It has only been tested with Ubuntu 16.04 LTS. It *should* work with other
#    operating systems, but it probably would take some additional work.
#
# — Ivan Vásquez (ivan@simian.co) / Jan 29, 2017


# Initial setup: just a couple vars we need
app = search(:aws_opsworks_app).first
app_path = "/srv/#{app['shortname']}"

# 1. Installing some required packages
include_recipe 'apt::default'
include_recipe 'php::default'
include_recipe 'php::module_mysql'
include_recipe 'php::module_gd'
include_recipe 'apache2::mod_php'
include_recipe 'apache2::mod_ssl'
include_recipe 'apache2::mod_expires'
include_recipe 'apache2::mod_ext_filter'

package 'Install PHP cURL' do
  package_name 'php-curl'
end

package 'Memcached' do
  package_name 'php-memcached'
end

package 'Mailer' do
  package_name 'sendmail'
end

execute "install_htop" do
  command "sudo apt-get install -y htop"
  user "root"
  action :run
end

# 2. Set the environment variables for PHP
ruby_block "insert_env_vars" do
  block do
    file = Chef::Util::FileEdit.new('/etc/apache2/envvars')
    app['environment'].each do |key, value|
      Chef::Log.info("Setting apache envvar #{key}= #{key}=\"#{value}\"")
      file.insert_line_if_no_match /^export #{key}\=/, "export #{key}=\"#{value}\""
      file.write_file
    end
  end
end

# Make sure PHP can read the vars
ruby_block "php_env_vars" do
  block do
    file = Chef::Util::FileEdit.new('/etc/php/7.0/apache2/php.ini')
    Chef::Log.info("Setting the variable order for PHP")
    file.search_file_replace_line /^variables_order =/, "variables_order = \"EGPCS\""
    file.write_file
  end
end

# 3. map the environment_variables node to ENV variables
ruby_block "insert_env_vars" do
  block do
    file = Chef::Util::FileEdit.new('/etc/environment')
    app['environment'].each do |key, value|
      Chef::Log.info("Setting ENV variable #{key}= #{key}=\"#{value}\"")
      file.insert_line_if_no_match /^#{key}\=/, "#{key}=\"#{value}\""
      file.write_file
    end
  end
end

# source the file so we can use it right away if needed
bash "update_env_vars" do
  user "root"
  code <<-EOS
  source /etc/environment
  EOS
end

# 4. We create the site
web_app app['shortname'] do
  template 'web_app.conf.erb'
  allow_override 'All'
  server_name app['domains'].first
  server_port 80
  server_aliases app['domains'].drop(1)
  docroot app_path
  multisite app['environment']['MULTISITE']
end

# 6. Call the WordPress cron
cron 'wpcron' do
  minute '*'
  command "wget -q -O - #{app['domains'].first}/wp-cron.php?doing_wp_cron"
end