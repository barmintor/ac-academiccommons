set :rails_env, "pass_test"
set :domain,      "taft.cul.columbia.edu"
set :deploy_to,   "/opt/passenger/ac2_test/"
set :user, "deployer"
set :branch, "pass_test"
set :scm_passphrase, "Current user can full owner domains."

role :app, domain
role :web, domain
role :db,  domain, :primary => true

