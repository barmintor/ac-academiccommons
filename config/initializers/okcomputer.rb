# Additional checks for OkComputer.

# Require authentication to all checks but the default check
creds = Rails.application.config_for(:secrets)['okcomputer']
raise 'Missing OkComputer credentials' if creds.blank?

OkComputer.require_authentication(creds['user'], creds['password'], except: %w(default))

# Checking Solr connection
solr_urls = [:solr, :blacklight].map {|c| Rails.application.config_for(c)['url'] }.uniq
solr_urls.each_with_index do |url, i|
  OkComputer::Registry.register("solr#{i}", OkComputer::SolrCheck.new(url))
end

# Checking Fedora object retrieval
OkComputer::Registry.register("fedora_object", OkComputer::FedoraObjectCheck.new)

# Checking mail server configuration and availability
OkComputer::Registry.register('action_mailer', OkComputer::ActionMailerCheck.new)

# Check that directories exists
OkComputer::Registry.register('indexing_log_directory', OkComputer::DirectoryCheck.new('log/ac-indexing'))
OkComputer::Registry.register('reports_log_directory', OkComputer::DirectoryCheck.new('log/monthly_reports'))
OkComputer::Registry.register('self_deposits_directory', OkComputer::DirectoryCheck.new('data/self-deposit-uploads'))
