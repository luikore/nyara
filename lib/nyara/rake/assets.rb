namespace :assets do
  desc "compile assets into public (requires linner)"
  task :build do
    sh 'bundle exec linner build'
  end

  desc "clean assets in public (requires linner)"
  task :clean do
    sh 'bundle exec linner clean'
  end
end
