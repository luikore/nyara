namespace :db do
  desc "run migration. example: `NYARA_ENV=test VERSION=20130901 rake db:migrate`"
  task :migrate do
    require 'active_record'
    db_config = YAML.load_file 'config/database.yml'
    ActiveRecord::Base.establish_connection db_config[(ENV['NYARA_ENV'] || 'development')]
    ActiveRecord::Migrator.migrate 'db/migrate', ENV['VERSION'] ? ENV['VERSION'].to_i : nil
  end

  desc "create database. example: `NYARA_ENV=test rake db:create`"
  task :create do
    require 'active_record'
    db_config = YAML.load_file 'config/database.yml'
    t = ActiveRecord::Tasks::DatabaseTasks
    t.create db_config[(ENV['NYARA_ENV'] || 'development')]
  end
end
