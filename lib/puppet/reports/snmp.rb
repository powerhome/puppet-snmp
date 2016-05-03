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

  desc <<-DESC
  Send notification of failed reports to an SNMP server.
  DESC

  def process
    if self.status == 'failed'
      Puppet.debug "Sending status for #{self.host} to SNMP server #{SNMP_SERVER} at #{Time.now.asctime} due to run status #{self.status} on #{self.configuration_version} in #{self.environment}"
      hostname_bind = VarBind.new("1.3.18.0.2.4.486", OctetString.new(self.host))
      puppet_env_bind = VarBind.new("1.3.6.1.4.1.34380.1.1.12", OctetString.new(self.environment))
      trap_options = [hostname_bind, puppet_env_bind]
      
      if SNMP_VERSION =~ /v2/
        SNMP::Manager.open(:Host => SNMP_SERVER, :Version => :SNMPv2c) do |snmp|
          snmp.trap_v2(12345, "1.3.6.1.4.1.34380", trap_options)
        end
      else
        SNMP::Manager.open(:Host => SNMP_SERVER, :Version => :SNMPv1) do |snmp|
          snmp.trap_v1("enterprises.34380", ip_address, :enterpriseSpecific, 42, 12345, trap_options)
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
end
