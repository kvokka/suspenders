require 'forwardable'
# require 'pry'

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

    @@devise_model = ''
    @@user_choice  = []
    @@use_asset_pipelline = true

    def readme
      template 'README.md.erb', 'README.md'
    end

    def raise_on_missing_assets_in_test
      inject_into_file(
        'config/environments/test.rb',
        "\n  config.assets.raise_runtime_errors = true",
        after: 'Rails.application.configure do'
      )
    end

    def raise_on_delivery_errors
      replace_in_file 'config/environments/development.rb',
                      'raise_delivery_errors = false', 'raise_delivery_errors = true'
    end

    def set_test_delivery_method
      inject_into_file(
        'config/environments/development.rb',
        "\n  config.action_mailer.delivery_method = :test",
        after: 'config.action_mailer.raise_delivery_errors = true'
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
        'config/environments/development.rb',
        config,
        after: "config.action_mailer.raise_delivery_errors = true\n"
      )
    end

    def raise_on_unpermitted_parameters
      config = "\n    config.action_controller.action_on_unpermitted_parameters = :raise"
      inject_into_class 'config/application.rb', 'Application', config
    end

    def configure_quiet_assets
      config = "\n    config.quiet_assets = true"
      inject_into_class 'config/application.rb', 'Application', config
    end

    def provide_setup_script
      template 'bin_setup', 'bin/setup', force: true
      run 'chmod a+x bin/setup'
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
      generate.fixture_replacement :factory_girl
    end

      RUBY

      inject_into_class 'config/application.rb', 'Application', config
    end

    def set_up_factory_girl_for_rspec
      copy_file 'factory_girl_rspec.rb', 'spec/support/factory_girl.rb'
    end

    def generate_factories_file
      copy_file 'factories.rb', 'spec/factories.rb'
    end

    def set_up_hound
      copy_file 'hound.yml', '.hound.yml'
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
                       after: 'config.action_mailer.raise_delivery_errors = false'
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
        'config/environments/production.rb',
        config,
        after: 'Rails.application.configure do'
      )
    end

    def enable_rack_deflater
      config = <<-RUBY

  # Enable deflate / gzip compression of controller-generated responses
  config.middleware.use Rack::Deflater
      RUBY

      inject_into_file(
        'config/environments/production.rb',
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
        'config/environments/production.rb',
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
      remove_file 'config/initializers/wrap_parameters.rb'
    end

    def create_partials_directory
      empty_directory 'app/views/application'
    end

    def create_shared_flashes
      copy_file '_flashes.html.erb',
                'app/views/application/_flashes.html.erb'
      copy_file 'flashes_helper.rb',
                'app/helpers/flashes_helper.rb'
    end

    def create_shared_javascripts
      copy_file '_javascript.html.erb',
                'app/views/application/_javascript.html.erb'
    end

    def create_application_layout
      template 'suspenders_layout.html.erb.erb',
               'app/views/layouts/application.html.erb',
               force: true
    end

    def use_postgres_config_template
      template 'postgresql_database.yml.erb', 'config/database.yml',
               force: true
      template 'postgresql_database.yml.erb', 'config/database.yml.sample',
               force: true
    end

    def create_database
      bundle_command 'exec rake db:drop db:create db:migrate'
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
        'shoulda_matchers_config_rspec.rb',
        'spec/support/shoulda_matchers.rb'
      )
    end

    def configure_spec_support_features
      empty_directory_with_keep_file 'spec/features'
      empty_directory_with_keep_file 'spec/support/features'
    end

    def configure_rspec
      remove_file 'spec/rails_helper.rb'
      remove_file 'spec/spec_helper.rb'
      copy_file 'rails_helper.rb', 'spec/rails_helper.rb'
      copy_file 'spec_helper.rb', 'spec/spec_helper.rb'
    end

    def configure_ci
      template 'circle.yml.erb', 'circle.yml'
    end

    def configure_i18n_for_test_environment
      copy_file 'i18n.rb', 'spec/support/i18n.rb'
    end

    def configure_i18n_for_missing_translations
      raise_on_missing_translations_in('development')
      raise_on_missing_translations_in('test')
    end

    def configure_background_jobs_for_rspec
      generate 'delayed_job:active_record'
    end

    def configure_action_mailer_in_specs
      copy_file 'action_mailer.rb', 'spec/support/action_mailer.rb'
    end

    def configure_capybara_webkit
      copy_file 'capybara_webkit.rb', 'spec/support/capybara_webkit.rb'
    end

    def configure_time_formats
      remove_file 'config/locales/en.yml'
      template 'config_locales_en.yml.erb', 'config/locales/en.yml'
    end

    def configure_rack_timeout
      rack_timeout_config = 'Rack::Timeout.timeout = (ENV["RACK_TIMEOUT"] || 10).to_i'
      append_file 'config/environments/production.rb', rack_timeout_config
    end

    def configure_simple_form
      bundle_command 'exec rails generate simple_form:install'
    end

    def configure_action_mailer
      action_mailer_host 'development', %("localhost:3000")
      action_mailer_host 'test', %("www.example.com")
      action_mailer_host 'production', %{ENV.fetch("APPLICATION_HOST")}
    end

    def configure_active_job
      configure_application_file(
        'config.active_job.queue_adapter = :delayed_job'
      )
      configure_environment 'test', 'config.active_job.queue_adapter = :inline'
    end

    def fix_i18n_deprecation_warning
      config = '    config.i18n.enforce_available_locales = true'
      inject_into_class 'config/application.rb', 'Application', config
    end

    def generate_rspec
      generate 'rspec:install'
    end

    def configure_puma
      copy_file 'puma.rb', 'config/puma.rb'
    end

    def set_up_forego
      copy_file 'Procfile', 'Procfile'
    end

    def setup_stylesheets
      remove_file 'app/assets/stylesheets/application.css'
      copy_file 'application.scss',
                'app/assets/stylesheets/application.scss'
    end

    def install_refills
      generate 'refills:import flashes'
      run 'rm app/views/refills/_flashes.html.erb'
      run 'rmdir app/views/refills'
    end

    def install_bitters
      run 'bitters install --path app/assets/stylesheets'
    end

    def gitignore_files
      remove_file '.gitignore'
      copy_file 'gitignore_file', '.gitignore'
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
      directory 'dotfiles', '.', force: true
    end

    def init_git
      run 'git init'
    end

    def git_init_commit
      if user_choose?(:gitcommit)
        say 'Init commit'
        run 'git add .'
        run 'git commit -m "Init commit"'
      end
    end

    def create_heroku_apps(flags)
      create_staging_heroku_app(flags)
      create_production_heroku_app(flags)
    end

    def provide_deploy_script
      copy_file 'bin_deploy', 'bin/deploy'

      instructions = <<-MARKDOWN

## Deploying

If you have previously run the `./bin/setup` script,
you can deploy to staging and production with:

    $ ./bin/deploy staging
    $ ./bin/deploy production
      MARKDOWN

      append_file 'README.md', instructions
      run 'chmod a+x bin/deploy'
    end

    def configure_automatic_deployment
      deploy_command = <<-YML.strip_heredoc
      deployment:
        staging:
          branch: master
          commands:
            - bin/deploy staging
      YML

      append_file 'circle.yml', deploy_command
    end

    def create_github_repo(repo_name)
      run "hub create #{repo_name}"
    end

    def setup_segment
      copy_file '_analytics.html.erb',
                'app/views/application/_analytics.html.erb'
    end

    def setup_spring
      bundle_command 'exec spring binstub --all'
      run 'spring stop'
    end

    def copy_miscellaneous_files
      copy_file 'browserslist', 'browserslist'
      copy_file 'errors.rb', 'config/initializers/errors.rb'
      copy_file 'json_encoding.rb', 'config/initializers/json_encoding.rb'
    end

    def customize_error_pages
      meta_tags = <<-EOS
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
        'application.rb',
        'environment.rb',
        'environments/development.rb',
        'environments/production.rb',
        'environments/test.rb'
      ]

      config_files.each do |config_file|
        cleanup_comments File.join(destination_root, "config/#{config_file}")
      end
    end

    def remove_routes_comment_lines
      replace_in_file 'config/routes.rb',
                      /Rails\.application\.routes\.draw do.*end/m,
                      "Rails.application.routes.draw do\nend"
    end

    def disable_xml_params
      copy_file 'disable_xml_params.rb',
                'config/initializers/disable_xml_params.rb'
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

    def install_user_gems_from_github
      File.readlines('Gemfile').each do |l|
        possible_gem_name = l.match(/(?:github:\s+)(?:'|")\w+\/(.*)(?:'|")/i)
        install_from_github possible_gem_name[1] if possible_gem_name
      end
    end

    # def rvm_bundler_stubs_install
    #   if system "rvm -v | grep 'rvm.io'"
    #     run 'chmod +x $rvm_path/hooks/after_cd_bundler'
    #     run 'bundle install --binstubs=./bundler_stubs'
    #   end
    # end

    # ------------------------------------ step1

    def users_gems
      choose_authenticate_engine
      choose_template_engine
      choose_frontend
      # Placeholder for other gem additions

      choose_undroup_gems
      ask_cleanup_commens
      users_init_commit_choice
      add_user_gems
    end

    def user_gems_from_args_or_default_set
      gems_flags = []
      options.each { |k, v| gems_flags.push k.to_sym if v == true }
      gems = GEMPROCLIST & gems_flags
      if gems.empty?
        @@user_choice = DEFAULT_GEMSET
      else
        gems.each { |g| @@user_choice << g }
      end
      add_user_gems
    end

    # ------------------------------------ step2

    def choose_frontend
      variants = { none:            'No front-end framework',
                   bootstrap3_sass: 'Twitter bootstrap v.3 sass',
                   bootstrap3:      'Twitter bootstrap v.3 asset pipeline'
                    }
      gem = choice 'Select front-end framework: ', variants
      add_to_user_choise(gem) if gem
    end

    def choose_template_engine
      variants = { none: 'Erb', slim: 'Slim', haml: 'Haml' }
      gem = choice 'Select markup language: ', variants
      add_to_user_choise(gem) if gem
    end

    def choose_authenticate_engine
      variants = { none: 'None', devise: 'devise', devise_with_model: 'devise vs pre-installed model' }
      gem = choice 'Select authenticate engine: ', variants
      if gem == :devise_with_model
        @@devise_model = ask_stylish 'Enter devise model name:'
        gem = :devise
      end
      add_to_user_choise(gem) if gem
    end

    def choose_undroup_gems
      variants = { none:          'None',
                   will_paginate: 'Easy pagination implement',
                   rails_db:      'For pretty view in browser & xls export for models',
                   faker:         'Gem for generate fake data in testing',
                   rubocop:       'Code inspector and code formatting tool',
                   guard:         'Guard (with RSpec, livereload, rails, migrate, bundler)',
                   bundler_audit: 'Extra possibilities for gems version control',
                   airbrake:      'Airbrake error logging',
                   responders:    'A set of responders modules to dry up your Rails 4.2+ app.',
                   hirbunicode:   'Hirb unicode support',
                   dotenv_heroku: 'dotenv-heroku support',
                   tinymce:       'Integration of TinyMCE with the Rails asset pipeline',
                   meta_request:  "Rails meta panel in chrome console. Very usefull in AJAX debugging.\n#{' ' * 24}Link for chrome add-on in Gemfile.\n#{' ' * 24}Do not delete comments if you need this link"
                    }
      multiple_choice('Write numbers of all preferred gems.', variants).each do |gem|
        add_to_user_choise gem
      end
    end

    # def bundler_audit_gem
    #   gem_name = __callee__.to_s.gsub(/_gem/, '')
    #   gem_description = 'Extra possibilities for gems version control'
    #   add_to_user_choise( yes_no_question( gem_name,
    #           gem_description)) unless options[gem_name]
    # end

    def users_init_commit_choice
      variants = { none: 'No', gitcommit: 'Yes' }
      sel = choice 'Make init commit in the end? ', variants
      add_to_user_choise(sel) unless sel == :none
    end

    def ask_cleanup_commens
      unless options[:clean_comments]
        variants = { none: 'No', clean_comments: 'Yes' }
        sel = choice 'Delete comments in Gemfile, routes.rb & config files? ',
                     variants
        add_to_user_choise(sel) unless sel == :none
      end
    end

    # ------------------------------------ step3

    def add_haml_gem
      inject_into_file('Gemfile', "\ngem 'haml-rails'", after: '# user_choice')
    end

    def add_dotenv_heroku_gem
      inject_into_file('Gemfile', "\n  gem 'dotenv-heroku'",
                       after: 'group :development do')
      append_file 'Rakefile', %(\nrequire 'dotenv-heroku/tasks' if ENV['RAILS_ENV'] == 'test' || ENV['RAILS_ENV'] == 'development'\n)
    end

    def add_slim_gem
      inject_into_file('Gemfile', "\ngem 'slim-rails'", after: '# user_choice')
      inject_into_file('Gemfile', "\n  gem 'html2slim'", after: 'group :development do')
    end

    def add_rails_db_gem
      inject_into_file('Gemfile', "\n  gem 'rails_db'\n  gem 'axlsx_rails'",
                       after: 'group :development do')
    end

    def add_rubocop_gem
      inject_into_file('Gemfile', "\n  gem 'rubocop', require: false",
                       after: 'group :development do')
      copy_file 'rubocop.yml', '.rubocop.yml'
    end

    def add_guard_gem
      t = <<-TEXT.chomp

  gem 'guard'
  gem 'guard-livereload', '~> 2.4', require: false
  gem 'guard-puma'
  gem 'guard-migrate'
  gem 'guard-rspec', require: false
  gem 'guard-bundler', require: false
  gem 'rb-inotify', github: 'kvokka/rb-inotify'
      TEXT
      inject_into_file('Gemfile', t, after: 'group :development do')
    end

    def add_guard_rubocop_gem
      inject_into_file('Gemfile', "\n  gem 'guard-rubocop'",
                       after: 'group :development do')
    end

    def add_meta_request_gem
      inject_into_file('Gemfile', "\n  gem 'meta_request' # link for chrome add-on. https://chrome.google.com/webstore/detail/railspanel/gjpfobpafnhjhbajcjgccbbdofdckggg",
                       after: 'group :development do')
    end

    def add_faker_gem
      inject_into_file('Gemfile', "\n  gem 'faker'", after: 'group :development, :test do')
    end

    def add_bundler_audit_gem
      copy_file 'bundler_audit.rake', 'lib/tasks/bundler_audit.rake'
      append_file 'Rakefile', %(\ntask default: "bundler:audit"\n)
    end

    def add_bootstrap3_sass_gem
      inject_into_file('Gemfile', "\ngem 'bootstrap-sass', '~> 3.3.6'",
                       after: '# user_choice')
    end

    def add_airbrake_gem
      inject_into_file('Gemfile', "\ngem 'airbrake'",
                       after: '# user_choice')
    end

    def add_bootstrap3_gem
      inject_into_file('Gemfile', "\ngem 'twitter-bootstrap-rails'",
                       after: '# user_choice')
      inject_into_file('Gemfile', "\ngem 'devise-bootstrap-views'",
                       after: '# user_choice') if user_choose?(:devise)
    end

    def add_devise_gem
      devise_conf = <<-TEXT

  # v.3.5 syntax. will be deprecated in 4.0
  def configure_permitted_parameters
    devise_parameter_sanitizer.for(:sign_in) do |user_params|
      user_params.permit(:email, :password)
    end

    devise_parameter_sanitizer.for(:sign_up) do |user_params|
      user_params.permit(:email, :password, :password_confirmation)
    end
  end
  protected :configure_permitted_parameters
    TEXT
      inject_into_file('Gemfile', "\ngem 'devise'", after: '# user_choice')
      inject_into_file('app/controllers/application_controller.rb',
                       "\nbefore_action :configure_permitted_parameters, if: :devise_controller?",
                       after: 'class ApplicationController < ActionController::Base')

      inject_into_file('app/controllers/application_controller.rb', devise_conf,
                       after: 'protect_from_forgery with: :exception')
      copy_file 'devise_rspec.rb', 'spec/support/devise.rb'
    end

    def add_will_paginate_gem
      inject_into_file('Gemfile', "\ngem 'will_paginate', '~> 3.0.6'",
                       after: '# user_choice')
      inject_into_file('Gemfile', "\ngem 'will_paginate-bootstrap'",
                       after: '# user_choice') if user_choose?(:bootstrap3) ||
                                                  user_choose?(:bootstrap3_sass)
    end

    def add_responders_gem
      inject_into_file('Gemfile', "\ngem 'responders'", after: '# user_choice')
    end

    def add_hirbunicode_gem
      inject_into_file('Gemfile', "\ngem 'hirb-unicode'", after: '# user_choice')
    end

    def add_tinymce_gem
      inject_into_file('Gemfile', "\ngem 'tinymce-rails'", after: '# user_choice')
      copy_file 'tinymce.yml', 'config/tinymce.yml'
    end

    # ------------------------------------ step4

    def add_user_gems
      GEMPROCLIST.each do |g|
        send "add_#{g}_gem" if user_choose? g.to_sym
      end
      add_guard_rubocop_gem if user_choose?(:guard) &&
                               user_choose?(:rubocop) &&
                               !options[:guard_rubocop]
    end

    def post_init
      @@app_file_scss = 'app/assets/stylesheets/application.scss'
      @@app_file_css = 'app/assets/stylesheets/application.css'
      @@js_file = 'app/assets/javascripts/application.js'
      install_queue = [:responders,
                       :guard,
                       :guard_rubocop,
                       :bootstrap3_sass,
                       :bootstrap3,
                       :devise,
                       :normalize,
                       :tinymce,
                       :rubocop]
      install_queue.each { |q| send "after_install_#{q}" }
      delete_comments
    end

    def after_install_devise
      generate 'devise:install' if user_choose? :devise
      if !@@devise_model.empty? && user_choose?(:devise)
        generate "devise #{@@devise_model.titleize}"
        inject_into_file('app/controllers/application_controller.rb',
                         "\nbefore_action :authenticate_user!",
                         after: 'before_action :configure_permitted_parameters, if: :devise_controller?')
      end
      if user_choose?(:bootstrap3)
        generate 'devise:views:bootstrap_templates'
      else
        generate 'devise:views'
      end
    end

    def after_install_rubocop
      if user_choose? :rubocop
        t = <<-TEXT

if ENV['RAILS_ENV'] == 'test' || ENV['RAILS_ENV'] == 'development'
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
end
        TEXT
        append_file 'Rakefile', t
        run 'rubocop -a'
      end
    end

    def after_install_guard
      if user_choose?(:guard)
        run 'guard init'
        replace_in_file 'Guardfile',
                        "guard 'puma' do",
                        'guard :puma, port: 3000 do', quiet_err = true
      end
    end

    def after_install_guard_rubocop
      if user_choose?(:guard) && user_choose?(:rubocop)

        cover_def_by 'Guardfile', 'guard :rubocop do', 'group :red_green_refactor, halt_on_fail: true do'
        cover_def_by 'Guardfile', 'guard :rspec, ', 'group :red_green_refactor, halt_on_fail: true do'

        replace_in_file 'Guardfile',
                        'guard :rubocop do',
                        'guard :rubocop, all_on_start: false do', quiet_err = true
        replace_in_file 'Guardfile',
                        'guard :rspec, cmd: "bundle exec rspec" do',
                        "guard :rspec, cmd: 'bundle exec rspec', failed_mode: :keep do", quiet_err = true
      end
    end

    def after_install_bootstrap3_sass
      if user_choose? :bootstrap3_sass
        setup_stylesheets
        @@use_asset_pipelline = false
        append_file(@@app_file_scss,
                    "\n@import 'bootstrap-sprockets';\n@import 'bootstrap';")
        inject_into_file(@@js_file, "\n//= require bootstrap-sprockets",
                         after: '//= require jquery_ujs')
        bundle_command 'exec rails generate simple_form:install --bootstrap'
      end
    end

    def after_install_bootstrap3
      if user_choose? :bootstrap3
        @@use_asset_pipelline = true
        remove_file 'app/views/layouts/application.html.erb'
        generate 'bootstrap:install static'
        generate 'bootstrap:layout'
        bundle_command 'exec rails generate simple_form:install --bootstrap'
        inject_into_file('app/assets/stylesheets/bootstrap_and_overrides.css',
                         "  =require devise_bootstrap_views\n",
                         before: '  */')
      end
    end

    def after_install_normalize
      if @@use_asset_pipelline
        inject_into_file(@@app_file_css, " *= require normalize-rails\n",
                         after: " * file per style scope.\n *\n")
      else
        inject_into_file(@@app_file_scss, "\n@import 'normalize-rails';",
                         after: '@charset "utf-8";')
      end
    end

    def after_install_tinymce
      if user_choose? :tinymce
        inject_into_file(@@js_file, "\n//= require tinymce-jquery",
                         after: '//= require jquery_ujs')
      end
    end

    def after_install_responders
      run('rails g responders:install') if user_choose? :responders
    end

    def show_goodbye_message
      say 'Congratulations! You just pulled our suspenders.'
      say_color YELLOW, "Remember to run 'rails generate airbrake' with your API key." if user_choose? :airbrake
    end

    private

      def yes_no_question(gem_name, gem_description)
        gem_name_color = "#{gem_name.capitalize}.\n"
        variants = { none: 'No', gem_name.to_sym => gem_name_color }
        choice "Use #{gem_name}? #{gem_description}", variants
      end

      def choice(selector, variants)
        unless variants.keys[1..-1].map { |a| options[a] }.include? true
          values = []
          say "\n  #{BOLDGREEN}#{selector}#{COLOR_OFF}"
          variants.each_with_index do |variant, i|
            values.push variant[0]
            say "#{i.to_s.rjust(5)}. #{BOLDBLUE}#{variant[1]}#{COLOR_OFF}"
          end
          answer = ask_stylish('Enter choice:') until (0...variants.length)
                                                      .map(&:to_s).include? answer
          values[answer.to_i] == :none ? nil : values[answer.to_i]
        end
      end

      def multiple_choice(selector, variants)
        values = []
        result = []
        answers = ''
        say "\n  #{BOLDGREEN}#{selector} Use space as separator#{COLOR_OFF}"
        variants.each_with_index do |variant, i|
          values.push variant[0]
          say "#{i.to_s.rjust(5)}. #{BOLDBLUE}#{variant[0]
                .to_s.ljust(15)}-#{COLOR_OFF} #{variant[1]}"
        end
        loop do
          answers = ask_stylish('Enter choices:').split ' '
          break if answers.any? && (answers - (0...variants.length)
                  .to_a.map(&:to_s)).empty?
        end
        answers.delete '0'
        answers.uniq.each { |a| result.push values[a.to_i] }
        result
      end

      def ask_stylish(str)
        ask "#{BOLDGREEN}  #{str} #{COLOR_OFF}".rjust(10)
      end

      def say_color(color, str)
        say "#{color}#{str}#{COLOR_OFF}".rjust(4)
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
          next unless g[0] == '-' && g[1] == '-'
          add_to_user_choise g[2..-1].to_sym
        end
      end

      def cleanup_comments(file)
        accepted_content = File.readlines(file).reject do |line|
          line =~ /^\s*#.*$/ || line =~ /^$\n/
        end

        File.open(file, 'w') do |f|
          accepted_content.each { |line| f.puts line }
        end
      end

      def delete_comments
        if options[:clean_comments] || user_choose?(:clean_comments)
          cleanup_comments 'Gemfile'
          remove_config_comment_lines
          remove_routes_comment_lines
        end
      end

      # does not recognize variable nesting, but now it does not matter
      def cover_def_by(file, lookup_str, external_def)
        expect_end = 0
        found = false
        accepted_content = ''
        File.readlines(file).each do |line|
          expect_end += 1 if found && line =~ /\sdo\s/
          expect_end -= 1 if found && line =~ /(\s+end|^end)/
          if line =~ Regexp.new(lookup_str)
            accepted_content += "#{external_def}\n#{line}"
            expect_end += 1
            found = true
          else
            accepted_content += line
          end
          if found && expect_end == 0
            accepted_content += "\nend"
            found = false
          end
        end
        File.open(file, 'w') do |f|
          f.puts accepted_content
        end
      end

      def install_from_github(gem_name)
        return nil unless gem_name
        path = `bundle list #{gem_name}`.chomp
        run "cd #{path} && gem build #{gem_name}.gemspec && gem install #{gem_name}"
      end

      def user_choose?(g)
        @@user_choice.include? g
      end

      def add_to_user_choise(g)
        @@user_choice.push g
      end
  end
end
