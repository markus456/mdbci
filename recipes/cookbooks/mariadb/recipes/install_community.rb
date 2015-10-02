require 'shellwords'

include_recipe "mariadb::mdbcrepos"

# BUG: #6309 Check if SElinux already disabled!
# Turn off SElinux
if node[:platform] == "centos" and node["platform_version"].to_f >= 6.0
#  execute "SElinux status" do
#  	command "/usr/sbin/selinuxenabled && echo enabled || echo disabled"
#	returns [1, 0]
#  end
  execute "Turn off SElinux" do
    #if 1
      command "/usr/sbin/setenforce 0"
    #end
  end
  cookbook_file 'selinux.config' do
    path "/etc/selinux/config"
    action :create
  end
end  # Turn off SElinux

# Remove mysql-libs for MariaDB-Server 5.1
if node['mariadb']['version'] == "5.1"
  execute "Remove mysql-libs for MariaDB-Server 5.1" do
    if node[:platform] == "ubuntu" and node[:platform] == "debian" 
      command "apt-get -y remove mysql-libs"
    elsif node[:platform] == "centos"
      command "yum remove -y mysql-libs"
    end
  end
end

# Install packages
case node[:platform_family]
when "suse"
  execute "install" do
    command "zypper -n install --from mariadb MariaDB-server MariaDB-client &> /vagrant/log"
  end
when "debian"
  package 'mariadb-server'
  package 'mariadb-client'
when "windows"
  windows_package "MariaDB" do
    source "#{Chef::Config[:file_cache_path]}/mariadb.msi"
    installer_type :msi
    action :install
  end
else
  package 'MariaDB-server'
  package 'MariaDB-client'
end

# Config /etc/my.cnf and /etc/mysql/my.cnf.d/server.cnf files
case node[:platform_family]
  when "debian", "ubuntu"

    bash 'Config mariadb /etc/mysql/my.cnf file' do
    code <<-EOF
      sed -i "s/bind-address/#bind-address/g" /etc/mysql/my.cnf
      sed -i 's/#server-id\t\t= 1/server-id\t\t= #{Shellwords.escape(node['mariadb']['server_id'])}/g' /etc/mysql/my.cnf
      EOF
    end

  when "rhel", "fedora", "centos", "suse"

    bash 'Config MariaDB /etc/my.cnf file' do
    code <<-EOF
      sed -i 6"i\n" /etc/my.cnf
      sed -i 7"i[mysqld]" /etc/my.cnf
      sed -i 8"i#bind-address = 127.0.0.1" /etc/my.cnf
      sed -i 9"iserver-id = #{Shellwords.escape(node['mariadb']['server_id'])}" /etc/my.cnf
    EOF
    end

    bash 'Config MariaDB /etc/my.cnf.d/server.cnf file' do
    code <<-EOF
      sed -i 13"iserver-id = #{Shellwords.escape(node['mariadb']['server_id'])}" /etc/my.cnf.d/server.cnf
      EOF
    end

end # server.cnf block
