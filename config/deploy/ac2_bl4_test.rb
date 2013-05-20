set :rails_env, "ac2_bl4_test"
set :application, "ac2_bl4_test"
set :domain,      "bronte.cul.columbia.edu"
set :deploy_to,   "/opt/passenger/#{application}/"
set :user, "deployer"
set :branch, @variables[:branch] || "ac2_bl4_test"
set :default_branch, "ac2_bl4_test"
set :scm_passphrase, "Current user can full owner domains."

role :app, domain
role :web, domain
role :db,  domain, :primary => true