require 'optparse'

module Clorun
  class Options
    attr_reader :target, :config, :name, :test, :features
    def initialize(argv)
      @target = "all"
      @test = "run_all"
      puts "#******#*************#*********#***********#******"
      puts "**********#*****  CLOUD RUNNER  *****#*****#******"
      puts "***#******************#**************#******#*****"
      parse(argv)
      @features = argv
    end
  private
    def parse(argv)
      OptionParser.new do |opts|
        opts.banner = "Usage: clorun -c CONFIG_FOLDER [options] features..."
        opts.on("-t", "--target TARGET", [:deploy, :test, :term, :reconf, :all], "Target usage (deploy|test|term|all)") do |t|
          @target = t
        end
        opts.on("-c", "--config TEMPLATES_FOLDER", String, "Relative path of folder that contains template files (in clorun/templates directory)") do |conf|
          @config = conf
        end
        opts.on("-n", "--name NAME", String, "Name of environment") do |name|
          @name = name
        end
        opts.on("-r", "--rake_target TARGET", [:run, :run_all, :wiki], "Rake target to run cucumber tests (run|run_all|wiki)") do |r|
          @test = r
        end
        opts.on("-h", "--help", "Show this message") do
          puts opts
          exit
        end
        begin
          argv = ["-h"] if argv.empty?
          opts.parse!(argv)
        rescue OptionParser::ParseError => e
          STDERR.puts e.message, "\n", opts
          exit(-1)
        end
      end
    end
  end
end

