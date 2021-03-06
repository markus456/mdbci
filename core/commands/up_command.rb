# frozen_string_literal: true

require_relative 'base_command'
require_relative '../docker_manager'
require_relative '../models/configuration'
require_relative '../services/shell_commands'
require_relative '../services/machine_configurator'
require_relative 'generate_command'

# The command sets up the environment specified in the configuration file.
class UpCommand < BaseCommand
  include ShellCommands

  def self.synopsis
    'Setup environment as specified in the configuration.'
  end

  VAGRANT_NO_PARALLEL = '--no-parallel'

  # Checks that all required parameters are passed to the command
  # and set them as instance variables.
  #
  # @raise [ArgumentError] if unable to parse arguments.
  def setup_command
    if @args.empty? || @args.first.nil?
      raise ArgumentError, 'You must specify path to the mdbci configuration as a parameter.'
    end
    @specification = @args.first
    @attempts = if @env.attempts.nil?
                  5
                else
                  @env.attempts.to_i
                end
    @box_manager = @env.boxes
    @network_configs = {}
    @machine_configurator = MachineConfigurator.new(@ui)
  end

  # Method parses up command configuration and extracts path to the
  # configuration and node name if specified.
  #
  # @raise [ArgumentError] if path to the configuration is invalid
  def parse_configuration
    config, node = Configuration.parse_spec(@specification)
    if node.empty?
      @ui.info "Node #{node} is specified in #{@specification}"
    else
      @ui.info "Node is not specified in #{@specification}"
    end
    [config, node]
  end

  # Generate docker images, so they will not be loaded during production
  #
  # @param config [Hash] configuration read from the template
  # @param nodes_directory [String] path to the directory where they are located
  def generate_docker_images(config, nodes_directory)
    @ui.info 'Generating docker images.'
    config.each do |node|
      next if node[1]['box'].nil?
      DockerManager.build_image("#{nodes_directory}/#{node[0]}", node[1]['box'])
    end
  end

  # Generate flags based upon the configuration
  #
  # @param provider [String] name of the provider to work with
  # @return [String] flags that should be passed to Vagrant commands
  def generate_vagrant_run_flags(provider)
    flags = []
    flags.push(VAGRANT_NO_PARALLEL) if %w[aws docker].include?(provider)
    flags.uniq.join(' ')
  end

  # Identify whether we should show idle notifications or not
  #
  # @param node_name [String] name of the box that is being brought up.
  # @return [Boolean] true if box or configuration is slow.
  def show_idle_notifications(node_name = '')
    box_names = @config.box_names(node_name)
    box_names.any? do |box_name|
      box = @box_manager.getBox(box_name)
      box.key?('extra_vagrant_output')
    end
  end

  # Check whether node is running or not.
  #
  # @param node [String] name of the node to get status from.
  # @return [Boolean]
  def node_running?(node)
    status = `vagrant status #{node}`.split("\n")[2]
    @ui.info "Node '#{node}' status: #{status}"
    if status.include? 'running'
      @ui.info "Node '#{node}' is running."
      true
    else
      @ui.error "Node '#{node}' is not running."
      false
    end
  end

  # Check whether chef was successfully installed on the machine or not
  #
  # @param node [String] name of the node to check.
  # @return [Boolean]
  def chef_installed?(node)
    command = "vagrant ssh #{node} -c "\
              '"test -e /var/chef/cache/chef-stacktrace.out && printf FOUND || printf NOT_FOUND"'
    chef_stacktrace = `#{command}`
    if chef_stacktrace == 'FOUND'
      @ui.error "Chef on node '#{node}' was installed with error."
      false
    else
      @ui.info "Chef on node '#{node}' was successfully installed."
      true
    end
  end

  # Check whether chef have provisioned the server or not
  #
  # @param node [String] name of the node to check
  # return [Boolean]
  def node_provisioned?(node)
    command = "vagrant ssh #{node} -c"\
                     '"test -e /var/mdbci/provisioned && printf PROVISIONED || printf NOT"'
    provision_file = `#{command}`
    if provision_file == 'PROVISIONED'
      @ui.info "Node '#{node}' was configured."
      true
    else
      @ui.error "Node '#{node}' is not configured."
      false
    end
  end

  # Split list of nodes between running and halt ones
  # @param nodes [Array<String] name of nodes to check
  # @return [Array<String>, Array<String>] nodes that are running and those that are not
  def running_and_halt_nodes(nodes)
    nodes.partition do |node|
      node_running?(node)
    end
  end

  # Check that all specified nodes are configured and brought up.
  # Return list of nodes that needs to be re-created or re-provisioned.
  #
  # @param nodes [Array<String>] name of nodes that should be checked.
  # @return [Array<String>, Array<String>] nodes to recreate and nodes to re-provision.
  def check_nodes(nodes)
    recreate = []
    reconfigure = []
    nodes.each do |node|
      unless node_running?(node) && chef_installed?(node)
        recreate.push node
        next
      end
      reconfigure.push(node) unless node_provisioned?(node)
    end
    [recreate, reconfigure]
  end

  # Configure nodes using the chef-solo and their respected role
  # @param nodes [Array<String>] names of nodes that should be configured
  # @return [Array<String>] list of nodes that we not successfully configured
  def configure_nodes(nodes)
    nodes.reject do |node|
      configure(node)
    end
  end

  # Configure single node using the chef-solo respected role
  # @param nde[String] name of the node
  # @return [Boolean] whether we were successfull or not
  def configure(node)
    @network_configs[node] = get_node_network_config(node, @config, @env)
    solo_config = "#{node}-config.json"
    role_file = GenerateCommand.role_file_name(@config.path, node)
    unless File.exist?(role_file)
      @ui.info("Machine '#{node}' should not be configured. Skipping")
      return true
    end
    extra_files = [
      [role_file, "roles/#{node}.json"],
      [GenerateCommand.node_config_file_name(@config.path, node), "configs/#{solo_config}"]
    ]
    @machine_configurator.configure(@network_configs[node], solo_config, extra_files)
    node_provisioned?(node)
  end

  # Bring up whole configuration or a machine up.
  #
  # @param provider [String] name of the provider to use.
  # @param node [String] node name to bring up. It can be empty if we need to bring
  # the whole configuration up.
  # @return [Array<String>] list of node names that should be checked
  def bring_up_machines(provider, node_name = '')
    @ui.info "Bringing up #{(node_name.empty? ? 'configuration ' : 'node ')} #{@specification}"
    vagrant_flags = generate_vagrant_run_flags(provider)
    run_command_and_log("vagrant up #{vagrant_flags} --provider=#{provider} #{node_name}",
                        show_idle_notifications(node_name))
  end

  # Destroy and then create specified nodes.
  #
  # @param nodes [Array<String>] list of nodes that should be re-created
  # @param provider [String] name of virtual box provider
  def recreate(nodes, provider)
    nodes.each do |node|
      @ui.info "Destroying '#{node}' node."
      run_command_and_log("vagrant destroy --force #{node}")
      bring_up_machines(provider, node)
    end
  end

  # Check that nodes were brougt up and configrued. If they were not
  # configured, then try to reconfigure them
  #
  # @param nodes_to_check [Array<String>] list of nodes to check
  # @return [Array<String>] list of nodes that are still misconfigured.
  def check_and_configure_nodes(nodes_to_check)
    running_nodes, halt_nodes = running_and_halt_nodes(nodes_to_check)
    unconfigured_nodes = configure_nodes(running_nodes)
    halt_nodes.concat(configure_nodes(unconfigured_nodes))
  end

  # Destroy all existing nodes and setup configuration
  #
  # @param config [Configuration] configuration that should be run
  # @param node [String] name of the node to bring up
  # @return [Array<String>] list of nodes that should be checked
  def setup_nodes(config, node = '')
    generate_docker_images(config.template, '.') if config.provider == 'docker'
    @ui.info 'Destroying existing nodes.'
    run_command_and_log("vagrant destroy --force #{node}")
    bring_up_machines(config.provider)
    nodes_to_check = if node.empty?
                       config.node_names
                     else
                       [node]
                     end
    check_and_configure_nodes(nodes_to_check)
  end

  # Try to fix nodes that were not brought up. Try to reconfigure them.
  # If any operation fails, try to repair them several times.
  #
  # @param nodes_to_fix [Array<String>] list of node names to fix.
  # @param nodes_provider [String] name of the provider.
  # @return [Boolean]
  def fix_nodes(nodes_to_fix, nodes_provider)
    @attempts.times do |attempt|
      @ui.info "Checking that nodes were brought up. Attempt #{attempt + 1}"
      recreate(nodes_to_fix, nodes_provider)
      nodes_to_fix = check_and_configure_nodes(nodes_to_fix)
      break if nodes_to_fix.empty?
    end

    broken_nodes, unconfigured_nodes = check_nodes(nodes_to_fix)
    unless broken_nodes.empty? && unconfigured_nodes.empty?
      @ui.error "The following nodes were not brought up: #{broken_nodes.join(', ')}"
      @ui.error "The following nodes were not configured: #{unconfigured_nodes.join(', ')}"
      return false
    end
    true
  end

  # Provide information for the end-user where to find the required information
  # @param working_directory [String] path to the current working directory
  # @param config_path [String] path to the configuration
  # @param node [String] name of the node that was brought up
  def generate_config_information(working_directory, config_path, node = '')
    network_config_path = "#{config_path}#{Configuration::NETWORK_FILE_SUFFIX}"
    @ui.info 'All nodes were brought up and configured.'
    @ui.info "DIR_PWD=#{working_directory}"
    @ui.info "CONF_PATH=#{config_path}"
    @ui.info "Generating #{network_config_path} file"
    File.open(network_config_path, 'w') do |file|
      @network_configs.each_pair do |node_name, config|
        config.each_pair do |key, value|
          file.puts("#{node_name}_#{key}=#{value}")
        end
      end
    end
  end

  # Switch to the working directory, so all Vagrant commands will
  # be run in corresponding directory. The directory will be returned
  # to the invoking one after the completion.
  #
  # @param directory [String] path to the directory to switch to.
  def run_in_directory(directory)
    current_dir = Dir.pwd
    Dir.chdir(directory)
    yield
    Dir.chdir(current_dir)
  end

  def execute
    begin
      setup_command
      @config, node = parse_configuration
    rescue ArgumentError => error
      @ui.warning error.message
      return ARGUMENT_ERROR_RESULT
    end
    run_in_directory(@config.path) do
      nodes_to_fix = setup_nodes(@config, node)
      return ERROR_RESULT unless fix_nodes(nodes_to_fix, @config.provider)
    end
    generate_config_information(Dir.pwd, @config.path, node)
    SUCCESS_RESULT
  end
end
