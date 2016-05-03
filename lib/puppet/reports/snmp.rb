require 'puppet'
require 'yaml'
require 'puppet/util/puppetdb'
require 'puppetdb/connection'

begin
  require 'snmp'
  include SNMP
rescue LoadError => e
  Puppet.info "You need the `snmp` library to use the snmp report"
end

Puppet::Reports.register_report(:snmp) do

  # connect to PuppetDB to get ip for the node
  PuppetDB::Connection.check_version

  configfile = File.join(File.dirname(Puppet.settings[:config]), "snmp.yaml")
  raise Puppet::ParseError, "SNMP report config file #{configfile} not readable" unless File.exist?(configfile)
  config = YAML.load_file(configfile)
  SNMP_SERVER  = config[:snmp_server]
  SNMP_VERSION = config[:snmp_version]
  
  PUPPETLABS_OID = "1.3.6.1.4.1.34380"
  PUPPET_ENVIRONMENT_OID = "1.3.6.1.4.1.34380.1.1.12"
  HOSTNAME_OID = "1.3.18.0.2.4.486"
  SPECIFIC_TRAP_ID = 42 # Randomly chosen to represent agent run failure

  desc <<-DESC
  Send notification of failed reports to an SNMP server.
  DESC

  def process
    if self.status == 'failed'
      Puppet.debug "Sending status for #{self.host} to SNMP server #{SNMP_SERVER} at #{Time.now.asctime} due to run status #{self.status} on #{self.configuration_version} in #{self.environment}"
      
      system_uptime = 12345 # Dummy value because we must provide one
      
      if SNMP_VERSION =~ /v2/
        SNMP::Manager.open(:Host => SNMP_SERVER, :Version => :SNMPv2c) do |snmp|
          snmp.trap_v2(system_uptime, PUPPETLABS_OID, trap_options)
        end
      else
        SNMP::Manager.open(:Host => SNMP_SERVER, :Version => :SNMPv1) do |snmp|
          snmp.trap_v1(PUPPETLABS_OID, ip_address, :enterpriseSpecific, SPECIFIC_TRAP_ID, system_uptime, trap_options)
        end
      end
    end
  end
  
private
  def ip_address
    @ip_address ||= begin
      uri = URI(Puppet::Util::Puppetdb.config.server_urls.first)
      puppetdb = PuppetDB::Connection.new(uri.host, uri.port, uri.scheme == 'https')
      parser = PuppetDB::Parser.new
      query = parser.facts_query("fqdn='#{self.host}'", ['ipaddress'])
      results = puppetdb.query(:facts, query, :extract => :value).collect { |f| f['value'] }
      results[0]
    end
  end
  
  def trap_options
    {
      HOSTNAME_OID => self.host,
      PUPPET_ENVIRONMENT_OID => self.environment,
    }.map do |key, value|
      VarBind.new(key, OctetString.new(value))
    end
  end
end
