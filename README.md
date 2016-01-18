# Suspenders

![Suspenders boy](http://media.tumblr.com/1TEAMALpseh5xzf0Jt6bcwSMo1_400.png)

## About

Fork from thoughtbot/suspenders
Implemented function of user choice gems installation with all their settings,
so you can use fully working application with all needed installed and
configured from the box

This user gem pack are available for installation

 * bootstrap3
 * bootstrap3_sass
 * bundler_audit
 * faker
 * guard
 * guard_rubocop
 * slim
 * haml
 * meta_request
 * rails_db
 * rubocop
 * devise
 * devise-bootstrap-views
 * will_paginate
 * will_paginate-bootstrap


## Installation

First install the suspenders gem:

    gem install suspenders

Then run:

    suspenders projectname

This will create a Rails app in `projectname` using the latest version of Rails.

    suspenders projectname -c

This will provide a dialog, where you can select needed gems, also you can add
it with gemname flag, after app_name, like `suspenders projectname --slim`.

*NB: if you install custom gems, default user gem pack will not be installed.

## Gemfile

To see the latest and greatest gems, look at Suspenders'
[Gemfile](templates/Gemfile.erb), which will be appended to the default
generated projectname/Gemfile. This gem will be installed anyway.

It includes application gems like:

* [Airbrake](https://github.com/airbrake/airbrake) for exception notification
* [Autoprefixer Rails](https://github.com/ai/autoprefixer-rails) for CSS vendor prefixes
* [Delayed Job](https://github.com/collectiveidea/delayed_job) for background
  processing
* [Flutie](https://github.com/thoughtbot/flutie) for `page_title` and `body_class` view
  helpers
* [High Voltage](https://github.com/thoughtbot/high_voltage) for static pages
* [jQuery Rails](https://github.com/rails/jquery-rails) for jQuery
* [New Relic RPM](https://github.com/newrelic/rpm) for monitoring performance
* [Normalize](https://necolas.github.io/normalize.css/) for resetting browser styles
* [Postgres](https://github.com/ged/ruby-pg) for access to the Postgres database
* [Rack Canonical Host](https://github.com/tylerhunt/rack-canonical-host) to
  ensure all requests are served from the same domain
* [Rack Timeout](https://github.com/heroku/rack-timeout) to abort requests that are
  taking too long
* [Recipient Interceptor](https://github.com/croaky/recipient_interceptor) to
  avoid accidentally sending emails to real people from staging
* [Simple Form](https://github.com/plataformatec/simple_form) for form markup
  and style
* [Title](https://github.com/calebthompson/title) for storing titles in
  translations
* [Puma](https://github.com/puma/puma) to serve HTTP requests

And development gems like:

* [Dotenv](https://github.com/bkeepers/dotenv) for loading environment variables
* [Pry Rails](https://github.com/rweng/pry-rails) for interactively exploring
  objects
* [ByeBug](https://github.com/deivid-rodriguez/byebug) for interactively
  debugging behavior
* [Bullet](https://github.com/flyerhzm/bullet) for help to kill N+1 queries and
  unused eager loading
* [Bundler Audit](https://github.com/rubysec/bundler-audit) for scanning the
  Gemfile for insecure dependencies based on published CVEs
* [Spring](https://github.com/rails/spring) for fast Rails actions via
  pre-loading
* [Web Console](https://github.com/rails/web-console) for better debugging via
  in-browser IRB consoles.
* [Quiet Assets](https://github.com/evrone/quiet_assets) for muting assets
  pipeline log messages

And testing gems like:

* [Capybara](https://github.com/jnicklas/capybara) and
  [Capybara Webkit](https://github.com/thoughtbot/capybara-webkit) for
  integration testing
* [Factory Girl](https://github.com/thoughtbot/factory_girl) for test data
* [Formulaic](https://github.com/thoughtbot/formulaic) for integration testing
  HTML forms
* [RSpec](https://github.com/rspec/rspec) for unit testing
* [RSpec Mocks](https://github.com/rspec/rspec-mocks) for stubbing and spying
* [Shoulda Matchers](https://github.com/thoughtbot/shoulda-matchers) for common
  RSpec matchers
* [Timecop](https://github.com/ferndopolis/timecop-console) for testing time

## Other goodies

Suspenders also comes with:

* The [`./bin/setup`][setup] convention for new developer setup
* Rails' flashes set up and in application layout
* A few nice time formats set up for localization
* `Rack::Deflater` to [compress responses with Gzip][compress]
* A [low database connection pool limit][pool]
* [Safe binstubs][binstub]
* [t() and l() in specs without prefixing with I18n][i18n]
* An automatically-created `SECRET_KEY_BASE` environment variable in all
  environments
* The analytics adapter [Segment][segment] (and therefore config for Google
  Analytics, Intercom, Facebook Ads, Twitter Ads, etc.)


## Heroku

You can optionally create Heroku staging and production apps:

    suspenders app  * heroku true

This:

* Creates a staging and production Heroku app
* Sets them as `staging` and `production` Git remotes
* Configures staging with `RACK_ENV` and `RAILS_ENV` environment variables set
  to `staging`
* Adds the [Rails Stdout Logging][logging-gem] gem
  to configure the app to log to standard out,
  which is how [Heroku's logging][heroku-logging] works.
* Creates a [Heroku Pipeline] for review apps

[logging-gem]: https://github.com/heroku/rails_stdout_logging
[heroku-logging]: https://devcenter.heroku.com/articles/logging#writing-to-your-log
[Heroku Pipeline]: https://devcenter.heroku.com/articles/pipelines

You can optionally specify alternate Heroku flags:

    suspenders app \
       * heroku true \
       * heroku-flags " * region eu  * addons newrelic,sendgrid,ssl"

See all possible Heroku flags:

    heroku help create

## Git

This will initialize a new git repository for your Rails app. You can
bypass this with the ` * skip-git` option:

    suspenders app  * skip-git true

## GitHub

You can optionally create a GitHub repository for the suspended Rails app. It
requires that you have [Hub](https://github.com/github/hub) on your system:

    curl http://hub.github.com/standalone -sLo ~/bin/hub && chmod +x ~/bin/hub
    suspenders app  * github organization/project

This has the same effect as running:

    hub create organization/project

## Spring

Suspenders uses [spring](https://github.com/rails/spring) by default.
It makes Rails applications load faster, but it might introduce confusing issues
around stale code not being refreshed.
If you think your application is running old code, run `spring stop`.
And if you'd rather not use spring, add `DISABLE_SPRING=1` to your login file.

## Dependencies

Suspenders requires the latest version of Ruby.

Some gems included in Suspenders have native extensions. You should have GCC
installed on your machine before generating an app with Suspenders.

Use [OS X GCC Installer](https://github.com/kennethreitz/osx-gcc-installer/) for
Snow Leopard (OS X 10.6).

Use [Command Line Tools for XCode](https://developer.apple.com/downloads/index.action)
for Lion (OS X 10.7) or Mountain Lion (OS X 10.8).

We use [Capybara Webkit](https://github.com/thoughtbot/capybara-webkit) for
full-stack JavaScript integration testing. It requires QT. Instructions for
installing QT are
[here](https://github.com/thoughtbot/capybara-webkit/wiki/Installing-Qt-and-compiling-capybara-webkit).

PostgreSQL needs to be installed and running for the `db:create` rake task.


## License

MIT Licence
