# LIBDIR = File.expand_path(File.join(File.dirname(__FILE__), "..", "lib"))
require 'rubygems'
require 'net/scp'
require 'ftools'
require 'fileutils'
require 'json/pure'
require 'thread'
require 'yaml'
require 'yaml/store'
require File.join(LIBDIR, 'options')
require File.join(File.dirname(__FILE__), 'amazon')

DEBUG=:yes

class Hash
  def method_missing(meth, *args, &block)
    if args.size == 0
      self[meth.to_s] || self[meth.to_sym]
    end
  end

  def has?(key)
    self[key] && !self[key].to_s.empty?
  end

  def does_not_have?(key)
    self[key].nil? || self[key].to_s.empty?
  end
end

module Clorun
  class Runner

    def initialize(argv)
      @options = Options.new(argv)
      configs_dir = File.join(LIBDIR, '..', 'configs')
      Dir.mkdir(configs_dir) unless File.exist?(configs_dir)
      @env_dir = File.join(configs_dir, @options.name)
      @templ_dir = File.join(LIBDIR, '..', 'templates', @options.config)
      @cfg = { :access_key_id => ENV['AMAZON_ACCESS_KEY_ID'], :secret_access_key => ENV['AMAZON_SECRET_ACCESS_KEY'] }
      @cfg.merge! YAML.load_file(File.join(@templ_dir, 'ec2.config'))
    end

    def run
      case @options.target
      when :deploy 
        deploy
      when :term
        term
      when :reconf
        reconfigure
      when :all
        deploy
        test
        term
      when :test
        test
      end
    end

private
    
    def deploy

      fatal("The environment with name '#{@options.name}' already exist. Exiting.") if File.exist?(@env_dir)
      Dir.mkdir(@env_dir)
      File.copy(File.join(@templ_dir, "solo.rb"), @env_dir)
      chef_tar_file = File.join(@templ_dir, "chef.tar.gz")
      File.copy(chef_tar_file, @env_dir) if File.exist?(chef_tar_file)
      jsons = Dir[File.join(@templ_dir, "*.json")]
      puts "Needed #{jsons.size} machines"
      names = jsons.map { |j| File.basename(j).scan(/(.*).json/).to_s }
      json_cfg = { :amount => jsons.size, :name => names }
      @cfg.merge! json_cfg
      env = Amazon.new(@cfg)

      instances = []
      @cfg.name.each do |name|
        instances << { :id => env.create_instance, :name => name }
      end
      threads = []
      mutex = Mutex.new
      instances.each do |i|
        threads << Thread.new(i) do |t_i|
          t_i.merge!(env.get_instance_info(t_i[:id]))
          print "For #{t_i.name} host an ip #{t_i.external_ip} is assigned.\n"
          mutex.synchronize do
            i.merge!(t_i)
          end
        end
      end
      threads.each { |t| t.join }
#          instances[ {:id, :external_host, :external_ip, :internal_host, :key, :name }, {...}, {...} ]

      prepare_jsons(instances, jsons)
      reconfigure
    end

    def term
      jsons = Dir[File.join(@env_dir, "*.json")]
      puts "#{jsons.size} machines set to be deleted"
      ids = []
      jsons.each do |f|
        buffer = JSON.parse(File.open(f).read)
        ids << buffer["cloud"]["id"]
      end
      env = Amazon.new(@cfg)
      env.terminate_instances(ids)
      FileUtils.rm_rf(@env_dir)
    end

    def reconfigure
      threads = []
      jsons = Dir[File.join(@env_dir, "*.json")]
      jsons.each do |f|
        buffer = JSON.parse(File.open(f).read)
        i = buffer.cloud
        threads << Thread.new(i) do |t_i|
          configure_hosts(t_i.ip, t_i.key, t_i.name)
          print "Access to #{t_i.name}:  ssh -i #{t_i.key} root@#{t_i.ip}\n"
        end
      end
      threads.each { |t| t.join }
    end

    def test
    end

    ##############################
    # Prepare json files from templates to run by Chef 
    # and copy them to configs dir 
    ###############################
    def prepare_jsons(instances, jsons)
      recipes = {}
      roles = {}
      ind = 0
      jsons.each do |f|
        buffer = JSON.parse(File.open(f).read)
        unless buffer["recipes"].nil?
          buffer["recipes"].each do |r|
            if recipes[r].nil?
              recipes[r] = [instances[ind][:external_ip]]
            else
              recipes[r] << instances[ind][:external_ip] unless recipes[r].include?(instances[ind][:external_ip])
            end
          end
        end
        unless buffer["roles"].nil?
          buffer["roles"].each do |r|
            if roles[r].nil?
              roles[r] = [instances[ind][:external_ip]]
            else
              roles[r] << instances[ind][:external_ip] unless roles[r].include?(instances[ind][:external_ip])
            end
          end
        end
        ind += 1
      end
      to_store = { "cloud" => { "roles" => roles, "recipes" => recipes }}
      ind = 0
      jsons.each do |f|
        host_specific = { "name" => File.basename(f).scan(/(.*).json/).to_s, "id" => instances[ind][:id], "key" => instances[ind][:key], "ip" => instances[ind][:external_ip] }
        to_store["cloud"].merge! host_specific
        buffer = JSON.parse(File.open(f).read)
        if buffer["cloud"].nil?
          buffer.merge! to_store
        else
          buffer["cloud"].merge! to_store["cloud"]
        end
        File.open(File.join(@env_dir, File.basename(f)), 'w') do |out|
          out.write(buffer.to_json)
        end
        ind += 1
      end
    end

    ############## CHEF #################
    def configure_hosts(ip, key, name)
      system("ssh-keygen -R " + ip)
      Net::SSH.start(ip, 'root', :keys => key) do |ssh|
        ssh.exec! "gem install --no-ri --no-rdoc ohai chef --source http://gems.opscode.com --source http://gems.rubyforge.org"
        files = ["#{name}.json", "solo.rb"]
        files << "chef.tar.gz" unless @cfg.chef_cooks_url
        puts "Files to upload: " + files.join(',')
        files.each do |file|
          ssh.scp.upload! File.join(@env_dir, file), '/root/'
        end
        ssh.exec!("wget -c -T 7 --tries=7 -o wget.log http://myserver/cooks.tar.gz && tar -xzf cooks.tar.gz -C /root")
        ssh.exec!("wget -c -T 7 --tries=7 -a wget.log #{@cfg.chef_cooks_url}") if @cfg.chef_cooks_url
        ssh.exec!("tar -xzf /root/chef.tar.gz -C /root")
        puts ssh.exec!("/usr/bin/chef-solo -c /root/solo.rb -j /root/#{name}.json")
      end
    end

    def fatal(msg, code=1)
      puts msg
      exit code
    end

  end
end
