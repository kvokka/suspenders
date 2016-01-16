require "forwardable"
require 'pry'

module Suspenders
  class AppBuilder < Rails::AppBuilder
    include Suspenders::Actions
    extend Forwardable

    def_delegators :heroku_adapter,
                   :create_heroku_pipelines_config_file,
                   :create_heroku_pipeline,
                   :create_production_heroku_app,
                   :create_staging_heroku_app,
                   :provide_review_apps_setup_script,
                   :set_heroku_rails_secrets,
                   :set_heroku_remotes,
                   :set_heroku_serve_static_files,
                   :set_up_heroku_specific_gems

    def readme
      template 'README.md.erb', 'README.md'
    end

    def raise_on_missing_assets_in_test
      inject_into_file(
        "config/environments/test.rb",
        "\n  config.assets.raise_runtime_errors = true",
        after: "Rails.application.configure do",
      )
    end

    def raise_on_delivery_errors
      replace_in_file 'config/environments/development.rb',
        'raise_delivery_errors = false', 'raise_delivery_errors = true'
    end

    def set_test_delivery_method
      inject_into_file(
        "config/environments/development.rb",
        "\n  config.action_mailer.delivery_method = :test",
        after: "config.action_mailer.raise_delivery_errors = true",
      )
    end

    def add_bullet_gem_configuration
      config = <<-RUBY
  config.after_initialize do
    Bullet.enable = true
    Bullet.bullet_logger = true
    Bullet.rails_logger = true
  end

      RUBY

      inject_into_file(
        "config/environments/development.rb",
        config,
        after: "config.action_mailer.raise_delivery_errors = true\n",
      )
    end

    def raise_on_unpermitted_parameters
      config = <<-RUBY
    config.action_controller.action_on_unpermitted_parameters = :raise
      RUBY

      inject_into_class "config/application.rb", "Application", config
    end

    def configure_quiet_assets
      config = <<-RUBY
    config.quiet_assets = true
      RUBY

      inject_into_class "config/application.rb", "Application", config
    end

    def provide_setup_script
      template "bin_setup", "bin/setup", force: true
      run "chmod a+x bin/setup"
    end

    def provide_dev_prime_task
      copy_file 'dev.rake', 'lib/tasks/dev.rake'
    end

    def configure_generators
      config = <<-RUBY

    config.generators do |generate|
      generate.helper false
      generate.javascript_engine false
      generate.request_specs false
      generate.routing_specs false
      generate.stylesheets false
      generate.test_framework :rspec
      generate.view_specs false
    end

      RUBY

      inject_into_class 'config/application.rb', 'Application', config
    end

    def set_up_factory_girl_for_rspec
      copy_file 'factory_girl_rspec.rb', 'spec/support/factory_girl.rb'
    end

    def generate_factories_file
      copy_file "factories.rb", "spec/factories.rb"
    end

    def set_up_hound
      copy_file "hound.yml", ".hound.yml"
    end

    def configure_newrelic
      template 'newrelic.yml.erb', 'config/newrelic.yml'
    end

    def configure_smtp
      copy_file 'smtp.rb', 'config/smtp.rb'

      prepend_file 'config/environments/production.rb',
        %{require Rails.root.join("config/smtp")\n}

      config = <<-RUBY

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = SMTP_SETTINGS
      RUBY

      inject_into_file 'config/environments/production.rb', config,
        after: "config.action_mailer.raise_delivery_errors = false"
    end

    def enable_rack_canonical_host
      config = <<-RUBY

  if ENV.fetch("HEROKU_APP_NAME", "").include?("staging-pr-")
    ENV["APPLICATION_HOST"] = ENV["HEROKU_APP_NAME"] + ".herokuapp.com"
  end

  # Ensure requests are only served from one, canonical host name
  config.middleware.use Rack::CanonicalHost, ENV.fetch("APPLICATION_HOST")
      RUBY

      inject_into_file(
        "config/environments/production.rb",
        config,
        after: "Rails.application.configure do",
      )
    end

    def enable_rack_deflater
      config = <<-RUBY

  # Enable deflate / gzip compression of controller-generated responses
  config.middleware.use Rack::Deflater
      RUBY

      inject_into_file(
        "config/environments/production.rb",
        config,
        after: serve_static_files_line
      )
    end

    def setup_asset_host
      replace_in_file 'config/environments/production.rb',
        "# config.action_controller.asset_host = 'http://assets.example.com'",
        'config.action_controller.asset_host = ENV.fetch("ASSET_HOST", ENV.fetch("APPLICATION_HOST"))'

      replace_in_file 'config/initializers/assets.rb',
        "config.assets.version = '1.0'",
        'config.assets.version = (ENV["ASSETS_VERSION"] || "1.0")'

      inject_into_file(
        "config/environments/production.rb",
        '  config.static_cache_control = "public, max-age=#{1.year.to_i}"',
        after: serve_static_files_line
      )
    end

    def setup_staging_environment
      staging_file = 'config/environments/staging.rb'
      copy_file 'staging.rb', staging_file

      config = <<-RUBY

Rails.application.configure do
  # ...
end
      RUBY

      append_file staging_file, config
    end

    def setup_secret_token
      template 'secrets.yml', 'config/secrets.yml', force: true
    end

    def disallow_wrapping_parameters
      remove_file "config/initializers/wrap_parameters.rb"
    end

    def create_partials_directory
      empty_directory 'app/views/application'
    end

    def create_shared_flashes
      copy_file "_flashes.html.erb", "app/views/application/_flashes.html.erb"
      copy_file "flashes_helper.rb", "app/helpers/flashes_helper.rb"
    end

    def create_shared_javascripts
      copy_file '_javascript.html.erb', 'app/views/application/_javascript.html.erb'
    end

    def create_application_layout
      template 'suspenders_layout.html.erb.erb',
        'app/views/layouts/application.html.erb',
        force: true
    end

    def use_postgres_config_template
      template 'postgresql_database.yml.erb', 'config/database.yml', force: true
      template 'postgresql_database.yml.erb', 'config/database.yml.sample', force: true
    end

    def create_database
      bundle_command 'exec rake db:create db:migrate'
    end

    def replace_gemfile
      remove_file 'Gemfile'
      template 'Gemfile.erb', 'Gemfile'
    end

    def set_ruby_to_version_being_used
      create_file '.ruby-version', "#{Suspenders::RUBY_VERSION}\n"
    end

    def enable_database_cleaner
      copy_file 'database_cleaner_rspec.rb', 'spec/support/database_cleaner.rb'
    end

    def provide_shoulda_matchers_config
      copy_file(
        "shoulda_matchers_config_rspec.rb",
        "spec/support/shoulda_matchers.rb"
      )
    end

    def configure_spec_support_features
      empty_directory_with_keep_file 'spec/features'
      empty_directory_with_keep_file 'spec/support/features'
    end

    def configure_rspec
      remove_file "spec/rails_helper.rb"
      remove_file "spec/spec_helper.rb"
      copy_file "rails_helper.rb", "spec/rails_helper.rb"
      copy_file "spec_helper.rb", "spec/spec_helper.rb"
    end

    def configure_ci
      template "circle.yml.erb", "circle.yml"
    end

    def configure_i18n_for_test_environment
      copy_file "i18n.rb", "spec/support/i18n.rb"
    end

    def configure_i18n_for_missing_translations
      raise_on_missing_translations_in("development")
      raise_on_missing_translations_in("test")
    end

    def configure_background_jobs_for_rspec
      run 'rails g delayed_job:active_record'
    end

    def configure_action_mailer_in_specs
      copy_file 'action_mailer.rb', 'spec/support/action_mailer.rb'
    end

    def configure_capybara_webkit
      copy_file "capybara_webkit.rb", "spec/support/capybara_webkit.rb"
    end

    def configure_time_formats
      remove_file "config/locales/en.yml"
      template "config_locales_en.yml.erb", "config/locales/en.yml"
    end

    def configure_rack_timeout
      rack_timeout_config = <<-RUBY
Rack::Timeout.timeout = (ENV["RACK_TIMEOUT"] || 10).to_i
      RUBY

      append_file "config/environments/production.rb", rack_timeout_config
    end

    def configure_simple_form
      bundle_command "exec rails generate simple_form:install"
    end

    def configure_action_mailer
      action_mailer_host "development", %{"localhost:3000"}
      action_mailer_host "test", %{"www.example.com"}
      action_mailer_host "production", %{ENV.fetch("APPLICATION_HOST")}
    end

    def configure_active_job
      configure_application_file(
        "config.active_job.queue_adapter = :delayed_job"
      )
      configure_environment "test", "config.active_job.queue_adapter = :inline"
    end

    def fix_i18n_deprecation_warning
      config = <<-RUBY
    config.i18n.enforce_available_locales = true
      RUBY

      inject_into_class 'config/application.rb', 'Application', config
    end

    def generate_rspec
      generate 'rspec:install'
    end

    def configure_puma
      copy_file "puma.rb", "config/puma.rb"
    end

    def set_up_forego
      copy_file "Procfile", "Procfile"
    end

    def setup_stylesheets
      remove_file "app/assets/stylesheets/application.css"
      copy_file "application.scss",
                "app/assets/stylesheets/application.scss"
    end

    def install_refills
      run "rails generate refills:import flashes"
      run "rm app/views/refills/_flashes.html.erb"
      run "rmdir app/views/refills"
    end

    def install_bitters
      run "bitters install --path app/assets/stylesheets"
    end

    def gitignore_files
      remove_file '.gitignore'
      copy_file 'suspenders_gitignore', '.gitignore'
      [
        'app/views/pages',
        'spec/lib',
        'spec/controllers',
        'spec/helpers',
        'spec/support/matchers',
        'spec/support/mixins',
        'spec/support/shared_examples'
      ].each do |dir|
        run "mkdir #{dir}"
        run "touch #{dir}/.keep"
      end
    end

    def copy_dotfiles
      directory("dotfiles", ".")
    end

    def init_git
      run 'git init'
    end

    def git_init_commit
      if @@user_choice.include?(:gitcommit)
        run 'git add .'
        run 'git commit -m "Init commit"'
      end
    end

    def create_heroku_apps(flags)
      create_staging_heroku_app(flags)
      create_production_heroku_app(flags)
    end

    def provide_deploy_script
      copy_file "bin_deploy", "bin/deploy"

      instructions = <<-MARKDOWN

## Deploying

If you have previously run the `./bin/setup` script,
you can deploy to staging and production with:

    $ ./bin/deploy staging
    $ ./bin/deploy production
      MARKDOWN

      append_file "README.md", instructions
      run "chmod a+x bin/deploy"
    end

    def configure_automatic_deployment
      deploy_command = <<-YML.strip_heredoc
      deployment:
        staging:
          branch: master
          commands:
            - bin/deploy staging
      YML

      append_file "circle.yml", deploy_command
    end

    def create_github_repo(repo_name)
      run "hub create #{repo_name}"
    end

    def setup_segment
      copy_file '_analytics.html.erb',
        'app/views/application/_analytics.html.erb'
    end

    def setup_spring
      bundle_command "exec spring binstub --all"
      run 'spring stop'
    end

    def copy_miscellaneous_files
      copy_file "browserslist", "browserslist"
      copy_file "errors.rb", "config/initializers/errors.rb"
      copy_file "json_encoding.rb", "config/initializers/json_encoding.rb"
    end

    def customize_error_pages
      meta_tags =<<-EOS
  <meta charset="utf-8" />
  <meta name="ROBOTS" content="NOODP" />
  <meta name="viewport" content="initial-scale=1" />
      EOS

      %w(500 404 422).each do |page|
        inject_into_file "public/#{page}.html", meta_tags, after: "<head>\n"
        replace_in_file "public/#{page}.html", /<!--.+-->\n/, ''
      end
    end

    def remove_config_comment_lines
      config_files = [
        "application.rb",
        "environment.rb",
        "environments/development.rb",
        "environments/production.rb",
        "environments/test.rb",
      ]

      config_files.each { |config_file|
        cleanup_comments File.join(destination_root, "config/#{config_file}")
      }
    end

  def remove_routes_comment_lines
      replace_in_file 'config/routes.rb',
        /Rails\.application\.routes\.draw do.*end/m,
        "Rails.application.routes.draw do\nend"
    end

    def disable_xml_params
      copy_file 'disable_xml_params.rb', 'config/initializers/disable_xml_params.rb'
    end

    def setup_default_rake_task
      append_file 'Rakefile' do
        <<-EOS
task(:default).clear
task default: [:spec]

if defined? RSpec
  task(:spec).clear
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.verbose = false
  end
end
        EOS
      end
    end

# ------------------------------------ step1

    def users_gems
      @@user_choice = []
        choose_template_engine
        choose_frontend
        # Placeholder for other gem additions

        choose_undroup_gems
        ask_cleanup_commens
        users_init_commit_choice
        add_user_gems
    end

    def user_gems_from_args
      gems_flags = []
      options.each{ |k,v| gems_flags.push k if v == true }
      gems= GEMPROCLIST & gems_flags
      gems.each{ |g| @@user_choice << g }
      add_user_gems
    end

# ------------------------------------ step2

    def choose_frontend
      variants = { none: 'No front-end framework',
                   bootstrap3_sass: 'Twitter bootstrap v.3 sass',
                   bootstrap3: 'Twitter bootstrap v.3 asset pipeline',
                    }
        gem = choice 'Select front-end framework: ', variants
        @@user_choice.push(gem) if gem
    end

    def choose_template_engine
      variants = { none: 'Erb', slim: 'Slim', haml: 'Haml' }
        gem = choice 'Select markup language: ', variants
        @@user_choice.push(gem) if gem
    end

    def choose_undroup_gems
      variants = { none: 'None',
                   rails_db: 'For pretty view in browser & xls export for models',
                   faker: 'Gem for generate fake data in testing',
                   rubocop: 'Code inspector and code formatting tool',
                   guard: 'Guard (with livereload) and dependences',
                   bundler_audit: 'Extra possibilities for gems version control',
                   meta_request: "Rails meta panel in chrome console. Very usefull in AJAX debugging.\n#{' '*24}Link for chrome add-on in Gemfile.\n#{' '*24}Do not delete comments if you need this link",
                    }
      multiple_choice('Write numbers of all preferred gems.', variants).each do |gem|
        @@user_choice.push gem
      end
    end

    # def bundler_audit_gem
    #   gem_name = __callee__.to_s.gsub(/_gem/, '')
    #   gem_description = 'Extra possibilities for gems version control'
    #   @@user_choice.push( yes_no_question( gem_name, gem_description)) unless options[gem_name]
    # end

    def users_init_commit_choice
      variants = { none: 'No', gitcommit: 'Yes' }
      sel = choice 'Make init commit in the end? ', variants
      @@user_choice.push( sel) unless sel == :none
    end

    def ask_cleanup_commens
      unless options[:clean_comments]
        variants = { none: 'No', clean_comments: 'Yes' }
        sel = choice 'Delete comments in Gemfile, routes.rb & config files? ', variants
        @@user_choice.push( sel) unless sel == :none
      end
    end

# ------------------------------------ step3

    def add_haml_gem
      inject_into_file('Gemfile', "\ngem 'haml-rails'", after: '# user_choice')
    end

    def add_slim_gem
      inject_into_file('Gemfile', "\ngem 'slim-rails'", after: '# user_choice')
    end

    def add_rails_db_gem
      inject_into_file('Gemfile', "\n  gem 'rails_db'\n  gem 'axlsx_rails'", after: 'group :development do')
    end

    def add_rubocop_gem
      inject_into_file('Gemfile', "\n  gem 'rubocop', require: false", after: 'group :development do')
      copy_file "templates/.rubocop.yml", ".rubocop.yml"
    end


    def add_guard_gem
      t=<<-TEXT.chomp

  gem 'guard'
  gem 'guard-livereload', '~> 2.4', require: false
      TEXT
      inject_into_file('Gemfile', t, after: 'group :development do')
    end

    def add_guard_rubocop_gem
      inject_into_file('Gemfile', "\n  gem 'guard-rubocop'", after: 'group :development do')
    end

    def add_meta_request_gem
      inject_into_file('Gemfile', "\n  gem 'meta_request' # link for chrome add-on. https://chrome.google.com/webstore/detail/railspanel/gjpfobpafnhjhbajcjgccbbdofdckggg", after: 'group :development do')
    end

    def add_faker_gem
      inject_into_file('Gemfile', "\n  gem 'faker'", after: 'group :test do')
    end

    def add_bundler_audit_gem
      copy_file "bundler_audit.rake", "lib/tasks/bundler_audit.rake"
      append_file "Rakefile", %{\ntask default: "bundler:audit"\n}
    end

    def add_bootstrap3_sass_gem
      inject_into_file('Gemfile', "\ngem 'bootstrap-sass', '~> 3.3.6'", after: '# user_choice')
    end

    def add_bootstrap3_gem
      inject_into_file('Gemfile', "\ngem 'twitter-bootstrap-rails'", after: '# user_choice')
    end

# ------------------------------------ step4

    def add_user_gems
      GEMPROCLIST.each {|g| send "add_#{g}_gem" if  @@user_choice.include? g.to_sym }
      add_guard_rubocop_gem      if @@user_choice.include?(:guard) && @@user_choice.include?(:rubocop) && !options[:guard_rubocop]
    end

    def post_init
      app_file_scss = 'app/assets/stylesheets/application.scss'
      app_file_css = 'app/assets/stylesheets/application.css'
      js_file = 'app/assets/javascripts/application.js'
      if @@user_choice.include?(:bootstrap3_sass)
        setup_stylesheets
        use_asset_pipelline = false
      else
        use_asset_pipelline = true
      end
      run 'guard init' if @@user_choice.present? && @@user_choice.include?(:guard)
      if @@user_choice.include? :rubocop
        t=<<-TEXT
require 'rubocop/rake_task'
RuboCop::RakeTask.new
        TEXT
        append_file 'Rakefile', t
      end
      if @@user_choice.include? :bootstrap3_sass
          append_file(app_file_scss, "\n@import 'bootstrap-sprockets';\n@import 'bootstrap';")
          inject_into_file(js_file, "\n//= require bootstrap-sprockets", after: "//= require jquery_ujs")
          bundle_command "exec rails generate simple_form:install --bootstrap"
      end
      if @@user_choice.include? :bootstrap3
          remove_file 'app/views/layouts/application.html.erb'
          generate 'bootstrap:install static'
          generate 'bootstrap:layout'
          bundle_command "exec rails generate simple_form:install --bootstrap"
      end

      if use_asset_pipelline
        inject_into_file(app_file_css, " *= require normalize-rails\n", after: " * file per style scope.\n *\n")
      else
        inject_into_file(app_file_scss, "\n@import 'normalize-rails';", after: '@charset "utf-8";')
      end
      delete_comments
    end

    private

    def yes_no_question(gem_name, gem_description)
      gem_name_color = "\033[33m#{gem_name.capitalize}.\033[0m\n"
      variants = { none: 'No', gem_name.to_sym => gem_name_color }
      choice "Use #{gem_name}? #{gem_description}", variants
    end

    def choice(selector, variants)
      unless variants.keys[1..-1].map{|a| options[a]}.include? true
        values = []
        say "\n  \033[1m\033[36m#{selector}\033[0m"
        variants.each_with_index do |variant, i|
          values.push variant[0]
          say "#{i.to_s.rjust(5)}. #{variant[1]}"
        end
        answer = ask "\033[1m\033[36m  Enter choice: \033[0m".rjust(10) until (0...variants.length).map(&:to_s).include? answer
        values[answer.to_i] == :none ? nil : values[answer.to_i]
      end
    end

    def multiple_choice(selector, variants)
      values,result = [],[]
      answers = ''
      say "\n  \033[1m\033[36m#{selector} Use space as separator\033[0m"
      variants.each_with_index do |variant, i|
        values.push variant[0]
        say "#{i.to_s.rjust(5)}. \033[1m\033[34m#{variant[0].to_s.ljust(15)}-\033[0m #{variant[1]}"
      end
      loop do
        answers = (ask "\033[1m\033[36m  Enter choices: \033[0m".rjust(10)).split ' '
        break if (answers.any?) && (answers - (0...variants.length).to_a.map(&:to_s)).empty?
      end
      answers.delete '0'
      answers.uniq.each{|a| result.push values[a.to_i]}
      result
    end

    def raise_on_missing_translations_in(environment)
      config = 'config.action_view.raise_on_missing_translations = true'

      uncomment_lines("config/environments/#{environment}.rb", config)
    end

    def heroku_adapter
      @heroku_adapter ||= Adapters::Heroku.new(self)
    end

    def serve_static_files_line
      "config.serve_static_files = ENV['RAILS_SERVE_STATIC_FILES'].present?\n"
    end

    def add_gems_from_args
      ARGV.each do |g|
        next unless g[0]=='-' && g[1]=='-'
        @@user_choice.push g[2..-1].to_sym
      end
    end

    def cleanup_comments file
      accepted_content = File.readlines(file).reject do |line|
        line =~ /^.*#.*$/ || line =~ /^$\n/
      end

      File.open(file, "w") do |file|
        accepted_content.each { |line| file.puts line }
      end
    end

    def delete_comments
      if options[:clean_comments] || @@user_choice.include?(:clean_comments)
        cleanup_comments 'Gemfile'
        remove_config_comment_lines
        remove_routes_comment_lines
      end
    end
  end
end
