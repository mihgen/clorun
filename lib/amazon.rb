require 'rubygems'
require 'AWS'
require 'pp'
require "socket"
require 'resolv'

module Clorun
  class Amazon

    def initialize(cfg)
      @cfg = cfg
      if @cfg.EC2_URL
        @ec2 = AWS::EC2::Base.new( :access_key_id => @cfg.access_key_id, :secret_access_key => @cfg.secret_access_key, :server => URI.parse(@cfg.EC2_URL).host )
      else
        # default server is US ec2.amazonaws.com
        @ec2 = AWS::EC2::Base.new( :access_key_id => @cfg.access_key_id, :secret_access_key => @cfg.secret_access_key )
      end
    end

    #def create_instances

      #instances = []

      ################# THREADING OR EC2 AUTOSCALING IS NEEDED ####################
      #@cfg.name.each do |name|
        #if DEBUG == :yes
          #instances << {:id => 'i-c87175a0', :external_host => 'ec2-204-236-196-145.compute-1.amazonaws.com', :external_ip => '204.236.196.145', :internal_host => 'domU-12-31-39-00-C6-48.compute-1.internal', :key => '/home/mike/keys/amazon/mscherbakov.pem', :name => name }
        #else 
          #instances << create_instance(@cfg.ami, @cfg.keypair, @cfg.instance_type, @cfg.availability_zone, @cfg.security_groups).merge!({ :key => @cfg.key, :name => name })
        #end
      #end
      #return instances
    #end

    def terminate_instances(instances)
      instances.each do |i|
        response = @ec2.terminate_instances(:instance_id => i)
        puts "Instance #{response.instancesSet.item[0].instanceId} is #{response.instancesSet.item[0].currentState.name}." 
        puts "Previous state was #{response.instancesSet.item[0].previousState.name}."
      end
    end

    def create_instance
      if DEBUG == :yes
        return {:id => 'i-c87175a0', :external_host => 'ec2-204-236-196-145.compute-1.amazonaws.com', :external_ip => '204.236.196.145', :internal_host => 'domU-12-31-39-00-C6-48.compute-1.internal', :key => '/home/mike/keys/amazon/mscherbakov.pem' }
      end
#        instances << create_instance(@cfg.ami, @cfg.keypair, @cfg.instance_type, @cfg.availability_zone, @cfg.security_groups).merge!({ :key => @cfg.key, :name => name })
      response = @ec2.run_instances( :image_id => @cfg.ami, :key_name => @cfg.keypair, :instance_type => @cfg.instance_type, :availability_zone => @cfg.availability_zone, :security_group => @cfg.security_groups )
      instance_id = response.instancesSet.item[0].instanceId
      puts "Created instance: " + instance_id
      return instance_id
    end

    def get_instance_info(instance_id)
      puts "Waiting for instance #{instance_id} to start"
      sleep 5

      if @cfg.EC2_URL
        ec2 = AWS::EC2::Base.new( :access_key_id => @cfg.access_key_id, :secret_access_key => @cfg.secret_access_key, :server => URI.parse(@cfg.EC2_URL).host )
      else
        # default server is US ec2.amazonaws.com
        ec2 = AWS::EC2::Base.new( :access_key_id => @cfg.access_key_id, :secret_access_key => @cfg.secret_access_key )
      end
      while true do
        print "."
        sleep 2
        response = ec2.describe_instances(:instance_id => instance_id)
        item = response.reservationSet.item[0].instancesSet.item[0]
        if item.instanceState.name == "running"
          print "\n"
#          logger.info "Instance running, fetching hostname/ip data"

          instance = {}
          instance[:id] = instance_id
          instance[:external_host] = item.dnsName
          instance[:external_ip] = IPSocket.getaddress(item.dnsName)
          instance[:internal_host] = item.privateDnsName
#          setup_ssh_config

          puts "Instance #{instance_id} #{instance[:external_ip]} is running."

          # logger.info "check if sshd has started"
          #
          begin
            timeout(300) do
              s = TCPSocket.new(instance[:external_ip], 22)
              s.close
            end
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            puts "Failed to connect to #{instance[:external_ip]}:22, retrying in 3 seconds.."
            sleep 3
            retry
          rescue Timeout::Error, StandardError
            puts "Could not connect to #{instance[:external_ip]}:22, exiting"
            break
          end

          break
        end
      end
      return instance.merge!({ :key => @cfg.key })
    end
  end
end

