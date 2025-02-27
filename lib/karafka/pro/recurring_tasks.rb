# frozen_string_literal: true

# This Karafka component is a Pro component under a commercial license.
# This Karafka component is NOT licensed under LGPL.
#
# All of the commercial components are present in the lib/karafka/pro directory of this
# repository and their usage requires commercial license agreement.
#
# Karafka has also commercial-friendly license, commercial support and commercial components.
#
# By sending a pull request to the pro components, you are agreeing to transfer the copyright of
# your code to Maciej Mensfeld.

module Karafka
  module Pro
    # Recurring tasks functionality
    module RecurringTasks
      class << self
        # @return [Schedule, nil] current defined schedule or nil if not defined
        def schedule
          @schedule || define('0.0.0') {}
        end

        # Simplified API for schedules definitions
        #
        # @param version [String]
        # @param block [Proc]
        #
        # @example
        #   Karafka::Pro::RecurringTasks.define('1.0.1') do
        #     schedule(id: 'mailer', cron: '* * * * *') do
        #       MailingJob.perform_async
        #     end
        #   end
        def define(version = '1.0.0', &block)
          @schedule = Schedule.new(version: version)
          @schedule.instance_exec(&block)
        end

        # Defines nice command methods to dispatch cron requests
        Executor::COMMANDS.each do |command_name|
          class_eval <<~RUBY, __FILE__, __LINE__ + 1
            # @param task_id [String] task to which we want to dispatch command or '*' if to all
            def #{command_name}(task_id)
              Dispatcher.command('#{command_name}', task_id)
            end
          RUBY
        end

        # Below are private APIs

        # Sets up additional config scope, validations and other things
        #
        # @param config [Karafka::Core::Configurable::Node] root node config
        def pre_setup(config)
          # Expand the config with this feature specific stuff
          config.instance_eval do
            setting(:recurring_tasks, default: Setup::Config.config)
          end
        end

        # @param config [Karafka::Core::Configurable::Node] root node config
        def post_setup(config)
          RecurringTasks::Contracts::Config.new.validate!(config.to_h)

          # Published after task is successfully executed
          Karafka.monitor.notifications_bus.register_event('recurring_tasks.task.executed')

          # Initialize empty dummy schedule, so we always have one and so we do not have to
          # deal with a case where there is no schedule
          RecurringTasks.schedule

          # User can disable logging of executions, in which case we don't track them
          return unless Karafka::App.config.recurring_tasks.logging

          Karafka.monitor.subscribe(Listener.new)
        end
      end
    end
  end
end
