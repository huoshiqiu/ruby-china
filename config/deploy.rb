# coding: utf-8
require "bundler/capistrano"
require "sidekiq/capistrano"
require "rvm/capistrano"
require 'puma/capistrano'

default_run_options[:pty] = true

ip = '192.168.0.31'

set :rvm_type, :auto                     # Defaults to: :auto
set :rvm_ruby_version, 'default'      # Defaults to: 'default'
set :application, "chinaswift"
set :repository,  "https://github.com/huoshiqiu/ruby-china.git"
set :branch, "master"
set :deploy_to, '/home/deploy/swift'
set :scm, :git
# set :deploy_via, :remote_cache
set :git_shallow_clone, 1
set :puma_role, :app
set :puma_config_file, "config/puma.rb"

role :app, "deploy@#{ip}"
role :web, "deploy@#{ip}"
role :db,  "deploy@#{ip}"
role :queue, "deploy@#{ip}"

server ip, user: 'deploy', roles: %w{web app}, my_property: :my_value

namespace :sidekiq do
  task :quiet, :roles => :queue do
   run "cd #{deploy_to}/current/; bundle exec sidekiqctl quiet tmp/pids/sidekiq.pid"
  end

  task :stop, :roles => :queue do
   run "cd #{deploy_to}/current/; bundle exec sidekiqctl stop tmp/pids/sidekiq.pid 60"
  end
end

namespace :faye do
  desc "Start Faye"
  task :start, :roles => :app do
    run "cd #{deploy_to}/current/faye_server; bundle exec thin start -C thin.yml"
  end

  desc "Stop Faye"
  task :stop, :roles => :app do
    run "cd #{deploy_to}/current/faye_server; bundle exec thin stop -C thin.yml"
  end

  desc "Restart Faye"
  task :restart, :roles => :app do
    run "cd #{deploy_to}/current/faye_server; bundle exec thin restart -C  thin.yml"
  end
end

task :init_shared_path, :roles => :web do
  run "mkdir -p #{deploy_to}/shared/log"
  run "mkdir -p #{deploy_to}/shared/pids"
  run "mkdir -p #{deploy_to}/shared/assets"
end

task :link_shared_files, :roles => :web do
  run "ln -sf #{shared_path}/assets #{deploy_to}/current/public/assets"
  run "ln -sf #{deploy_to}/shared/config/*.yml #{deploy_to}/current/config/"
  run "ln -sf #{deploy_to}/shared/config/initializers/secret_token.rb #{deploy_to}/current/config/initializers"
  run "ln -sf #{deploy_to}/shared/config/faye_thin.yml #{deploy_to}/current/faye_server/thin.yml"
  run "ln -sf #{shared_path}/pids #{deploy_to}/current/tmp/"
end

task :mongoid_create_indexes, :roles => :web do
  run "cd #{deploy_to}/current/; RAILS_ENV=production bundle exec rake db:mongoid:create_indexes"
end

task :compile_assets, :roles => :web do
  run "cd #{deploy_to}/current/; RAILS_ENV=production bundle exec rake assets:precompile"
  run "cd #{deploy_to}/current/; RAILS_ENV=production bundle exec rake assets:cdn"
end

task :mongoid_migrate_database, :roles => :web do
  run "cd #{deploy_to}/current/; RAILS_ENV=production bundle exec rake db:migrate"
end

after "deploy:finalize_update","deploy:symlink", :init_shared_path, :link_shared_files , :mongoid_migrate_database , :compile_assets
before "deploy:update_code", "sidekiq:quiet"
after "deploy:update", "sidekiq:stop"
